import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/investigate.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day1 = '2026-08-16';
const _day2 = '2026-08-15';

class _SnapshotRepo extends LocalRepository {
  _SnapshotRepo({this.sleepGate, this.day2HrvGate});

  final Completer<Map<String, dynamic>>? sleepGate;
  final Completer<void>? day2HrvGate;
  final sleepDays = <String>[];
  final hrvDays = <String>[];
  final heartDays = <String>[];
  final wearDays = <String>[];
  final lungsDays = <String>[];

  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': _day1},
  };

  @override
  Future<List<String>> availableDays() async => const [_day1, _day2];

  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) {
    sleepDays.add(date);
    final gate = sleepGate;
    if (gate != null && !gate.isCompleted) return gate.future;
    return Future.value({
      'has_sleep': true,
      'sleep_source': 'manual',
      'duration_min': 420,
      'stages_confidence': 0.72,
    });
  }

  @override
  Future<Map<String, dynamic>> getDayHrv(String date) async {
    hrvDays.add(date);
    final gate = day2HrvGate;
    if (date == _day2 && gate != null) await gate.future;
    return {
      'rmssd': 32.0,
      'device_family': 'gen4',
      'hrv_time': {'confidence': 0.8, 'note': null},
      'coverage': {'rr_beats': 300, 'nn_clean': 270, 'clean_fraction': 0.9},
    };
  }

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async {
    heartDays.add(date);
    return {'recovery': 0};
  }

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async {
    wearDays.add(date);
    return {'worn_min': 0, 'coverage_pct': 0};
  }

  @override
  Future<Map<String, dynamic>> getDayLungs(String date) async {
    lungsDays.add(date);
    return {
      'resp': {'value': 15.2, 'confidence': 0.8, 'note': null},
    };
  }

  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
    Set<String> signals = const {},
  }) async => const {'points': []};
}

Future<AppState> _pumpInvestigate(
  WidgetTester tester, {
  required _SnapshotRepo repo,
  required InvestigateData? data,
  String? day,
}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final app = AppState.forTesting()..repo = repo;
  addTearDown(app.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<AppState>.value(
        value: app,
        child: Investigate('hrv', day: day, data: data),
      ),
    ),
  );
  return app;
}

Future<void> _revealCopyButton(WidgetTester tester) async {
  final button = find.byKey(
    const ValueKey('investigate-copy-support-snapshot'),
  );
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 30; i++) {
    if (button.evaluate().isNotEmpty) {
      await tester.ensureVisible(button);
      await tester.pump();
      return;
    }
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for the loaded support snapshot action');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for the requested Investigate state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clipboardCalls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    LocalDb.dbName = 'support_snapshot_ui_test.db';
    databasePath = p.join(
      await databaseFactory.getDatabasesPath(),
      LocalDb.dbName,
    );
    await databaseFactory.deleteDatabase(databasePath);
    await LocalDb.instance;
    await LocalDb.putDayResult(
      dayId: _day2,
      algoVersion: 109,
      payloadJson: '{}',
      windowJson: '{}',
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'OpenStrap',
      packageName: 'org.openstrap.edge',
      version: '0.10.0',
      buildNumber: '67',
      buildSignature: 'test-signature',
    );
    clipboardCalls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map;
        clipboardCalls.add(arguments['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  InvestigateData readyData({String day = _day1}) =>
      InvestigateData(day: day, days: const [_day1, _day2], algoVersion: 109);

  testWidgets('copies the snapshot for the displayed selected day', (
    tester,
  ) async {
    final repo = _SnapshotRepo();
    await _pumpInvestigate(tester, repo: repo, data: readyData());
    final button = find.byKey(
      const ValueKey('investigate-copy-support-snapshot'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expect(
      clipboardCalls.single,
      contains('Selected local day: Present ($_day1)'),
    );
    expect(clipboardCalls.single, contains('Data source: On-device derived'));
    expect(repo.sleepDays, [_day1]);
    expect(repo.hrvDays, [_day1]);
    expect(repo.heartDays, [_day1]);
    expect(repo.wearDays, [_day1]);
    expect(repo.lungsDays, [_day1]);
  });

  testWidgets('snapshot action is unavailable while Investigate is loading', (
    tester,
  ) async {
    final repo = _SnapshotRepo();
    await _pumpInvestigate(tester, repo: repo, data: null, day: _day1);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey('investigate-copy-support-snapshot')),
      findsNothing,
    );
    expect(clipboardCalls, isEmpty);
  });

  testWidgets('mismatched data and selected day cannot be copied', (
    tester,
  ) async {
    final repo = _SnapshotRepo();
    await _pumpInvestigate(
      tester,
      repo: repo,
      data: readyData(day: _day1),
      day: _day2,
    );

    expect(
      find.byKey(const ValueKey('investigate-copy-support-snapshot')),
      findsNothing,
    );
    expect(clipboardCalls, isEmpty);
  });

  testWidgets(
    'day navigation requests the new day and hides the old snapshot',
    (tester) async {
      final day2HrvGate = Completer<void>();
      final repo = _SnapshotRepo(day2HrvGate: day2HrvGate);
      await _pumpInvestigate(tester, repo: repo, data: readyData());

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(repo.hrvDays, contains(_day2));
      expect(
        find.byKey(const ValueKey('investigate-copy-support-snapshot')),
        findsNothing,
      );
      expect(clipboardCalls, isEmpty);

      day2HrvGate.complete();
      await _revealCopyButton(tester);
    },
  );

  testWidgets('copies the successfully loaded day after navigation', (
    tester,
  ) async {
    final repo = _SnapshotRepo();
    await _pumpInvestigate(tester, repo: repo, data: readyData());

    await tester.tap(find.bySemanticsLabel('Previous day'));
    await _revealCopyButton(tester);
    final button = find.byKey(
      const ValueKey('investigate-copy-support-snapshot'),
    );
    expect(button, findsOneWidget);
    await tester.tap(button);
    await _pumpUntil(tester, () => clipboardCalls.isNotEmpty);

    expect(clipboardCalls, hasLength(1));
    expect(
      clipboardCalls.single,
      contains('Selected local day: Present ($_day2)'),
    );
    expect(clipboardCalls.single, isNot(contains(_day1)));
    expect(repo.sleepDays, [_day2]);
    expect(repo.hrvDays, [_day2, _day2]);
    expect(repo.heartDays, [_day2, _day2]);
    expect(repo.wearDays, [_day2, _day2]);
    expect(repo.lungsDays, [_day2, _day2]);
  });

  testWidgets('navigation during capture cancels the stale clipboard write', (
    tester,
  ) async {
    final sleepGate = Completer<Map<String, dynamic>>();
    final repo = _SnapshotRepo(sleepGate: sleepGate);
    await _pumpInvestigate(tester, repo: repo, data: readyData());

    final button = find.byKey(
      const ValueKey('investigate-copy-support-snapshot'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(repo.sleepDays, [_day1]);

    await tester.tap(find.bySemanticsLabel('Previous day'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(repo.hrvDays, contains(_day2));

    sleepGate.complete({
      'has_sleep': true,
      'sleep_source': 'manual',
      'duration_min': 420,
      'stages_confidence': 0.72,
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    expect(clipboardCalls, isEmpty);
  });
}
