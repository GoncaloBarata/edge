import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/support/support_snapshot.dart';

SupportSnapshot _snapshot({
  String? day = '2026-08-16',
  int? algorithmVersion = 109,
  String? importedFrom,
  Object? deviceFamily = 'gen4',
  Map<String, dynamic> wear = const {'worn_min': 0, 'coverage_pct': 0},
  Map<String, dynamic> sleep = const {
    'has_sleep': true,
    'sleep_source': 'manual',
    'onset_ts': 1786917600,
    'wake_ts': 1786946400,
    'duration_min': 0,
    'stages_confidence': 0.75,
  },
  Map<String, dynamic> hrv = const {
    'rmssd': 0,
    'hrv_time': {
      'confidence': 0.75,
      'note': 'need_input:name=nn_beats,have=4,need=20',
    },
    'coverage': {'rr_beats': 0, 'nn_clean': 0, 'clean_fraction': 0.0},
  },
  Map<String, dynamic> heart = const {'recovery': 0},
  Map<String, dynamic> lungs = const {
    'resp': {'value': 0, 'confidence': 0.5},
  },
  Map<String, dynamic>? readinessAbsentDiagnostic,
}) => SupportSnapshot.fromStoredData(
  appVersion: '0.10.0',
  buildNumber: '67',
  day: day,
  algorithmVersion: algorithmVersion,
  importedFrom: importedFrom,
  deviceFamily: deviceFamily,
  wear: wear,
  sleep: sleep,
  hrv: hrv,
  heart: heart,
  lungs: lungs,
  readinessAbsentDiagnostic: readinessAbsentDiagnostic,
);

void main() {
  test('format is stable, ordered, and retains measured zeroes', () {
    final snapshot = _snapshot();
    final text = snapshot.format();

    expect(snapshot.format(), text);
    expect(text, startsWith('OpenStrap support snapshot\n'));
    expect(text, contains('App version: Present (0.10.0)'));
    expect(text, contains('Build: Present (67)'));
    expect(text, contains('Device family: WHOOP 4'));
    expect(text, contains('Selected local day: Present (2026-08-16)'));
    expect(text, contains('Data source: On-device derived'));
    expect(text, contains('Stored algorithm version: Present (v109)'));
    expect(text, contains('Wear time: Present (0 min)'));
    expect(text, contains('Wear coverage: Present (0%)'));
    expect(text, contains('Sleep status: Present'));
    expect(text, contains('Sleep source: Present (Manual)'));
    expect(text, contains('Sleep duration: Present (0 min)'));
    expect(text, contains('Sleep stage confidence: Present (0.75)'));
    expect(text, contains('HRV RMSSD: Present (0.0 ms)'));
    expect(text, contains('HRV RR beats: Present (0)'));
    expect(text, contains('HRV clean fraction: Present (0.00)'));
    expect(text, contains('Respiratory rate: Present (0.0 breaths/min)'));
    expect(text, contains('Readiness score: Present (0.0)'));
    expect(
      text,
      contains(
        'HRV note: Present (Too few clean beat-to-beat intervals to work this out. There were 4, and it needs 20.)',
      ),
    );

    expect(
      text.indexOf('Selected local day'),
      lessThan(text.indexOf('Sleep status')),
    );
    expect(text.indexOf('Sleep status'), lessThan(text.indexOf('HRV status')));
    expect(
      text.indexOf('HRV status'),
      lessThan(text.indexOf('Respiratory status')),
    );
    expect(
      text.indexOf('Respiratory status'),
      lessThan(text.indexOf('Readiness score')),
    );
    expect(text, isNot(endsWith('\n')));
  });

  test('null values are absent while missing projections are unavailable', () {
    final snapshot = _snapshot(
      wear: const {'worn_min': null, 'coverage_pct': null},
      sleep: const {},
      hrv: const {'rmssd': null},
      heart: const {'recovery': null},
      lungs: const {'resp': null},
      readinessAbsentDiagnostic: const {
        'hrv': {'value': false, 'baseline_n': 0},
        'note': 'unknown_machine_detail:do-not-guess',
      },
    );
    final text = snapshot.format();

    expect(text, contains('Wear time: Absent'));
    expect(text, contains('Wear coverage: Absent'));
    expect(text, contains('Sleep status: Unavailable'));
    expect(text, contains('HRV status: Absent'));
    expect(text, contains('HRV confidence: Unavailable'));
    expect(text, contains('Respiratory status: Absent'));
    expect(text, contains('Readiness score: Absent'));
    expect(text, contains('Readiness absent diagnostic: Present'));
    expect(text, contains('HRV measured: Present (no)'));
    expect(text, contains('HRV baseline nights: Present (0)'));
    expect(text, isNot(contains('do-not-guess')));

    final missing = _snapshot(
      wear: const {},
      sleep: const {},
      hrv: const {},
      heart: const {},
      lungs: const {},
    );
    expect(missing.format(), contains('Wear time: Unavailable'));
    expect(missing.format(), contains('Wear coverage: Unavailable'));
    expect(missing.format(), contains('HRV status: Unavailable'));
    expect(missing.format(), contains('Respiratory status: Unavailable'));
    expect(missing.format(), contains('Readiness score: Unavailable'));
    expect(
      missing.format(),
      contains('Readiness absent diagnostic: Unavailable'),
    );

    final noSleep = _snapshot(
      sleep: const {'has_sleep': false, 'sleep_source': 'none'},
    );
    expect(noSleep.format(), contains('Sleep status: Absent'));
    expect(noSleep.format(), contains('Sleep source: Present (None)'));
  });

  test('source and device family normalize to a fixed allowlist', () {
    final imported = _snapshot(
      importedFrom: r'C:\private\whoop-export.json',
      deviceFamily: 'unrecognized-adapter-id',
    );
    expect(imported.format(), contains('Data source: Imported'));
    expect(imported.format(), contains('Device family: Unknown'));
    expect(imported.format(), isNot(contains('whoop-export.json')));

    final unknown = _snapshot(algorithmVersion: null, deviceFamily: null);
    expect(unknown.format(), contains('Data source: Unknown'));
    expect(unknown.format(), contains('Device family: Unknown'));
    expect(unknown.format(), contains('Stored algorithm version: Unavailable'));
  });
}
