import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/data_quality_summary.dart';

import 'support/dart_source.dart';

const _goodWear = <String, dynamic>{'worn_min': 120, 'coverage_pct': 45};
const _goodSleep = <String, dynamic>{
  'has_sleep': true,
  'sleep_source': 'manual',
  'stages_confidence': 0.0,
};
const _goodHrv = <String, dynamic>{
  'rmssd': 0.0,
  'coverage': {'rr_beats': 120, 'nn_clean': 100, 'clean_fraction': 0.8},
  'hrv_time': {'confidence': 0.0, 'note': 'not used'},
};
const _goodLungs = <String, dynamic>{
  'resp': {'value': 0.0, 'confidence': 0.0},
};
const _goodHeart = <String, dynamic>{'recovery': 0.0};

DataQualitySummary _summary({
  Map<String, dynamic>? wear = _goodWear,
  Map<String, dynamic>? sleep = _goodSleep,
  Map<String, dynamic>? hrv = _goodHrv,
  Map<String, dynamic>? lungs = _goodLungs,
  Map<String, dynamic>? heart = _goodHeart,
  Map<String, dynamic>? readinessDiagnostic,
  bool readinessDiagnosticAvailable = true,
  Object? partialFlag,
}) => DataQualitySummary.fromProjections(
  wear: wear,
  sleep: sleep,
  hrv: hrv,
  lungs: lungs,
  heart: heart,
  readinessAbsentDiagnostic: readinessDiagnostic,
  readinessDiagnosticAvailable: readinessDiagnosticAvailable,
  partialFlag: partialFlag,
);

void main() {
  test('zero and low numeric values are available without cutoffs', () {
    final zero = _summary();
    expect(zero.wear.state, DataQualityState.available);
    expect(zero.wear.wornMinutes, 120);
    expect(zero.wear.coveragePercent, 45);
    expect(zero.sleep.state, DataQualityState.available);
    expect(zero.sleep.stageEvidence, 0);
    expect(zero.hrv.state, DataQualityState.available);
    expect(zero.respiratory.state, DataQualityState.available);
    expect(zero.readiness.state, DataQualityState.available);

    final low = _summary(
      wear: const {'worn_min': 1, 'coverage_pct': 1},
      sleep: const {
        'has_sleep': true,
        'sleep_source': 'auto',
        'stages_confidence': 0.01,
      },
      hrv: const {
        'rmssd': 0.1,
        'coverage': {'rr_beats': 1, 'nn_clean': 0},
      },
      lungs: const {
        'resp': {'value': 0.1},
      },
      heart: const {'recovery': 1},
    );
    expect(low.wear.state, DataQualityState.available);
    expect(low.wear.coveragePercent, 1);
    expect(low.sleep.state, DataQualityState.available);
    expect(low.sleep.stageEvidence, 0.01);
    expect(low.hrv.state, DataQualityState.available);
    expect(low.respiratory.state, DataQualityState.available);
    expect(low.readiness.state, DataQualityState.available);

    final capped = _summary(
      sleep: const {
        'has_sleep': true,
        'sleep_source': 'auto',
        'stages_confidence': 0.7,
      },
    );
    expect(capped.sleep.stageEvidence, 0.6);
  });

  test(
    'a successful projection with no value is distinct from unavailable',
    () {
      final absent = _summary(
        wear: const {'worn_min': null},
        sleep: const {'has_sleep': false, 'sleep_source': 'none'},
        hrv: const {'rmssd': null},
        lungs: const {'resp': null},
        heart: const {'recovery': null},
      );
      expect(absent.wear.state, DataQualityState.absent);
      expect(absent.sleep.state, DataQualityState.absent);
      expect(absent.hrv.state, DataQualityState.absent);
      expect(absent.respiratory.state, DataQualityState.absent);
      expect(absent.readiness.state, DataQualityState.absent);

      final unavailable = _summary(
        wear: null,
        sleep: const {},
        hrv: const {},
        lungs: const {},
        heart: null,
      );
      expect(unavailable.wear.state, DataQualityState.unavailable);
      expect(unavailable.sleep.state, DataQualityState.unavailable);
      expect(unavailable.hrv.state, DataQualityState.unavailable);
      expect(unavailable.respiratory.state, DataQualityState.unavailable);
      expect(unavailable.readiness.state, DataQualityState.unavailable);

      final missingField = _summary(
        wear: const {'coverage_pct': 60},
        sleep: const {'sleep_source': 'auto'},
        hrv: const {
          'coverage': {'rr_beats': 30},
        },
        lungs: const {
          'resp': {'confidence': 0.99},
        },
        heart: const {},
      );
      expect(missingField.wear.state, DataQualityState.unavailable);
      expect(missingField.sleep.state, DataQualityState.unavailable);
      expect(missingField.hrv.state, DataQualityState.unavailable);
      expect(missingField.respiratory.state, DataQualityState.unavailable);
      expect(missingField.readiness.state, DataQualityState.unavailable);
    },
  );

  test('only producer evidence distinguishes withheld from absent', () {
    final withheld = _summary(
      lungs: const {
        'resp': {'value': null, 'note': 'unstable_baseline:z=5.2,cap=5'},
      },
      heart: const {'recovery': null},
      readinessDiagnostic: const {'note': 'unstable_baseline:z=5.2,cap=5'},
    );
    expect(withheld.respiratory.state, DataQualityState.withheld);
    expect(withheld.respiratory.explanation, isNull);
    expect(withheld.readiness.state, DataQualityState.withheld);
    expect(withheld.readiness.explanation, isNull);

    final absent = _summary(
      lungs: const {
        'resp': {'value': null},
      },
      heart: const {'recovery': null},
      readinessDiagnostic: null,
    );
    expect(absent.respiratory.state, DataQualityState.absent);
    expect(absent.readiness.state, DataQualityState.absent);
  });

  test('known diagnostic notes receive generated explanations only', () {
    final baseline = _summary(
      lungs: const {
        'resp': {'value': null, 'note': 'need_baseline:have=2,need=4'},
      },
    );
    expect(baseline.respiratory.state, DataQualityState.withheld);
    expect(baseline.respiratory.explanation, 'Need 2 more nights');

    final input = _summary(
      lungs: const {
        'resp': {'value': null, 'note': 'need_input:name=age'},
      },
    );
    expect(input.respiratory.explanation, contains('Your age is not on file'));

    final unknownInput = _summary(
      lungs: const {
        'resp': {'value': null, 'note': 'need_input:name=unknown_private'},
      },
    );
    expect(unknownInput.respiratory.state, DataQualityState.withheld);
    expect(unknownInput.respiratory.explanation, isNull);
  });

  test(
    'unrelated raw and personal inputs never enter user-visible evidence',
    () {
      const sentinels = <String>[
        'RAW_RR_SENTINEL',
        'RAW_PPG_SENTINEL',
        'RAW_ACCELEROMETER_SENTINEL',
        'RAW_GPS_SENTINEL',
        'JOURNAL_SENTINEL',
        'MEAL_SENTINEL',
        'IDENTIFIER_SENTINEL',
        'FREE_TEXT_SENTINEL',
      ];
      final hrvInput = <String, dynamic>{
        'rmssd': 12,
        'coverage': {'rr_beats': 20, 'nn_clean': 18, 'clean_fraction': 0.9},
        'raw_rr': sentinels[0],
        'raw_ppg': sentinels[1],
        'accelerometer': sentinels[2],
        'gps': sentinels[3],
        'journal': sentinels[4],
        'meal': sentinels[5],
        'identifier': sentinels[6],
        'free_text': sentinels[7],
        'hrv_time': {'confidence': 1.0, 'note': sentinels[7]},
      };
      final summary = _summary(
        hrv: hrvInput,
        sleep: const {
          'has_sleep': true,
          'sleep_source': 'FREE_TEXT_SENTINEL',
          'stages_confidence': 0.7,
          'free_text': 'FREE_TEXT_SENTINEL',
        },
        lungs: const {
          'resp': {
            'value': null,
            'note': 'FREE_TEXT_SENTINEL',
            'private_key': 'IDENTIFIER_SENTINEL',
          },
          'private_key': 'RAW_GPS_SENTINEL',
        },
        heart: const {'recovery': null},
        readinessDiagnostic: const {
          'note': 'FREE_TEXT_SENTINEL',
          'private_key': 'IDENTIFIER_SENTINEL',
        },
      );

      expect(summary.respiratory.state, DataQualityState.withheld);
      expect(summary.respiratory.explanation, isNull);
      expect(summary.readiness.state, DataQualityState.withheld);
      expect(summary.readiness.explanation, isNull);
      expect(summary.sleep.source, isNull);
      expect(summary.hrv.state, DataQualityState.available);
      expect(summary.sleep.stageEvidence, 0.6);

      // Enumerate the model's user-facing scalar evidence explicitly; do not use
      // the summary object's default toString as a privacy assertion.
      final visibleEvidence = <String>[
        summary.wear.state.name,
        summary.wear.wornMinutes?.toString() ?? '',
        summary.wear.coveragePercent?.toString() ?? '',
        summary.sleep.state.name,
        summary.sleep.source?.name ?? '',
        summary.sleep.stageEvidence?.toStringAsFixed(2) ?? '',
        summary.hrv.state.name,
        summary.hrv.rrBeats?.toString() ?? '',
        summary.hrv.cleanBeats?.toString() ?? '',
        summary.hrv.cleanFraction?.toString() ?? '',
        summary.respiratory.state.name,
        summary.respiratory.explanation ?? '',
        summary.readiness.state.name,
        summary.readiness.explanation ?? '',
      ];
      for (final sentinel in sentinels) {
        expect(visibleEvidence.join('|'), isNot(contains(sentinel)));
      }

      final before = visibleEvidence.join('|');
      hrvInput['raw_rr'] = 'MUTATED_AFTER_MAPPING';
      (hrvInput['coverage'] as Map)['nn_clean'] = 0;
      expect(
        <String>[
          summary.hrv.rrBeats?.toString() ?? '',
          summary.hrv.cleanBeats?.toString() ?? '',
          summary.hrv.cleanFraction?.toString() ?? '',
        ].join('|'),
        '20|18|0.9',
      );
      expect(before, isNot(contains('MUTATED_AFTER_MAPPING')));
    },
  );

  test('partial is a day-level notice, not a metric limitation', () {
    final summary = _summary(partialFlag: 1);
    expect(summary.partialStoredResult, isTrue);
    expect(summary.wear.state, DataQualityState.available);
    expect(summary.sleep.state, DataQualityState.available);
    expect(summary.hrv.state, DataQualityState.available);
    expect(summary.respiratory.state, DataQualityState.available);
    expect(summary.readiness.state, DataQualityState.available);
  });

  test(
    'failed readiness diagnostic read is unavailable without losing rows',
    () {
      final summary = _summary(
        heart: const {'recovery': null},
        readinessDiagnosticAvailable: false,
      );
      expect(summary.readiness.state, DataQualityState.unavailable);
      expect(summary.wear.state, DataQualityState.available);
      expect(summary.sleep.state, DataQualityState.available);
      expect(summary.hrv.state, DataQualityState.available);
      expect(summary.respiratory.state, DataQualityState.available);
    },
  );

  test('mapper stays a scalar projection boundary', () async {
    final source = await File(
      'lib/ui2/screens/data_quality_summary.dart',
    ).readAsString();
    final code = stripCommentsAndStrings(source);

    expect(
      source.contains("import 'package:openstrap_analytics/") ||
          source.contains('import "package:openstrap_analytics/'),
      isFalse,
    );
    expect(source, isNot(contains('/compute/')));
    expect(
      code,
      isNot(
        matches(
          RegExp(r'\b(?:DerivationEngine|derive\w*|recompute\w*|compute\w*)\b'),
        ),
      ),
    );
    expect(
      code,
      isNot(
        matches(
          RegExp(r'\b(?:raw_records|raw_archive|decoded_onehz|decoded_rr)\b'),
        ),
      ),
    );
    expect(code, isNot(contains('getToday')));
    expect(source, isNot(contains('payload_json')));
    expect(code, isNot(contains('jsonDecode')));
    expect(
      code,
      isNot(
        matches(
          RegExp(r'^\s*final\s+(?:Map|List|Object|dynamic)\b', multiLine: true),
        ),
      ),
      reason:
          'the summary must not retain arbitrary input collections or objects',
    );
  });

  test('readiness diagnostic availability follows the day-result read', () async {
    final source = await File(
      'lib/ui2/screens/health_screen.dart',
    ).readAsString();
    final code = stripCommentsAndStrings(source);

    expect(code, contains('var readinessDiagnosticAvailable = false;'));
    expect(
      code,
      matches(
        RegExp(
          r'final row = await LocalDb\.dayResult\(day\);[\s\S]*?readinessDiagnosticAvailable = true;',
        ),
      ),
    );
    expect(
      source,
      contains(
        'This helper also swallows its own read and JSON parse failures',
      ),
    );
  });
}
