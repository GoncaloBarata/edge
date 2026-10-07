import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/support/support_snapshot.dart';

import 'support/dart_source.dart';

void main() {
  test('only allowlisted data appears in the formatted snapshot', () {
    const freeformSentinel = 'SENTINEL_FREEFORM_PRIVATE_TEXT';
    const sentinels = [
      'SENTINEL_EMAIL@example.invalid',
      'SENTINEL_PERSON_NAME',
      'SENTINEL_SERIAL_NUMBER',
      'AA:BB:CC:DD:EE:FF',
      'SENTINEL_BLE_ADDRESS',
      'SENTINEL_TOKEN_VALUE',
      'SENTINEL_JOURNAL_TEXT',
      'SENTINEL_MEAL_TEXT',
      'SENTINEL_GPS_COORDINATE',
      'SENTINEL_RAW_RR',
      'SENTINEL_RAW_PPG',
      'SENTINEL_RAW_ACCEL',
      'SENTINEL_ARBITRARY_MAP_KEY',
      'SENTINEL_IMPORT_FILENAME',
      'SENTINEL_IMPORT_PATH',
      freeformSentinel,
    ];
    final snapshot = SupportSnapshot.fromStoredData(
      appVersion: '0.10.0',
      buildNumber: '67',
      day: '2026-08-16',
      algorithmVersion: 109,
      importedFrom: r'C:\private\SENTINEL_IMPORT_PATH\SENTINEL_IMPORT_FILENAME',
      deviceFamily: 'AA:BB:CC:DD:EE:FF',
      wear: {
        'worn_min': 0,
        'coverage_pct': 0,
        'email': sentinels[0],
        'name': sentinels[1],
        'serial': sentinels[2],
        'address': sentinels[4],
        'token': sentinels[5],
        'gps': sentinels[8],
        sentinels[13]: sentinels[13],
      },
      sleep: {
        'has_sleep': true,
        'sleep_source': 'manual',
        'duration_min': 390,
        'stages_confidence': 0.7,
        'journal': sentinels[6],
        'meal': sentinels[7],
        'gps': sentinels[8],
        'rr': sentinels[9],
        'ppg': sentinels[10],
        'accel': sentinels[11],
        'extra': {sentinels[12]: sentinels[12]},
      },
      hrv: {
        'rmssd': 35.2,
        'device_family': sentinels[3],
        'hrv_time': {
          'confidence': 0.8,
          'note': freeformSentinel,
        },
        'coverage': {
          'rr_beats': 200,
          'nn_clean': 180,
          'clean_fraction': 0.9,
          'raw_rr': sentinels[9],
          'raw_ppg': sentinels[10],
          'raw_accel': sentinels[11],
          sentinels[12]: sentinels[12],
        },
        'raw_records': [sentinels[9], sentinels[10], sentinels[11]],
      },
      heart: {
        'recovery': null,
        'hr_curve': [sentinels[9]],
        'baselines': {sentinels[12]: sentinels[12]},
      },
      lungs: {
        'resp': {
          'value': 15.2,
          'confidence': 0.8,
          'note': freeformSentinel,
        },
        'gps': sentinels[8],
        'address': sentinels[4],
      },
      readinessAbsentDiagnostic: {
        'note': freeformSentinel,
        'email': sentinels[0],
        'journal': sentinels[6],
        'extra': {sentinels[12]: sentinels[12]},
      },
    );
    final text = snapshot.format();

    for (final sentinel in sentinels) {
      expect(text, isNot(contains(sentinel)), reason: 'leaked $sentinel');
    }
    expect(text, contains('Data source: Imported'));
    expect(text, contains('Device family: Unknown'));
    expect(text, contains('HRV note: Absent'));
    expect(text, contains('Respiratory note: Absent'));
    expect(text, contains('Readiness diagnostic note: Absent'));
    expect(text, isNot(contains(freeformSentinel)));
  });

  test('recognized diagnostic forms produce their fixed explanations', () {
    final snapshot = SupportSnapshot.fromStoredData(
      appVersion: '0.10.0',
      buildNumber: '67',
      day: '2026-08-16',
      algorithmVersion: 109,
      importedFrom: null,
      deviceFamily: 'gen4',
      wear: const {},
      sleep: const {},
      hrv: const {
        'hrv_time': {
          'note': 'need_input:name=nn_beats,have=4,need=20',
        },
      },
      heart: const {'recovery': null},
      lungs: const {
        'resp': {'note': 'need_baseline:have=4,need=7'},
      },
      readinessAbsentDiagnostic: const {
        'note': 'need_baseline:have=4,need=7',
      },
    );

    final text = snapshot.format();
    expect(
      text,
      contains(
        'HRV note: Present (Too few clean beat-to-beat intervals to work this out. There were 4, and it needs 20.)',
      ),
    );
    expect(text, contains('Respiratory note: Present (Need 3 more nights)'));
    expect(
      text,
      contains('Readiness diagnostic note: Present (Need 3 more nights)'),
    );
  });

  test('snapshot collector has no compute or raw-store dependency', () {
    final source = File('lib/support/support_snapshot.dart').readAsStringSync();
    final code = stripCommentsAndStrings(source);

    for (final forbidden in [
      'openstrap_analytics',
      'DerivationEngine',
      'getToday',
      'raw_archive',
      'raw_records',
      'decoded_onehz',
      'decoded_rr',
    ]) {
      expect(code, isNot(contains(forbidden)), reason: 'found $forbidden');
    }
  });
}
