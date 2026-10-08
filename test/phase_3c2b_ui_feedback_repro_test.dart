// Phase 3C2B-A: synthetic UI feedback and refresh reproductions.
//
// These tests use a disposable sqflite-ffi database and synthetic day_result /
// decoded_onehz rows only. They never open the user's database or health data.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show clockOfTs;
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart' show buildTheme;

const _dbName = 'phase_3c2b_ui_feedback_repro.db';

class _GatedRejectAppState extends AppState {
  _GatedRejectAppState(this.syntheticRepo) : super.forTesting() {
    repo = syntheticRepo;
  }

  final _SyntheticSleepRepository syntheticRepo;

  final rejectFinished = Completer<void>();
  final allowRejectCallToReturn = Completer<void>();

  @override
  Future<void> rejectSleep(String date) async {
    if (!rejectFinished.isCompleted) rejectFinished.complete();
    await allowRejectCallToReturn.future;
  }

  Future<void> performRealReject(String date) => super.rejectSleep(date);
}

class _CorrectionAppState extends AppState {
  _CorrectionAppState(this.syntheticRepo) : super.forTesting() {
    repo = syntheticRepo;
  }

  final _SyntheticSleepRepository syntheticRepo;
  final correctionFinished = Completer<void>();

  @override
  Future<void> setSleepOverride(
    String date,
    DateTime onset,
    DateTime offset, {
    String source = 'manual',
  }) async {
    try {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final row = await binding.runAsync(() async {
        await _applyCorrection(date, onset, offset, source: source);
        return LocalDb.dayResult(date);
      });
      if (row == null) throw StateError('re-derived day result is missing');
      final payload = jsonDecode(row['payload_json'] as String) as Map;
      final sleep = payload['sleep'] as Map;
      final window = (sleep['window'] as Map)['value'] as Map;
      syntheticRepo.setNight(
        date,
        _epoch(
          DateTime.fromMillisecondsSinceEpoch(
            (window['onset_ms'] as num).toInt(),
          ),
        ),
        _epoch(
          DateTime.fromMillisecondsSinceEpoch(
            (window['offset_ms'] as num).toInt(),
          ),
        ),
        source: payload['sleep_source'] as String? ?? 'none',
      );
    } finally {
      if (!correctionFinished.isCompleted) correctionFinished.complete();
    }
  }

  Future<void> _applyCorrection(
    String date,
    DateTime onset,
    DateTime offset, {
    required String source,
  }) => super.setSleepOverride(date, onset, offset, source: source);
}

class _SyntheticSleepRepository extends LocalRepositoryImpl {
  _SyntheticSleepRepository(Map<String, _SyntheticNight> nights)
    : _nights = Map.of(nights),
      super(getProfileMap: () => const {});

  final Map<String, _SyntheticNight> _nights;
  int sleepV2ReadCount = 0;

  void setNight(String day, int onsetTs, int wakeTs, {required String source}) {
    _nights[day] = _SyntheticNight(onsetTs, wakeTs, source);
  }

  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': _nights.keys.first},
  };

  @override
  Future<List<String>> availableDays() async =>
      _nights.keys.toList()..sort((a, b) => b.compareTo(a));

  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async {
    sleepV2ReadCount++;
    return _nightMap(_nights[date]);
  }

  @override
  Future<Map<String, dynamic>> getDaySleep(String date) async =>
      _nightMap(_nights[date]);

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async => {};

  @override
  Future<Map<String, dynamic>> getInsights() async => {
    'sleep_coach': {},
    'sleep_debt': {},
  };

  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
    Set<String> signals = const {},
  }) async => {'points': <Map<String, Object>>[]};

  @override
  Future<List<Map<String, dynamic>>> sleepWindows({
    int days = 60,
    String? before,
  }) async => [];

  Map<String, dynamic> _nightMap(_SyntheticNight? night) {
    if (night == null) return {'has_sleep': false, 'sleep_source': 'none'};
    final inBedMin = (night.wakeTs - night.onsetTs) ~/ 60;
    return {
      'has_sleep': true,
      'sleep_source': night.source,
      'onset_ts': night.onsetTs,
      'wake_ts': night.wakeTs,
      'duration_min': inBedMin - 20,
      'in_bed_min': inBedMin,
      'awake_min': 20,
      'efficiency': 0.95,
      'light_min': (inBedMin - 20) ~/ 2,
      'deep_min': (inBedMin - 20) ~/ 5,
      'rem_min': (inBedMin - 20) ~/ 5,
      'hypnogram': [
        {'t': night.onsetTs, 'stage': 'light'},
        {'t': night.wakeTs, 'stage': 'awake'},
      ],
      'nocturnal': <String, Object>{},
    };
  }
}

class _SyntheticNight {
  const _SyntheticNight(this.onsetTs, this.wakeTs, this.source);

  final int onsetTs;
  final int wakeTs;
  final String source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = _dbName;
  });

  setUp(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, _dbName));
  });

  testWidgets(
    'A1 CURRENT UI DEFECT: a changed manual window is reported as unapplied',
    (t) async {
      _setViewport(t);
      final correctionDay = _localDayAgo(3);
      final (initialOnset, initialWake) = _window(correctionDay, 23, 0, 7, 0);
      final (correctedOnset, correctedWake) = _window(
        correctionDay,
        22,
        0,
        8,
        0,
      );
      await t.runAsync(() async {
        await _seedManualDay(
          correctionDay,
          onset: initialOnset,
          wake: initialWake,
        );
        await _insertSyntheticRows(correctionDay);
      });

      final syntheticRepo = _SyntheticSleepRepository({
        correctionDay: _SyntheticNight(
          _epoch(initialOnset),
          _epoch(initialWake),
          'manual',
        ),
      });
      final app = _CorrectionAppState(syntheticRepo);
      addTearDown(app.dispose);
      await t.pumpWidget(_app(app, SleepDetail(day: correctionDay)));

      final initialText = _windowText(initialOnset, initialWake);
      await _until(t, find.text(initialText));
      expect(find.text('You set this window'), findsOneWidget);

      await t.tap(find.text('Change the times'));
      await t.pump(const Duration(milliseconds: 400));
      await _choose24HourTime(t, hour: 22, minute: 0);
      await _choose24HourTime(t, hour: 8, minute: 0, settle: false);
      await app.correctionFinished.future;
      await t.pump();

      await _until(t, find.text('That correction has not been applied'));
      final storedOverride = await t.runAsync(
        () => LocalDb.getSleepOverride(correctionDay),
      );
      expect(storedOverride, isNotNull, reason: 'the manual edit must persist');
      expect(storedOverride?['source'], 'manual');
      expect(storedOverride?['onset_ts'], _epoch(correctedOnset));
      expect(storedOverride?['offset_ts'], _epoch(correctedWake));
      final storedSleep = await syntheticRepo.getDaySleepV2(correctionDay);
      final dayRow = (await t.runAsync(
        () => LocalDb.dayResult(correctionDay),
      ))!;
      final payload = jsonDecode(dayRow['payload_json'] as String) as Map;
      final persistedWindow =
          ((payload['sleep'] as Map)['window'] as Map)['value'];
      expect(persistedWindow, isA<Map>());
      final persistedWindowMap = persistedWindow as Map;

      expect(storedSleep['sleep_source'], 'manual');
      expect(storedSleep['onset_ts'], _epoch(correctedOnset));
      expect(storedSleep['wake_ts'], _epoch(correctedWake));
      expect(
        persistedWindowMap['onset_ms'],
        correctedOnset.millisecondsSinceEpoch,
      );
      expect(
        persistedWindowMap['offset_ms'],
        correctedWake.millisecondsSinceEpoch,
      );
      expect(
        find.text(_windowText(correctedOnset, correctedWake)),
        findsOneWidget,
      );
      expect(
        find.textContaining('The night was not re-analysed'),
        findsOneWidget,
        reason:
            'the correction persisted and the displayed window changed, '
            'but _runOverride treats the unchanged manual source as failure',
      );
    },
  );

  testWidgets(
    'A2 CURRENT UI DEFECT: SleepDetail stays stale after insightsRevision',
    (t) async {
      _setViewport(t);
      final day = _localDayAgo(3);
      final (oldOnset, oldWake) = _window(day, 23, 0, 7, 0);
      final (newOnset, newWake) = _window(day, 22, 0, 8, 0);
      final repo = _SyntheticSleepRepository({
        day: _SyntheticNight(_epoch(oldOnset), _epoch(oldWake), 'manual'),
      });
      final app = _testApp(repo);
      addTearDown(app.dispose);
      await t.pumpWidget(_app(app, SleepDetail(day: day)));

      final oldText = _windowText(oldOnset, oldWake);
      await _until(t, find.text(oldText));
      await t.pumpAndSettle();
      final screenState = t.state(find.byType(SleepDetail));
      final oldRevision = app.insightsRevision.value;
      final readsBeforeRevision = repo.sleepV2ReadCount;

      // A different writer replaces the repository's current day projection,
      // then raises the same revision signal used by production writers.
      repo.setNight(day, _epoch(newOnset), _epoch(newWake), source: 'manual');
      app.bumpInsights();
      // Drain the complete scheduled widget/microtask chain. A revision
      // listener that starts an asynchronous SleepData.load must have time to
      // read the new projection and schedule its resulting frame before the
      // stale-screen assertions below run.
      await t.pumpAndSettle();

      final readsAfterRevision = repo.sleepV2ReadCount;
      final stored = await repo.getDaySleepV2(day);
      expect(app.insightsRevision.value, oldRevision + 1);
      expect(stored['onset_ts'], _epoch(newOnset));
      expect(stored['wake_ts'], _epoch(newWake));
      expect(
        readsAfterRevision,
        readsBeforeRevision,
        reason: 'a working revision subscription would reload this night',
      );
      expect(
        find.text(oldText),
        findsOneWidget,
        reason: 'SleepDetail did not subscribe to insightsRevision',
      );
      expect(find.text(_windowText(newOnset, newWake)), findsNothing);
      expect(identical(t.state(find.byType(SleepDetail)), screenState), isTrue);
    },
  );

  testWidgets(
    'A3 CURRENT UI DEFECT: a pending correction can show failure on another day',
    (t) async {
      _setViewport(t);
      final correctionDay = _localDayAgo(3);
      final neighborDay = _localDayAgo(4);
      final (targetOnset, targetWake) = _window(correctionDay, 23, 0, 7, 0);
      final (neighborOnset, neighborWake) = _window(neighborDay, 23, 30, 7, 30);
      // This case isolates page feedback ordering. It persists the rejection
      // through AppState, but intentionally has no decoded rows; A1 covers the
      // retained-raw re-derive and persisted sleep-window result.
      final repo = _SyntheticSleepRepository({
        neighborDay: _SyntheticNight(
          _epoch(neighborOnset),
          _epoch(neighborWake),
          'manual',
        ),
        correctionDay: _SyntheticNight(
          _epoch(targetOnset),
          _epoch(targetWake),
          'manual',
        ),
      });
      final app = _GatedRejectAppState(repo);
      addTearDown(() async {
        if (!app.allowRejectCallToReturn.isCompleted) {
          app.allowRejectCallToReturn.complete();
        }
        app.dispose();
      });
      await t.pumpWidget(_app(app, SleepDetail(day: correctionDay)));

      final targetText = _windowText(targetOnset, targetWake);
      await _until(t, find.text(targetText));
      await t.tap(find.text('Not sleep'));
      await t.pump();

      // Hold the UI Future, move to the neighboring night, then execute the
      // real AppState rejection while the screen remains on that night. This
      // barrier makes the navigation/reload ordering deterministic.
      await app.rejectFinished.future;
      await t.tap(find.bySemanticsLabel('Previous day'));
      await t.pump();
      final neighborText = _windowText(neighborOnset, neighborWake);
      await _until(t, find.text(neighborText));
      await t.runAsync(() => app.performRealReject(correctionDay));
      final override = await t.runAsync(
        () => LocalDb.getSleepOverride(correctionDay),
      );
      expect(override?['source'], 'rejected');
      app.allowRejectCallToReturn.complete();

      await _until(t, find.text('That correction has not been applied'));
      expect(
        find.text(neighborText),
        findsOneWidget,
        reason: 'the visible screen is now the neighboring day',
      );
      expect(
        find.textContaining('The night was not re-analysed'),
        findsOneWidget,
      );
      expect(
        (await t.runAsync(
          () => LocalDb.getSleepOverride(correctionDay),
        ))?['source'],
        'rejected',
      );
    },
  );
}

void _setViewport(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 1700 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget _app(AppState app, Widget screen) => MaterialApp(
  theme: buildTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child!,
  ),
  home: ChangeNotifierProvider<AppState>.value(value: app, child: screen),
);

AppState _testApp(_SyntheticSleepRepository repo) {
  final app = AppState.forTesting();
  app.repo = repo;
  return app;
}

Future<void> _choose24HourTime(
  WidgetTester t, {
  required int hour,
  required int minute,
  bool settle = true,
}) async {
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await t.pump(const Duration(milliseconds: 400));
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(2));
  await t.enterText(fields.at(0), hour.toString().padLeft(2, '0'));
  await t.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await t.tap(find.text('OK'));
  if (settle) {
    await t.pump(const Duration(milliseconds: 400));
  } else {
    // Confirming the wake time starts the real re-derive. Its busy indicator
    // animates until the write Future finishes, so pump once and let the
    // caller wait for the resulting UI state instead of waiting for a settle.
    await t.pump();
  }
}

Future<void> _until(WidgetTester t, Finder finder, {int attempts = 250}) async {
  for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

(DateTime, DateTime) _window(
  String wakeDay,
  int onsetHour,
  int onsetMinute,
  int wakeHour,
  int wakeMinute,
) {
  final parts = wakeDay.split('-').map(int.parse).toList();
  final onset = DateTime(
    parts[0],
    parts[1],
    parts[2] - 1,
    onsetHour,
    onsetMinute,
  );
  final wake = DateTime(parts[0], parts[1], parts[2], wakeHour, wakeMinute);
  return (onset, wake);
}

int _epoch(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

String _localDayAgo(int daysAgo) =>
    dayLabelOf(DateTime.now().subtract(Duration(days: daysAgo)));

String _windowText(DateTime onset, DateTime wake) =>
    '${clockOfTs(_epoch(onset))} → ${clockOfTs(_epoch(wake))}';

Future<void> _seedManualDay(
  String day, {
  required DateTime onset,
  required DateTime wake,
}) async {
  final onsetMs = onset.millisecondsSinceEpoch;
  final wakeMs = wake.millisecondsSinceEpoch;
  final inBedSec = (wakeMs - onsetMs) ~/ 1000;
  final window = {
    'onset_ms': onsetMs,
    'offset_ms': wakeMs,
    'spt_sec': inBedSec,
  };
  await _insertDayResult(
    day,
    jsonEncode({
      'date': day,
      'sleep_source': 'manual',
      'scalars': const <String, Object>{},
      'sleep': {
        'window': {'value': window, 'confidence': 0.8},
        'accounting': {
          'value': {
            'tst_sec': inBedSec - 20 * 60,
            'waso_sec': 20 * 60,
            'efficiency_pct': 96,
            'in_bed_sec': inBedSec,
            'light_sec': inBedSec ~/ 2,
            'deep_sec': inBedSec ~/ 5,
            'rem_sec': inBedSec ~/ 5,
            'nrem_sec': inBedSec * 7 ~/ 10,
          },
          'confidence': 0.8,
        },
      },
    }),
    jsonEncode(window),
  );
}

Future<void> _insertDayResult(
  String day,
  String payloadJson,
  String windowJson,
) async {
  final db = await LocalDb.instance;
  await db.insert('day_result', {
    'day_id': day,
    'algo_version': kAlgoVersion,
    'payload_json': payloadJson,
    'window_json': windowJson,
    'computed_at': DateTime.now().millisecondsSinceEpoch,
    'finalized': 1,
    'skipped': 0,
    'partial': 0,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _insertSyntheticRows(String wakeDay) async {
  final parts = wakeDay.split('-').map(int.parse).toList();
  final start = DateTime(parts[0], parts[1], parts[2] - 1, 21);
  final end = DateTime(parts[0], parts[1], parts[2], 9);
  final startSec = _epoch(start);
  final endSec = _epoch(end);
  final db = await LocalDb.instance;
  var batch = db.batch();
  var counter = 0;
  var pending = 0;
  Future<void> flush() async {
    if (pending == 0) return;
    await batch.commit(noResult: true);
    batch = db.batch();
    pending = 0;
  }

  for (var ts = startSec; ts <= endSec; ts++) {
    batch.insert('decoded_onehz', {
      'device_id': LocalDb.kPrimaryDeviceId,
      'ts_ms': ts * 1000,
      'rec_ts': ts,
      'counter': counter++,
      'hr': 54,
      'ax': 0.02,
      'ay': 0.01,
      'az': 0.999,
      'hr_valid': 1,
      'on_wrist': 1,
      'device_family': 'gen4',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    pending++;
    if (pending >= 2000) await flush();
  }
  await flush();
}
