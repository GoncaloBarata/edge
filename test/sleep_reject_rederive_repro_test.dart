// Phase 3C2A reproduction: exercise the production AppState rejection path and
// compare the persisted override with the day_result served to the UI.
//
// All rows live in this test's dedicated sqflite-ffi database and are synthetic.
// No user profile, private-data directory, or health record is opened.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/state/app_state.dart';

const _dbName = 'phase_3c2a_sleep_reject_rederive_repro.db';
const _syntheticReadiness = 74.0;
// Fixed local calendar labels keep fixture selection independent of wall time.
// The 30-day gap in the prune case is measured against its own synthetic edge.
const _retainedWakeDay = '2025-06-16';
const _prunedWakeDay = '2025-05-01';
const _pruneEdgeDay = '2025-05-31';

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
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
  });

  test(
    'retained synthetic sensor data lets Not sleep replace the day result',
    () async {
      final day = _retainedWakeDay;
      final (onsetSec, offsetSec) = _syntheticSleepWindow(day);
      await _seedDerivedSleep(day, onsetSec: onsetSec, offsetSec: offsetSec);
      final retainedRows = await _insertSyntheticDecodedDay(day, stepSec: 10);
      expect(
        retainedRows,
        greaterThan(1000),
        reason: 'fixture has retained data',
      );

      final before = (await LocalDb.dayResult(day))!;
      final beforeSleep = await _sleepFromRepository(day);
      expect(
        beforeSleep['has_sleep'],
        isTrue,
        reason: 'precondition: seeded night',
      );
      expect(beforeSleep['sleep_source'], 'auto');

      final app = _testApp();
      addTearDown(app.dispose);
      await app.rejectSleep(day);

      final override = await LocalDb.getSleepOverride(day);
      expect(override?['source'], 'rejected');
      expect(override?['day_id'], day);

      final after = (await LocalDb.dayResult(day))!;
      final afterBundle = jsonDecode(after['payload_json'] as String) as Map;
      final afterSleep = await _sleepFromRepository(day);
      expect(afterSleep['has_sleep'], isFalse);
      expect(afterSleep['sleep_source'], 'rejected');
      expect(afterBundle['sleep_source'], 'rejected');
      expect(after['payload_json'], isNot(before['payload_json']));
      expect(
        await _decodedCountForDay(day),
        retainedRows,
        reason: 'the successful correction does not delete the fixture rows',
      );

      // Clearing removes the override and runs automatic derivation again.
      // This fixture has flat all-day HR and stillness, so the observed result
      // is no sleep (`has_sleep=false`, `sleep_source=none`). It proves that
      // undo removes the rejected state; it does not prove automatic sleep was
      // restored from this synthetic sensor input.
      await app.clearSleepOverride(day);
      expect(await LocalDb.getSleepOverride(day), isNull);
      final cleared = await _sleepFromRepository(day);
      expect(cleared['has_sleep'], isFalse);
      expect(cleared['sleep_source'], 'none');
    },
  );

  test(
    'CURRENT DEFECT CHARACTERIZATION: pruned day stores rejection but keeps its night',
    () async {
      final oldDay = _prunedWakeDay;
      final edgeDay = _pruneEdgeDay;
      final (onsetSec, offsetSec) = _syntheticSleepWindow(oldDay);
      await _seedDerivedSleep(oldDay, onsetSec: onsetSec, offsetSec: offsetSec);
      await _seedFinalizedMarker(edgeDay);
      final oldBefore = (await LocalDb.dayResult(oldDay))!;
      final oldPayload = oldBefore['payload_json'] as String;
      final edgeBefore = (await LocalDb.dayResult(edgeDay))!['payload_json'];
      expect(
        await _decodedCountForDay(oldDay),
        0,
        reason: 'historical decoded substrate is already pruned',
      );

      // A finalized synthetic edge gives run() a positive data timestamp, while
      // keeping its raw day out of the re-derive todo set. The old day has no
      // decoded rows and therefore is absent from _deriveScope.targetDays.
      await _insertSyntheticDecodedDay(edgeDay, stepSec: 86400);
      final edgeCountBefore = await _decodedCountForDay(edgeDay);
      expect(edgeCountBefore, 1);

      final beforeSleep = await _sleepFromRepository(oldDay);
      expect(
        beforeSleep['has_sleep'],
        isTrue,
        reason: 'precondition: seeded history',
      );
      final app = _testApp();
      addTearDown(app.dispose);

      await app.rejectSleep(oldDay);

      final override = await LocalDb.getSleepOverride(oldDay);
      expect(override?['source'], 'rejected');
      final afterReject = (await LocalDb.dayResult(oldDay))!;
      final observedSleep = await _sleepFromRepository(oldDay);
      expect(
        afterReject['payload_json'],
        oldPayload,
        reason:
            'CURRENT BEHAVIOR: the pruned day is outside decodedRecTsMaxByDay '
            'scope, so the forced re-derive leaves the finalized day_result intact',
      );
      expect(
        observedSleep['has_sleep'],
        isTrue,
        reason: 'CURRENT BEHAVIOR: stored rejection and served night disagree',
      );
      expect(observedSleep['sleep_source'], 'auto');
      expect(await _decodedCountForDay(oldDay), 0);
      expect(
        await _decodedCountForDay(edgeDay),
        edgeCountBefore,
        reason: 'synthetic edge row remains intact',
      );
      expect(
        (await LocalDb.dayResult(edgeDay))?['payload_json'],
        edgeBefore,
        reason: 'the pre-finalized synthetic edge result is unchanged',
      );

      // Clearing is also safe to call, but it cannot regenerate a pruned day.
      // The historical bundle remains unchanged until substrate is restored or
      // another explicit data source supplies a replacement.
      await app.clearSleepOverride(oldDay);
      expect(await LocalDb.getSleepOverride(oldDay), isNull);
      expect((await LocalDb.dayResult(oldDay))?['payload_json'], oldPayload);
      expect((await _sleepFromRepository(oldDay))['has_sleep'], isTrue);
      expect(
        await LocalDb.metricValueOn(oldDay, 'readiness'),
        _syntheticReadiness,
        reason: 'the synthetic historical metric remains intact',
      );
    },
  );
}

AppState _testApp() {
  final app = AppState.forTesting();
  app.repo = LocalRepositoryImpl(getProfileMap: () => const {});
  return app;
}

DateTime _localStart(String day) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

(int onsetSec, int offsetSec) _syntheticSleepWindow(String wakeDay) {
  final wake = _localStart(wakeDay);
  final onset = DateTime(wake.year, wake.month, wake.day - 1, 22, 30);
  final offset = DateTime(wake.year, wake.month, wake.day, 7, 0);
  return (
    onset.millisecondsSinceEpoch ~/ 1000,
    offset.millisecondsSinceEpoch ~/ 1000,
  );
}

Future<void> _seedDerivedSleep(
  String day, {
  required int onsetSec,
  required int offsetSec,
}) async {
  await LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode({
      'scalars': {'readiness': _syntheticReadiness},
      'sleep_source': 'auto',
      'sleep': {
        'window': {
          'value': {
            'onset_ms': onsetSec * 1000,
            'offset_ms': offsetSec * 1000,
            'spt_sec': offsetSec - onsetSec,
          },
          'confidence': 0.8,
        },
        'accounting': {
          'value': {
            'tst_sec': offsetSec - onsetSec,
            'waso_sec': 0,
            'efficiency_pct': 100,
          },
          'confidence': 0.8,
        },
      },
    }),
    windowJson: jsonEncode({
      'onset_ms': onsetSec * 1000,
      'offset_ms': offsetSec * 1000,
    }),
    finalized: true,
    readiness: _syntheticReadiness,
    series: const {'readiness': _syntheticReadiness},
  );
}

Future<void> _seedFinalizedMarker(String day) async {
  await LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode({
      'scalars': <String, Object>{},
      'sleep_source': 'auto',
    }),
    windowJson: '{}',
    finalized: true,
  );
}

Future<int> _insertSyntheticDecodedDay(
  String day, {
  required int stepSec,
}) async {
  final db = await LocalDb.instance;
  final start = _localStart(day);
  final end = DateTime(start.year, start.month, start.day + 1);
  final startSec = start.millisecondsSinceEpoch ~/ 1000;
  final endSec = end.millisecondsSinceEpoch ~/ 1000;
  final batch = db.batch();
  var counter = 0;
  for (var ts = startSec; ts < endSec; ts += stepSec) {
    batch.insert('decoded_onehz', {
      'device_id': LocalDb.kPrimaryDeviceId,
      'ts_ms': ts * 1000,
      'rec_ts': ts,
      'counter': counter++,
      'hr': 58,
      'ax': 0.01,
      'ay': 0.01,
      'az': 0.9999,
      'hr_valid': 1,
      'on_wrist': 1,
      'device_family': 'gen4',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
  return counter;
}

Future<int> _decodedCountForDay(String day) async {
  final db = await LocalDb.instance;
  final start = _localStart(day).millisecondsSinceEpoch ~/ 1000;
  final endDate = _localStart(day);
  final end =
      DateTime(
        endDate.year,
        endDate.month,
        endDate.day + 1,
      ).millisecondsSinceEpoch ~/
      1000;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM decoded_onehz WHERE rec_ts >= ? AND rec_ts < ?',
    [start, end],
  );
  return (rows.single['n'] as num).toInt();
}

Future<Map<String, dynamic>> _sleepFromRepository(String day) async {
  final repo = LocalRepositoryImpl(getProfileMap: () => const {});
  return repo.getDaySleep(day);
}
