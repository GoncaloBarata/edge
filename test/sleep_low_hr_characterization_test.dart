import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _daySeconds = 2 * 60 * 60;
const _nightSeconds = 7 * 60 * 60;
const _tailSeconds = 60 * 60;
const _nightStartIndex = _daySeconds;
const _nightEndIndex = _daySeconds + _nightSeconds;
const _wakeDay = '2025-06-16';

final _captureStart = DateTime(2025, 6, 15, 20).millisecondsSinceEpoch ~/ 1000;

enum _MissingPattern { distributed, continuous }

typedef _CaseResult = ({
  Substrate substrate,
  PreparedDerivationDay day,
  double nightHrCoverage,
  double overallHrCoverage,
  double accelCoverage,
});

bool _isHrMissing(
  int secondInNight, {
  required int missingPercent,
  required _MissingPattern pattern,
}) {
  if (missingPercent == 0) return false;
  if (pattern == _MissingPattern.distributed) {
    // Exactly missingPercent samples in each 100-second cycle.
    return secondInNight % 100 < missingPercent;
  }
  final missingSeconds = _nightSeconds * missingPercent ~/ 100;
  final firstMissing = (_nightSeconds - missingSeconds) ~/ 2;
  return secondInNight >= firstMissing &&
      secondInNight < firstMissing + missingSeconds;
}

List<Map<String, dynamic>> _frames({
  required int sleepingHr,
  int missingPercent = 0,
  _MissingPattern missingPattern = _MissingPattern.distributed,
}) => [
  for (var i = 0; i < _daySeconds + _nightSeconds + _tailSeconds; i++)
    () {
      final sleeping = i >= _nightStartIndex && i < _nightEndIndex;
      final secondInSegment = sleeping ? i - _nightStartIndex : i;
      final missingHr =
          sleeping &&
          _isHrMissing(
            secondInSegment,
            missingPercent: missingPercent,
            pattern: missingPattern,
          );
      final hr = sleeping
          ? (sleepingHr +
                    (sleepingHr == 24
                        ? 0
                        : 1.5 * math.sin(secondInSegment / 1800.0)))
                .round()
          : (72 + 2 * math.sin(i / 600.0)).round();
      final phase = math.sin(i * 0.5);
      return <String, dynamic>{
        'rec_ts': _captureStart + i,
        // The decoded-page seam represents an absent HR second as zero while
        // retaining the timestamp and valid accelerometer measurements.
        'hr': missingHr ? 0 : hr,
        'ax': sleeping ? 0.02 : 0.3 * phase,
        'ay': sleeping ? 0.02 : 0.3,
        'az': sleeping ? 1.0 : 0.9 * (1 - 0.2 * phase),
      };
    }(),
];

_CaseResult _runCase(
  int sleepingHr, {
  int missingPercent = 0,
  _MissingPattern missingPattern = _MissingPattern.distributed,
}) {
  final substrate = substrateFromDecodedPage(
    _frames(
      sleepingHr: sleepingHr,
      missingPercent: missingPercent,
      missingPattern: missingPattern,
    ),
    const [],
  );
  final validNightHr = substrate.hr
      .getRange(_nightStartIndex, _nightEndIndex)
      .where((hr) => hr > 0)
      .length;
  final validAllHr = substrate.hr.where((hr) => hr > 0).length;
  final days = prepareDerivationPayload(substrate, targetDay: _wakeDay).days;
  return (
    substrate: substrate,
    day: days.single,
    nightHrCoverage: validNightHr / _nightSeconds,
    overallHrCoverage: validAllHr / substrate.length,
    accelCoverage: substrate.accelPresentFraction(
      _nightStartIndex,
      _nightEndIndex,
    ),
  );
}

void _record(
  String label,
  _CaseResult result, {
  required int missingPercent,
  _CaseResult? reference,
}) {
  // These lines make the characterization outcome visible in the focused test
  // run, including whether detection selected the accel or HR fallback path.
  final stages = <String, int>{};
  for (final stage in result.day.hypnoStages) {
    stages.update(stage, (count) => count + 1, ifAbsent: () => 1);
  }
  final hasWindow =
      result.day.sleepOnsetSec > 0 &&
      result.day.sleepOffsetSec > result.day.sleepOnsetSec;
  final windowDelta = hasWindow && reference != null
      ? 'start=${result.day.sleepOnsetSec - reference.day.sleepOnsetSec}s, '
            'end=${result.day.sleepOffsetSec - reference.day.sleepOffsetSec}s'
      : (hasWindow ? 'baseline' : 'absent');
  // ignore: avoid_print
  print(
    '$label: intended missing=$missingPercent%, '
    'night HR coverage=${(100 * result.nightHrCoverage).toStringAsFixed(1)}%, '
    'overall HR coverage=${(100 * result.overallHrCoverage).toStringAsFixed(1)}%, '
    'accel coverage=${(100 * result.accelCoverage).toStringAsFixed(1)}%, '
    'source=${result.day.sleepSource}, '
    'window=${result.day.sleepOnsetSec == 0 ? 'absent' : '[${result.day.sleepOnsetSec}, ${result.day.sleepOffsetSec})'}, '
    'window delta=$windowDelta, '
    'TST=${result.day.sleepJson['tst_sec']}, '
    'in-bed=${result.day.sleepJson['in_bed_sec']}, '
    'unobserved=${result.day.sleepJson['unobserved_sec']}, '
    'WASO=${result.day.sleepJson['waso_sec']}, stages=$stages',
  );
}

void _expectWindowNear(PreparedDerivationDay day, int onsetSec, int offsetSec) {
  expect(
    day.sleepJson['tst_sec'],
    isNotNull,
    reason: 'the synthetic night should be observed and staged',
  );
  expect(day.sleepOnsetSec, closeTo(onsetSec, 15 * 60));
  expect(day.sleepOffsetSec, closeTo(offsetSec, 15 * 60));
}

void _expectDetectedAlignedToReference(
  PreparedDerivationDay day,
  PreparedDerivationDay reference,
) {
  expect(day.sleepSource, 'auto');
  expect(day.sleepOnsetSec, greaterThan(0));
  expect(day.sleepOffsetSec, greaterThan(day.sleepOnsetSec));
  expect(day.sleepJson['tst_sec'], isA<num>());
  expect(day.sleepJson['tst_sec'], greaterThan(0));
  expect(day.sleepJson['in_bed_sec'], isA<num>());
  expect(day.sleepJson['in_bed_sec'], greaterThan(0));
  expect(day.sleepOnsetSec, closeTo(reference.sleepOnsetSec, 15 * 60));
  expect(day.sleepOffsetSec, closeTo(reference.sleepOffsetSec, 15 * 60));
}

void _expectNoDetectedSleep(PreparedDerivationDay day) {
  expect(day.sleepJson['tst_sec'], isNull);
  expect(day.sleepOnsetSec, 0);
  expect(day.sleepOffsetSec, 0);
}

void main() {
  final expectedOnset = _captureStart + _nightStartIndex;
  final expectedOffset = _captureStart + _nightEndIndex;
  const scenarios = <(String, int, _MissingPattern)>[
    ('0% reference', 0, _MissingPattern.distributed),
    ('10% distributed', 10, _MissingPattern.distributed),
    ('10% continuous block', 10, _MissingPattern.continuous),
    ('30% distributed', 30, _MissingPattern.distributed),
    ('30% continuous block', 30, _MissingPattern.continuous),
    ('50% distributed', 50, _MissingPattern.distributed),
    ('50% continuous block', 50, _MissingPattern.continuous),
  ];
  // These expectations pin the current output for characterization. An
  // intentional future algorithm fix may require updating them.

  test('reference night: 50 bpm, moving context, full sensor coverage', () {
    final result = _runCase(50);
    _record('50 bpm reference', result, missingPercent: 0);

    expect(result.nightHrCoverage, 1);
    expect(result.overallHrCoverage, 1);
    expect(result.accelCoverage, 1);
    _expectWindowNear(result.day, expectedOnset, expectedOffset);
    expect(result.day.sleepSource, 'auto');
  });

  test('valid very-low HR is retained and reaches sleep inference', () {
    final result = _runCase(30);
    _record('30 bpm low-HR', result, missingPercent: 0);

    final nightHr = result.substrate.hr.sublist(
      _nightStartIndex,
      _nightEndIndex,
    );
    expect(nightHr.every((hr) => hr >= 25 && hr <= 35), isTrue);
    expect(result.nightHrCoverage, 1);
    expect(result.accelCoverage, 1);
    _expectWindowNear(result.day, expectedOnset, expectedOffset);
    expect(result.day.sleepSource, 'auto');
  });

  test('24 bpm is absent after edge filtering and does not stage a night', () {
    final result = _runCase(24);
    _record('24 bpm below boundary', result, missingPercent: 0);

    final nightHr = result.substrate.hr.sublist(
      _nightStartIndex,
      _nightEndIndex,
    );
    expect(nightHr, everyElement(0));
    expect(result.nightHrCoverage, 0);
    expect(result.accelCoverage, 1);
    expect(result.day.sleepJson['tst_sec'], isNull);
    expect(result.day.sleepOnsetSec, 0);
    expect(result.day.sleepOffsetSec, 0);
  });

  for (final sleepingHr in [50, 30]) {
    test('Edge missing-HR matrix: $sleepingHr bpm night', () {
      final reference = _runCase(sleepingHr);
      expect(reference.nightHrCoverage, 1);
      expect(reference.accelCoverage, 1);
      _expectWindowNear(reference.day, expectedOnset, expectedOffset);

      for (final (label, missingPercent, pattern) in scenarios) {
        final result = _runCase(
          sleepingHr,
          missingPercent: missingPercent,
          missingPattern: pattern,
        );
        _record(
          '$sleepingHr bpm / $label',
          result,
          missingPercent: missingPercent,
          reference: reference,
        );

        final expectedMissing = _nightSeconds * missingPercent ~/ 100;
        final nightHr = result.substrate.hr.sublist(
          _nightStartIndex,
          _nightEndIndex,
        );
        expect(
          nightHr.where((hr) => hr == 0).length,
          expectedMissing,
          reason: 'missing HR is represented by the dense-array zero sentinel',
        );
        expect(
          result.nightHrCoverage,
          closeTo(1 - missingPercent / 100, 1e-12),
        );
        expect(result.accelCoverage, 1);
        expect(
          result.substrate.length,
          _daySeconds + _nightSeconds + _tailSeconds,
        );

        final currentlyDetected =
            missingPercent != 50 || pattern == _MissingPattern.distributed;
        if (currentlyDetected) {
          _expectDetectedAlignedToReference(result.day, reference.day);
        } else {
          _expectNoDetectedSleep(result.day);
        }
      }
    });
  }
}
