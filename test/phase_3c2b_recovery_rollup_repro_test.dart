// Phase 3C2B recovery/rollup reproduction.
// All database rows and sensor samples are synthetic and isolated in sqflite-ffi.
//
// B3 note: there is no controllable failure-injection seam for the cross-day
// isolate. Do not turn an arbitrary malformed input into a claimed runtime
// failure case; the production catch/retry path remains uncharacterized here.
// B4 note: repository reads can be compared with persisted values below, but
// this historical-day fixture cannot exercise the Today-only frozen headline.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/series_codec.dart';
import 'package:openstrap_edge/state/app_state.dart';

const _dbName = 'phase_3c2b_recovery_rollup_repro.db';
const _profile = <String, dynamic>{
  'age': 35,
  'sex': 'm',
  'weight_kg': 75,
  'height_cm': 178,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = _dbName;
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
  });

  setUp(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
  });

  test('B1 correction replaces day outputs and refreshes 3-day rollup', () async {
    const sentinelKey = 'phase_3c2b_b1_prior_artifact_sentinel_7f28d2c1';
    const sentinelValue = 'replaced-only-by-production-rollup';
    final days =
        _recentWeekendDays(); // Saturday, Sunday, Monday; all synthetic.
    final records = <Map<String, dynamic>>[];
    for (var i = 0; i < days.length; i++) {
      records.add(_syntheticDayRecord(days[i], index: i));
      await _seedDayResult(records.last);
    }
    await _storeCrossDay(records);
    final seededCrossday = _decodeJson(
      (await LocalDb.baseline('crossday'))!['payload_json'],
    )..[sentinelKey] = sentinelValue;
    await LocalDb.putBaseline('crossday', jsonEncode(seededCrossday));
    await _insertSyntheticWindow(days.first);

    final beforeRow = (await LocalDb.dayResult(days.first))!;
    final beforePayload = _decodePayload(beforeRow);
    final beforeDay = _dayOutputs(beforePayload);
    final beforeCrossday = _decodeJson(
      (await LocalDb.baseline('crossday'))!['payload_json'],
    );
    expect(beforeCrossday[sentinelKey], sentinelValue);

    final app = _testApp();
    addTearDown(app.dispose);
    final onset = _localTime(days.first, hour: 0, minute: 15);
    final offset = _localTime(days.first, hour: 7, minute: 15);
    await app.setSleepOverride(days.first, onset, offset);

    final afterRow = (await LocalDb.dayResult(days.first))!;
    final afterPayload = _decodePayload(afterRow);
    final afterDay = _dayOutputs(afterPayload);
    final afterCrossday = _decodeJson(
      (await LocalDb.baseline('crossday'))!['payload_json'],
    );
    final afterCrossdayInput = _decodeJson(
      (await LocalDb.baseline('crossday_input'))!['payload_json'],
    );
    final crossdayInputDay = (afterCrossdayInput['days'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['date'] == days.first);
    final series = <String, double?>{
      for (final key in const ['rhr', 'rmssd', 'readiness', 'strain', 'trimp'])
        key: await LocalDb.metricValueOn(days.first, key),
    };
    final displayedSleep = await app.repo!.getDaySleep(days.first);
    final displayedHeart = await app.repo!.getDayHeart(days.first);

    expect(afterPayload['sleep_source'], 'manual');
    expect(afterRow['payload_json'], isNot(beforeRow['payload_json']));
    expect(afterDay['window_onset_ms'], isNot(beforeDay['window_onset_ms']));
    expect(afterDay['window_offset_ms'], isNot(beforeDay['window_offset_ms']));
    const accountingKeys = [
      'tst_sec',
      'in_bed_sec',
      'waso_sec',
      'light_sec',
      'deep_sec',
      'rem_sec',
    ];
    expect(
      accountingKeys.any((key) => beforeDay[key] != afterDay[key]),
      isTrue,
      reason: 'the corrected window must change persisted sleep accounting',
    );
    expect(afterDay['tst_sec'], isA<num>());
    expect(
      afterCrossday.containsKey(sentinelKey),
      isFalse,
      reason: 'the production rollup must replace the seeded prior artifact',
    );
    expect(afterCrossday['n_days'], 3);
    expect(afterCrossday['built_for_day'], LocalDb.localDayLabelNow());
    expect(
      crossdayInputDay['onset_sec'],
      ((afterDay['window_onset_ms'] as num) / 1000).round(),
    );
    expect(
      crossdayInputDay['wake_sec'],
      ((afterDay['window_offset_ms'] as num) / 1000).round(),
    );
    expect(
      crossdayInputDay['tst_min'],
      ((afterDay['tst_sec'] as num) / 60).round(),
    );
    expect(displayedSleep['sleep_source'], 'manual');
    expect(displayedSleep['has_sleep'], isTrue);
    expect(displayedHeart['recovery'], afterDay['readiness']);
    if ((afterRow['partial'] as num?) != 1) {
      expect(series['readiness'], afterDay['readiness']);
      expect(series['rhr'], afterDay['rhr']);
      expect(series['rmssd'], afterDay['rmssd']);
      expect(series['strain'], afterDay['strain']);
    }

    // Values are emitted for the central serial test run; absent or unchanged
    // metrics are valid observations and are not asserted to move.
    // ignore: avoid_print
    print(
      'PHASE 3C2B B1 ${jsonEncode({'day': days.first, 'before': beforeDay, 'after': afterDay, 'series_after': series, 'displayed_sleep': _displayedSleepOutputs(displayedSleep), 'displayed_recovery': displayedHeart['recovery'], 'crossday_before': _crossDayOutputs(beforeCrossday), 'crossday_after': _crossDayOutputs(afterCrossday), 'crossday_input_after': crossdayInputDay, 'rollup_replaced_sentinel': !afterCrossday.containsKey(sentinelKey)})}',
    );
  });

  test(
    'B2 fewer than 3 rollup inputs leave the fresh prior artifact readable',
    () async {
      final days = _recentWeekendDays();
      final records = [
        for (var i = 0; i < days.length; i++)
          _syntheticDayRecord(days[i], index: i),
      ];
      await _seedDayResult(records[0]);
      await _seedDayResult(records[1]);
      await _storeCrossDay(records, marker: 'prior-three-day-rollup');
      await _insertSyntheticWindow(days.first);

      final before = (await LocalDb.baseline('crossday'))!['payload_json'];
      final app = _testApp();
      addTearDown(app.dispose);
      await app.setSleepOverride(
        days.first,
        _localTime(days.first, hour: 0, minute: 15),
        _localTime(days.first, hour: 7, minute: 15),
      );

      final inputArtifact = _decodeJson(
        (await LocalDb.baseline('crossday_input'))!['payload_json'],
      );
      final after = (await LocalDb.baseline('crossday'))!['payload_json'];
      final displayed = await app.repo!.getInsights();
      expect((inputArtifact['days'] as List), hasLength(2));
      expect(
        after,
        before,
        reason: '_runCrossDay skips without replacing the prior bundle',
      );
      expect(displayed['fixture_marker'], 'prior-three-day-rollup');
      expect(displayed['n_days'], 3);

      // ignore: avoid_print
      print(
        'PHASE 3C2B B2 ${jsonEncode({'rollup_input_days': (inputArtifact['days'] as List).length, 'stored_rollup_after_skip': _crossDayOutputs(_decodeJson(after)), 'repository_still_serves_prior': displayed['fixture_marker']})}',
      );
    },
  );
}

AppState _testApp() {
  final app = AppState.forTesting();
  app.user = Map<String, dynamic>.from(_profile);
  app.repo = LocalRepositoryImpl(getProfileMap: () => app.user ?? const {});
  return app;
}

List<String> _recentWeekendDays() {
  final now = DateTime.now();
  final thisMonday = DateTime(now.year, now.month, now.day - now.weekday + 1);
  final lastMonday = thisMonday.subtract(const Duration(days: 7));
  return [
    dayLabelOf(lastMonday.subtract(const Duration(days: 2))),
    dayLabelOf(lastMonday.subtract(const Duration(days: 1))),
    dayLabelOf(lastMonday),
  ];
}

DateTime _localTime(String dayId, {required int hour, required int minute}) {
  final parts = dayId.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], hour, minute);
}

Map<String, dynamic> _syntheticDayRecord(String dayId, {required int index}) {
  final durationHours = const [7.0, 7.5, 7.0][index];
  final onset = _localTime(dayId, hour: 0, minute: 30 + (index * 5));
  final onsetSec = onset.millisecondsSinceEpoch ~/ 1000;
  final offsetSec = onsetSec + (durationHours * 3600).round();
  final inBedSec = offsetSec - onsetSec;
  final tstSec = (durationHours * 3600).round();
  final lightSec = (tstSec * 0.55).round();
  final deepSec = (tstSec * 0.20).round();
  final remSec = tstSec - lightSec - deepSec;
  return {
    'date': dayId,
    'onset_sec': onsetSec,
    'wake_sec': offsetSec,
    'tst_min': tstSec ~/ 60,
    'in_bed_sec': inBedSec,
    'tst_sec': tstSec,
    'light_sec': lightSec,
    'deep_sec': deepSec,
    'rem_sec': remSec,
    'rhr': 54.0 + index,
    'rmssd': 38.0 + (index * 3),
    'readiness': 64.0 + (index * 4),
    'strain': 3.0 + index,
    'trimp': 12.0 + (index * 2),
    'efficiency': 0.94,
  };
}

Future<void> _seedDayResult(Map<String, dynamic> record) async {
  final dayId = record['date'] as String;
  final onsetSec = record['onset_sec'] as int;
  final offsetSec = record['wake_sec'] as int;
  final inBedSec = record['in_bed_sec'] as int;
  final tstSec = record['tst_sec'] as int;
  final payload = <String, dynamic>{
    'date': dayId,
    'scalars': {
      for (final key in const ['rhr', 'rmssd', 'readiness', 'strain', 'trimp'])
        key: record[key],
      'efficiency': record['efficiency'],
    },
    'sleep_source': 'auto',
    'sleep': {
      'window': {
        'value': {
          'onset_ms': onsetSec * 1000,
          'offset_ms': offsetSec * 1000,
          'spt_sec': inBedSec,
        },
        'confidence': 0.9,
      },
      'accounting': {
        'value': {
          'tst_sec': tstSec,
          'in_bed_sec': inBedSec,
          'observed_in_bed_sec': inBedSec,
          'waso_sec': inBedSec - tstSec,
          'efficiency_pct': (tstSec / inBedSec) * 100,
          'light_sec': record['light_sec'],
          'deep_sec': record['deep_sec'],
          'rem_sec': record['rem_sec'],
          'nrem_sec':
              (record['light_sec'] as int) + (record['deep_sec'] as int),
          'unobserved_sec': 0,
        },
        'confidence': 0.8,
      },
    },
    'series': {'hypnogram': const <Map<String, Object>>[]},
  };
  await LocalDb.putDayResult(
    dayId: dayId,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode(payload),
    windowJson: jsonEncode({
      'onset_ms': onsetSec * 1000,
      'offset_ms': offsetSec * 1000,
    }),
    finalized: true,
    rhr: (record['rhr'] as num).toDouble(),
    rmssd: (record['rmssd'] as num).toDouble(),
    readiness: (record['readiness'] as num).toDouble(),
    series: {
      'rhr': (record['rhr'] as num).toDouble(),
      'rmssd': (record['rmssd'] as num).toDouble(),
      'readiness': (record['readiness'] as num).toDouble(),
      'strain': (record['strain'] as num).toDouble(),
      'trimp': (record['trimp'] as num).toDouble(),
    },
  );
}

Future<void> _storeCrossDay(
  List<Map<String, dynamic>> records, {
  String? marker,
}) async {
  final days = [
    for (final r in records)
      {
        'date': r['date'],
        'onset_sec': r['onset_sec'],
        'wake_sec': r['wake_sec'],
        'tst_min': r['tst_min'],
        'sleep_coverage': 1.0,
        'rhr': r['rhr'],
        'rmssd': r['rmssd'],
        'readiness': r['readiness'],
        'strain': r['strain'],
        'trimp': r['trimp'],
        'efficiency': r['efficiency'],
        'hypnogram': const <Map<String, Object>>[],
      },
  ]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  final bundle = buildCrossDayBundle(days, _profile)
    ..['algo_version'] = kAlgoVersion
    ..['built_for_day'] = LocalDb.localDayLabelNow()
    ..['built_at_epoch'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (marker != null) bundle['fixture_marker'] = marker;
  await LocalDb.putBaseline('crossday', jsonEncode(bundle));
}

Future<void> _insertSyntheticWindow(String dayId) async {
  // One 10-hour, same-local-day sensor span. The corrected sleep window is
  // 00:15–07:15; the rest of the capture provides baseline and wake samples.
  final start = _localTime(dayId, hour: 0, minute: 0);
  final startSec = start.millisecondsSinceEpoch ~/ 1000;
  final db = await LocalDb.instance;
  var counter = 0;
  var batch = db.batch();
  var pending = 0;
  Future<void> flush() async {
    if (pending == 0) return;
    await batch.commit(noResult: true);
    batch = db.batch();
    pending = 0;
  }

  for (var i = 0; i < 10 * 3600; i++) {
    final ts = startSec + i;
    final asleep = i >= 30 * 60 && i < 6 * 3600;
    final hrBase = i < 30 * 60 ? 74 : (asleep ? 52 : 82);
    final hr = (hrBase + 2 * math.sin(i / (asleep ? 1800.0 : 120.0))).round();
    var ax = 0.02;
    var ay = 0.02;
    var az = 1.0;
    if (!asleep) {
      final phase = math.sin(i * 0.5);
      ax = 0.3 * phase;
      ay = 0.3;
      az = 0.9 * (1 - 0.2 * phase);
    }
    batch.insert('decoded_onehz', {
      'device_id': LocalDb.kPrimaryDeviceId,
      'ts_ms': ts * 1000,
      'rec_ts': ts,
      'counter': counter++,
      'hr': hr,
      'ax': ax,
      'ay': ay,
      'az': az,
      'device_family': 'gen4',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final rrMs = (60000 / hr).round() + ((i % 7) - 3);
    batch.insert('decoded_rr', {
      'device_id': LocalDb.kPrimaryDeviceId,
      'ts_ms': ts * 1000,
      'rec_ts': ts,
      'beat_index': 0,
      'rr_ts_ms': ts * 1000,
      'rr_ms': rrMs,
      'device_family': 'gen4',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    pending += 2;
    if (pending >= 4000) await flush();
  }
  await flush();
}

Map<String, dynamic> _decodePayload(Map<String, dynamic> row) =>
    SeriesCodec.decodePayloadJson(row['payload_json'])!;

Map<String, dynamic> _decodeJson(Object? raw) =>
    (jsonDecode(raw as String) as Map).cast<String, dynamic>();

Map<String, dynamic> _dayOutputs(Map<String, dynamic> payload) {
  final scalars = (payload['scalars'] as Map?)?.cast<String, dynamic>() ?? {};
  final sleep = (payload['sleep'] as Map?)?.cast<String, dynamic>() ?? {};
  final account =
      ((sleep['accounting'] as Map?)?['value'] as Map?)
          ?.cast<String, dynamic>() ??
      {};
  final window =
      ((sleep['window'] as Map?)?['value'] as Map?)?.cast<String, dynamic>() ??
      {};
  return {
    'sleep_source': payload['sleep_source'],
    'window_onset_ms': window['onset_ms'],
    'window_offset_ms': window['offset_ms'],
    'tst_sec': account['tst_sec'],
    'in_bed_sec': account['in_bed_sec'],
    'waso_sec': account['waso_sec'],
    'light_sec': account['light_sec'],
    'deep_sec': account['deep_sec'],
    'rem_sec': account['rem_sec'],
    'rhr': scalars['rhr'],
    'rmssd': scalars['rmssd'],
    'readiness': scalars['readiness'],
    'strain': scalars['strain'],
    'trimp': scalars['trimp'],
  };
}

Map<String, dynamic> _displayedSleepOutputs(Map<String, dynamic> sleep) => {
  for (final key in const [
    'sleep_source',
    'duration_min',
    'in_bed_min',
    'awake_min',
    'light_min',
    'deep_min',
    'rem_min',
  ])
    key: sleep[key],
};

Map<String, dynamic> _crossDayOutputs(Map<String, dynamic> bundle) => {
  'n_days': bundle['n_days'],
  'sleep_debt': _path(bundle, const ['sleep_debt', 'value']),
  'sleep_need': _path(bundle, const ['sleep_coach', 'need', 'value']),
  'sleep_need_note': _path(bundle, const ['sleep_coach', 'need', 'note']),
  'strain_bonus_min': _path(bundle, const ['sleep_coach', 'strain_bonus_min']),
  'built_for_day': bundle['built_for_day'],
};

Object? _path(Object? value, List<String> parts) {
  var current = value;
  for (final part in parts) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}
