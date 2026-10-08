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

List<Map<String, dynamic>> _frames({required int sleepingHr}) => [
  for (var i = 0; i < _daySeconds + _nightSeconds + _tailSeconds; i++)
    () {
      final sleeping = i >= _nightStartIndex && i < _nightEndIndex;
      final secondInSegment = sleeping ? i - _nightStartIndex : i;
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
        'hr': hr,
        'ax': sleeping ? 0.02 : 0.3 * phase,
        'ay': sleeping ? 0.02 : 0.3,
        'az': sleeping ? 1.0 : 0.9 * (1 - 0.2 * phase),
      };
    }(),
];

({
  Substrate substrate,
  PreparedDerivationDay day,
  double nightHrCoverage,
  double overallHrCoverage,
  double accelCoverage,
})
_runCase(int sleepingHr) {
  final substrate = substrateFromDecodedPage(
    _frames(sleepingHr: sleepingHr),
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
  ({
    Substrate substrate,
    PreparedDerivationDay day,
    double nightHrCoverage,
    double overallHrCoverage,
    double accelCoverage,
  })
  result,
) {
  // These lines make the characterization outcome visible in the focused test
  // run, including whether detection selected the accel or HR fallback path.
  // ignore: avoid_print
  print(
    '$label: night HR coverage=${(100 * result.nightHrCoverage).toStringAsFixed(1)}%, '
    'overall HR coverage=${(100 * result.overallHrCoverage).toStringAsFixed(1)}%, '
    'accel coverage=${(100 * result.accelCoverage).toStringAsFixed(1)}%, '
    'source=${result.day.sleepSource}, '
    'window=${result.day.sleepOnsetSec == 0 ? 'absent' : '[${result.day.sleepOnsetSec}, ${result.day.sleepOffsetSec})'}, '
    'TST=${result.day.sleepJson['tst_sec']}, '
    'in-bed=${result.day.sleepJson['in_bed_sec']}',
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

void main() {
  final expectedOnset = _captureStart + _nightStartIndex;
  final expectedOffset = _captureStart + _nightEndIndex;

  test('reference night: 50 bpm, moving context, full sensor coverage', () {
    final result = _runCase(50);
    _record('50 bpm reference', result);

    expect(result.nightHrCoverage, 1);
    expect(result.overallHrCoverage, 1);
    expect(result.accelCoverage, 1);
    _expectWindowNear(result.day, expectedOnset, expectedOffset);
    expect(result.day.sleepSource, 'auto');
  });

  test('valid very-low HR is retained and reaches sleep inference', () {
    final result = _runCase(30);
    _record('30 bpm low-HR', result);

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
    _record('24 bpm below boundary', result);

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
}
