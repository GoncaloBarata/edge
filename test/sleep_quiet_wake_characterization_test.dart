import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _timezone = 'Europe/Lisbon';
const _captureSeconds = 12 * 60 * 60;
const _sleepOnsetIndex = 60 * 60; // 23:00 local; capture starts at 22:00
const _finalWakeIndex = 8 * 60 * 60; // 06:00 local
const _targetDay = '2025-06-16';

final _captureStartSec =
    DateTime.utc(2025, 6, 15, 21).millisecondsSinceEpoch ~/ 1000;

enum _WakeSignal { ordinary, quiet, clear }

typedef _Fixture = ({
  Substrate substrate,
  PreparedDerivationDay day,
  int confirmedWakeSec,
  int leaveBedSec,
  int trueAwakeInBedMinutes,
  String caseName,
});

List<Map<String, dynamic>> _decodedRows({
  required int awakeInBedMinutes,
  required _WakeSignal signal,
  bool gen5BandEnvelope = false,
}) => [
  for (var i = 0; i < _captureSeconds; i++)
    () {
      final t = _captureStartSec + i;
      final beforeSleep = i < _sleepOnsetIndex;
      final asleepBySignal = i >= _sleepOnsetIndex && i < _finalWakeIndex;
      final inPostWakeInterval =
          i >= _finalWakeIndex && i < _finalWakeIndex + awakeInBedMinutes * 60;
      final sleepingLike =
          asleepBySignal || (inPostWakeInterval && signal == _WakeSignal.quiet);
      final clearlyAwake =
          (inPostWakeInterval && signal == _WakeSignal.clear) ||
          i >= _finalWakeIndex + awakeInBedMinutes * 60;

      final hr = beforeSleep
          ? 74 + 2 * math.sin(i / 90.0)
          : (sleepingLike
                ? (i < _finalWakeIndex ? 52 : 57) + 1.5 * math.sin(i / 1800.0)
                : (clearlyAwake ? 86 : 72) + 2 * math.sin(i / 120.0));

      var ax = 0.02;
      var ay = 0.02;
      var az = 1.0;
      if (beforeSleep || clearlyAwake) {
        final phase = math.sin(i * 0.5);
        ax = 0.3 * phase;
        ay = 0.3;
        az = 0.9 * (1 - 0.2 * phase);
      } else if (inPostWakeInterval && signal == _WakeSignal.quiet) {
        // Small wrist adjustment every 15 minutes; no phone-use input exists.
        final pulseSecond = (i - _finalWakeIndex) % 900;
        if (pulseSecond < 5) {
          ax = 0.02 + 0.025 * math.sin(pulseSecond * math.pi / 4);
          ay = 0.02;
          az = math.sqrt(1 - ax * ax - ay * ay);
        }
      }

      final band = !gen5BandEnvelope
          ? -1
          : (i < _sleepOnsetIndex
                ? 0
                : (i < _finalWakeIndex
                      ? 2
                      : (i < _finalWakeIndex + awakeInBedMinutes * 60
                            ? 3
                            : 0)));
      return <String, dynamic>{
        'rec_ts': t,
        'hr': hr.round(),
        'ax': ax,
        'ay': ay,
        'az': az,
        if (gen5BandEnvelope) 'band_sleep_state': band,
      };
    }(),
];

_Fixture _runCase({
  required String caseName,
  required int awakeInBedMinutes,
  required _WakeSignal signal,
  bool continuedSleepTruth = false,
  bool gen5BandEnvelope = false,
}) {
  final substrate = substrateFromDecodedPage(
    _decodedRows(
      awakeInBedMinutes: awakeInBedMinutes,
      signal: signal,
      gen5BandEnvelope: gen5BandEnvelope,
    ),
    const [],
  );
  final prepared = prepareDerivationPayload(substrate, targetDay: _targetDay);
  expect(prepared.days, hasLength(1), reason: 'fixed local target day exists');
  final day = prepared.days.single;
  final wake = _captureStartSec + _finalWakeIndex;
  final leave = wake + awakeInBedMinutes * 60;
  return (
    substrate: substrate,
    day: day,
    confirmedWakeSec: continuedSleepTruth ? leave : wake,
    leaveBedSec: leave,
    trueAwakeInBedMinutes: continuedSleepTruth ? 0 : awakeInBedMinutes,
    caseName: caseName,
  );
}

String _localTime(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toIso8601String();

Map<String, int> _stageCounts(List<String> stages) {
  final counts = <String, int>{};
  for (final stage in stages) {
    counts.update(stage, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

double? _meanWakeHr(_Fixture result) {
  final from = result.confirmedWakeSec - _captureStartSec;
  final until = result.leaveBedSec - _captureStartSec;
  if (until <= from) return null;
  final values = result.substrate.hr.sublist(from, until);
  return values.reduce((a, b) => a + b) / values.length;
}

double? _meanWakeMovement(_Fixture result) {
  final from = result.confirmedWakeSec - _captureStartSec;
  final until = result.leaveBedSec - _captureStartSec;
  if (until - from < 2) return null;
  var sum = 0.0;
  for (var i = from + 1; i < until; i++) {
    final dx = result.substrate.ax[i] - result.substrate.ax[i - 1];
    final dy = result.substrate.ay[i] - result.substrate.ay[i - 1];
    final dz = result.substrate.az[i] - result.substrate.az[i - 1];
    sum += math.sqrt(dx * dx + dy * dy + dz * dz);
  }
  return sum / (until - from - 1);
}

void _record(_Fixture result) {
  final day = result.day;
  final extensionMinutes = day.sleepOffsetSec == 0
      ? null
      : math.max(0, (day.sleepOffsetSec - result.confirmedWakeSec) ~/ 60);
  // ignore: avoid_print
  print(
    'EDGE ${result.caseName}: timezone=$_timezone, '
    'true onset=${_localTime(_captureStartSec + _sleepOnsetIndex)}, '
    'confirmed wake=${_localTime(result.confirmedWakeSec)}, '
    'leave bed=${_localTime(result.leaveBedSec)}, '
    'awake-in-bed=${result.trueAwakeInBedMinutes}m, '
    'detected=[${_localTime(day.sleepOnsetSec)}, ${_localTime(day.sleepOffsetSec)}), '
    'extension=${extensionMinutes}m, source=${day.sleepSource}, '
    'in-bed=${day.sleepJson['in_bed_sec']}, TST=${day.sleepJson['tst_sec']}, '
    'WASO=${day.sleepJson['waso_sec']}, '
    'unobserved=${day.sleepJson['unobserved_sec']}, '
    'stages=${_stageCounts(day.hypnoStages)}, '
    'wake-HR-mean=${_meanWakeHr(result)?.toStringAsFixed(2) ?? 'n/a'}, '
    'wake-mean-|delta-g|=${_meanWakeMovement(result)?.toStringAsFixed(5) ?? 'n/a'}',
  );
}

void main() {
  test('same-day preparation characterizes 30/60/90-minute wake cases', () {
    final control = _runCase(
      caseName: 'CONTROL ordinary waking activity',
      awakeInBedMinutes: 0,
      signal: _WakeSignal.ordinary,
    );
    _record(control);
    expect(control.day.sleepSource, 'auto');
    expect(
      control.day.sleepOnsetSec,
      _captureStartSec + _sleepOnsetIndex + 171,
      reason: 'pins the current 23:02:51 detected onset for this fixture',
    );
    expect(
      control.day.sleepOffsetSec,
      control.confirmedWakeSec - 170,
      reason:
          'pins the prepared-day offset conversion, one second after Analytics',
    );
    expect(control.day.sleepJson['tst_sec'], isA<num>());

    for (final minutes in [30, 60, 90]) {
      final quiet = _runCase(
        caseName: 'QUIET WAKE ${minutes}m',
        awakeInBedMinutes: minutes,
        signal: _WakeSignal.quiet,
      );
      final clear = _runCase(
        caseName: 'CLEAR WAKE ${minutes}m',
        awakeInBedMinutes: minutes,
        signal: _WakeSignal.clear,
      );
      final continuedSleep = _runCase(
        caseName: 'SENSOR-INDISTINGUISHABLE continued sleep ${minutes}m',
        awakeInBedMinutes: minutes,
        signal: _WakeSignal.quiet,
        continuedSleepTruth: true,
      );
      _record(quiet);
      _record(clear);
      _record(continuedSleep);

      // Different ground-truth stories, identical decoded sensor observations.
      expect(quiet.substrate.tsSec, continuedSleep.substrate.tsSec);
      expect(quiet.substrate.hr, continuedSleep.substrate.hr);
      expect(quiet.substrate.ax, continuedSleep.substrate.ax);
      expect(quiet.substrate.ay, continuedSleep.substrate.ay);
      expect(quiet.substrate.az, continuedSleep.substrate.az);
      expect(quiet.day.sleepJson, continuedSleep.day.sleepJson);
      expect(quiet.day.sleepOnsetSec, continuedSleep.day.sleepOnsetSec);
      expect(quiet.day.sleepOffsetSec, continuedSleep.day.sleepOffsetSec);

      // Pin the observed output for these exact synthetic signals. Quiet
      // wake ends the window 2:50 before leaving bed; clear wake ends it 2:50
      // before the confirmed wake. The prepared-day offset is one second after
      // Analytics' raw segment boundary. These are fixture characterizations,
      // not target thresholds for other nights.
      expect(
        quiet.day.sleepOnsetSec,
        _captureStartSec + _sleepOnsetIndex + 171,
      );
      expect(quiet.day.sleepOffsetSec, quiet.leaveBedSec - 170);
      expect(clear.day.sleepOffsetSec, clear.confirmedWakeSec - 170);
      for (final day in [quiet.day, clear.day]) {
        expect(day.sleepJson['in_bed_sec'], isA<num>());
        expect(day.sleepJson['tst_sec'], day.sleepJson['in_bed_sec']);
        expect(day.sleepJson['waso_sec'], 0);
        expect(day.sleepJson['unobserved_sec'], 0);
        // The Edge-pinned Analytics revision stages this integer-HR fixture
        // entirely as light inside the detected window.
        expect(day.hypnoStages.toSet(), {'light'});
      }

      expect(quiet.day.sleepSource, 'auto');
      expect(clear.day.sleepSource, 'auto');
      expect(
        quiet.substrate.bandSleepState.every((state) => state == -1),
        isTrue,
        reason: 'sensor-only fixture supplies no Gen5/MG envelope',
      );
    }
  });

  test('synthetic Gen5/MG envelope versus sensor-only Edge preparation', () {
    for (final minutes in [30, 60, 90]) {
      final noBand = _runCase(
        caseName: 'GEN5/MG-model no envelope ${minutes}m',
        awakeInBedMinutes: minutes,
        signal: _WakeSignal.quiet,
      );
      final withBand = _runCase(
        caseName: 'GEN5/MG-model UP at wake ${minutes}m',
        awakeInBedMinutes: minutes,
        signal: _WakeSignal.quiet,
        gen5BandEnvelope: true,
      );
      _record(noBand);
      _record(withBand);
      expect(withBand.day.sleepJson['band_offset_trim_sec'], isA<num>());
      expect(withBand.day.sleepOffsetSec, withBand.confirmedWakeSec + 1);
      expect(noBand.day.sleepJson['band_offset_trim_sec'], isNull);
    }
  });
}
