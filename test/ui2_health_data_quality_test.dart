import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/screens/data_quality_summary.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/ui2/screens/investigate.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day1 = '2026-08-16';
const _day2 = '2026-08-17';
const _privateSentinel = 'SENTINEL_FREEFORM_PRIVATE_TEXT';
const _privacySentinels = <String>[
  'RAW_RR_SENTINEL',
  'RAW_PPG_SENTINEL',
  'RAW_ACCELEROMETER_SENTINEL',
  'RAW_GPS_SENTINEL',
  'JOURNAL_SENTINEL',
  'MEAL_SENTINEL',
  'IDENTIFIER_SENTINEL',
  'FREE_TEXT_SENTINEL',
];

class _VitalsRepo extends LocalRepository {
  _VitalsRepo({this.day2Recovery = 40});

  final num? day2Recovery;
  Completer<void>? day2TimelineGate;
  final timelineDays = <String>[];
  final lungsDays = <String>[];
  final wearDays = <String>[];
  final hrvDays = <String>[];
  final sleepDays = <String>[];
  final heartDays = <String>[];

  @override
  Future<Map<String, dynamic>> getToday() async => const {
    'status': {'today_day': _day2},
  };

  @override
  Future<List<String>> availableDays() async => const [_day2, _day1];

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async {
    timelineDays.add(date);
    if (date == _day2 && day2TimelineGate != null) {
      await day2TimelineGate!.future;
    }
    return {
      'date': date,
      'highs': {
        'low_hr': {'v': date == _day1 ? 50 : 60},
        'peak_hr': {'v': date == _day1 ? 120 : 130},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getDayLungs(String date) async {
    lungsDays.add(date);
    return {
      'resp': {
        'value': date == _day1 ? 10.0 : 15.0,
        'gps_trace': _privacySentinels[3],
      },
      'meal_text': _privacySentinels[5],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async {
    wearDays.add(date);
    return {
      'worn_min': date == _day1 ? 120 : 240,
      'coverage_pct': 50,
      'journal': _privacySentinels[4],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayHrv(String date) async {
    hrvDays.add(date);
    return {
      'rmssd': date == _day1 ? 22.0 : 33.0,
      'coverage': {'rr_beats': 200, 'nn_clean': 190, 'clean_fraction': 0.95},
      'hrv_time': {'confidence': 0.01, 'note': _privateSentinel},
      'raw_rr': _privacySentinels[0],
      'raw_ppg': _privacySentinels[1],
      'accelerometer': _privacySentinels[2],
      'identifier': _privacySentinels[6],
      'free_text': _privacySentinels[7],
    };
  }

  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async {
    sleepDays.add(date);
    return {
      'has_sleep': true,
      'sleep_source': 'manual',
      'stages_confidence': 0.7,
      'journal': _privacySentinels[4],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async {
    heartDays.add(date);
    return {
      'recovery': date == _day1 ? 44 : day2Recovery,
      'meal': _privacySentinels[5],
      'identifier': _privacySentinels[6],
      'note': _privacySentinels[7],
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for selected-day Vitals data');
}

List<String> _rowText(WidgetTester tester, String metricKey) {
  final row = find.byKey(ValueKey('health-data-quality-$metricKey'));
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .toList();
}

void _expectNoSentinelsInDataQuality(WidgetTester tester) {
  for (final key in const ['wear', 'sleep', 'hrv', 'resp_rate', 'readiness']) {
    final visible = _rowText(tester, key).join('\n');
    for (final sentinel in _privacySentinels) {
      expect(visible, isNot(contains(sentinel)), reason: 'in $key row');
    }
    expect(visible, isNot(contains(_privateSentinel)), reason: 'in $key row');
  }
}

DataQualitySummary _zeroAndLowQuality() => DataQualitySummary.fromProjections(
  wear: const {'worn_min': 0, 'coverage_pct': 0.1},
  sleep: const {
    'has_sleep': true,
    'sleep_source': 'manual',
    'stages_confidence': 0.01,
  },
  hrv: const {
    'rmssd': 0.1,
    'coverage': {'rr_beats': 1, 'nn_clean': 0, 'clean_fraction': 0.01},
  },
  lungs: const {
    'resp': {'value': 0.1},
  },
  heart: const {'recovery': 0},
  readinessAbsentDiagnostic: null,
  partialFlag: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    LocalDb.dbName = 'health_data_quality_test.db';
    databasePath = p.join(
      await databaseFactory.getDatabasesPath(),
      LocalDb.dbName,
    );
    await databaseFactory.deleteDatabase(databasePath);
    await LocalDb.instance;
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  test(
    'successful day result with no diagnostic is readiness No value',
    () async {
      final vitals = await VitalsData.load(
        _VitalsRepo(day2Recovery: null),
        want: _day2,
      );
      expect(vitals.quality?.readiness.state, DataQualityState.absent);
    },
  );

  testWidgets(
    'day navigation hides stale rows and opens day-specific details',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final gate = Completer<void>();
      final repo = _VitalsRepo()..day2TimelineGate = gate;
      final app = AppState.forTesting()..repo = repo;
      final theme = ThemeController.seed(
        AppThemeChoice.light,
        Brightness.light,
      );
      addTearDown(app.dispose);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: ChangeNotifierProvider<AppState>.value(
            value: app,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: Scaffold(
                body: HealthScreen(
                  data: const HealthData(),
                  vitals: VitalsData(
                    day: _day1,
                    days: [_day2, _day1],
                    timeline: {
                      'date': _day1,
                      'highs': {
                        'low_hr': {'v': 50},
                        'peak_hr': {'v': 120},
                      },
                    },
                    lungs: {
                      'resp': {'value': 10.0},
                    },
                    wear: {'worn_min': 120, 'coverage_pct': 50},
                    hrv: {'rmssd': 22.0},
                    quality: _zeroAndLowQuality(),
                  ),
                  tab: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Data quality'), findsOneWidget);
      expect(find.text('Partial stored result'), findsOneWidget);
      for (final key in const [
        'wear',
        'sleep',
        'hrv',
        'resp_rate',
        'readiness',
      ]) {
        expect(_rowText(tester, key), contains('Available'));
      }
      expect(
        _rowText(tester, 'sleep').join(' '),
        contains('Stage evidence · coverage-derived: 0.01'),
      );
      expect(_rowText(tester, 'sleep').join(' '), isNot(contains('%')));
      expect(find.text('10.0'), findsOneWidget);
      _expectNoSentinelsInDataQuality(tester);

      await tester.tap(find.bySemanticsLabel('Next day'));
      await tester.pump();
      await _pumpUntil(tester, () => repo.timelineDays.contains(_day2));

      expect(
        find.bySemanticsLabel('Previous day'),
        findsOneWidget,
        reason: 'the day navigator remains available while the new read waits',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Data quality'), findsNothing);
      expect(
        find.text('10.0'),
        findsNothing,
        reason: 'day 1 values must not remain visible under day 2',
      );

      gate.complete();
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('health-data-quality-readiness'))
            .evaluate()
            .isNotEmpty,
      );
      await _settle(tester);

      expect(find.text('Data quality'), findsOneWidget);
      expect(find.text('15.0'), findsOneWidget);
      for (final key in const [
        'wear',
        'sleep',
        'hrv',
        'resp_rate',
        'readiness',
      ]) {
        expect(_rowText(tester, key), contains('Available'));
      }
      final sleepEvidence = _rowText(tester, 'sleep').join(' ');
      expect(
        sleepEvidence,
        contains('Stage evidence · coverage-derived: 0.60'),
      );
      expect(sleepEvidence, isNot(contains('%')));
      expect(_rowText(tester, 'hrv').join(' '), isNot(contains('33.0')));
      expect(_rowText(tester, 'resp_rate').join(' '), isNot(contains('15.0')));
      expect(_rowText(tester, 'readiness').join(' '), isNot(contains('40')));
      _expectNoSentinelsInDataQuality(tester);

      const routes = <(String, String)>[
        ('wear', 'wear'),
        ('sleep', 'sleep'),
        ('hrv', 'hrv'),
        ('resp_rate', 'resp_rate'),
        ('readiness', 'readiness'),
      ];
      for (final (rowKey, metricKey) in routes) {
        final row = find.byKey(ValueKey('health-data-quality-$rowKey'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        final screen = tester.widget<Investigate>(find.byType(Investigate));
        expect(screen.metricKey, metricKey);
        expect(screen.day, _day2);

        Navigator.of(tester.element(find.byType(Investigate))).pop();
        await tester.pumpAndSettle();
      }

      expect(repo.timelineDays, isNotEmpty);
      expect(repo.timelineDays, everyElement(_day2));
      expect(repo.lungsDays, contains(_day2));
      expect(repo.wearDays, isNotEmpty);
      expect(repo.wearDays, everyElement(_day2));
      expect(repo.hrvDays, isNotEmpty);
      expect(repo.hrvDays, everyElement(_day2));
      expect(repo.sleepDays, isNotEmpty);
      expect(repo.sleepDays, everyElement(_day2));
      expect(repo.heartDays, isNotEmpty);
      expect(repo.heartDays, everyElement(_day2));
    },
  );
}
