import 'package:flutter/foundation.dart';

import '../../models/metric.dart' show whyFromNote;

/// How much this screen can say about a selected day's stored measurement.
///
/// `limited` is reserved for an explicit limitation attached to an individual
/// measurement. A partial day result is shown separately and never changes all
/// five metric states.
enum DataQualityState { available, limited, withheld, absent, unavailable }

enum DataQualitySleepSource {
  auto,
  autoFallback,
  manual,
  confirmed,
  none,
  rejected,
}

@immutable
class DataQualityWear {
  final DataQualityState state;
  final num? wornMinutes;
  final num? coveragePercent;

  const DataQualityWear({
    required this.state,
    this.wornMinutes,
    this.coveragePercent,
  });
}

@immutable
class DataQualitySleep {
  final DataQualityState state;
  final DataQualitySleepSource? source;

  /// The producer's coverage-derived confidence score, capped at 0.6. It is
  /// neither literal observed coverage, an accuracy estimate, nor a probability.
  final num? stageEvidence;

  const DataQualitySleep({
    required this.state,
    this.source,
    this.stageEvidence,
  });
}

@immutable
class DataQualityHrv {
  final DataQualityState state;
  final num? rrBeats;
  final num? cleanBeats;
  final num? cleanFraction;

  const DataQualityHrv({
    required this.state,
    this.rrBeats,
    this.cleanBeats,
    this.cleanFraction,
  });
}

@immutable
class DataQualityRespiratory {
  final DataQualityState state;
  final String? explanation;

  const DataQualityRespiratory({required this.state, this.explanation});
}

@immutable
class DataQualityReadiness {
  final DataQualityState state;
  final String? explanation;

  const DataQualityReadiness({required this.state, this.explanation});
}

/// Screen-scoped, scalar-only view of the selected day's stored projections.
///
/// The input maps are inspected here and never retained. Unknown map keys,
/// free text, confidence fallbacks, and raw records cannot enter this model.
@immutable
class DataQualitySummary {
  final DataQualityWear wear;
  final DataQualitySleep sleep;
  final DataQualityHrv hrv;
  final DataQualityRespiratory respiratory;
  final DataQualityReadiness readiness;

  /// True only when the stored day-result row explicitly marks itself partial.
  final bool partialStoredResult;

  const DataQualitySummary({
    required this.wear,
    required this.sleep,
    required this.hrv,
    required this.respiratory,
    required this.readiness,
    this.partialStoredResult = false,
  });

  factory DataQualitySummary.fromProjections({
    required Map<String, dynamic>? wear,
    required Map<String, dynamic>? sleep,
    required Map<String, dynamic>? hrv,
    required Map<String, dynamic>? lungs,
    required Map<String, dynamic>? heart,
    required Map<String, dynamic>? readinessAbsentDiagnostic,
    bool readinessDiagnosticAvailable = true,
    Object? partialFlag,
  }) {
    final wearState = _primaryNumberState(wear, 'worn_min');
    final sleepHasNight = sleep?['has_sleep'];
    final sleepState = sleep == null || !sleep.containsKey('has_sleep')
        ? DataQualityState.unavailable
        : sleepHasNight == true
        ? DataQualityState.available
        : sleepHasNight == false
        ? DataQualityState.absent
        : DataQualityState.unavailable;

    final hrvState = _primaryNumberState(hrv, 'rmssd');
    final respProjection = lungs == null || !lungs.containsKey('resp')
        ? null
        : lungs['resp'];
    final respiratory = _respiratory(
      respProjection,
      projectionAvailable: lungs != null && lungs.containsKey('resp'),
    );

    final readinessValueState = _primaryNumberState(heart, 'recovery');
    final readiness = switch (readinessValueState) {
      DataQualityState.available => const DataQualityReadiness(
        state: DataQualityState.available,
      ),
      DataQualityState.unavailable => const DataQualityReadiness(
        state: DataQualityState.unavailable,
      ),
      _ when !readinessDiagnosticAvailable => const DataQualityReadiness(
        state: DataQualityState.unavailable,
      ),
      _ when readinessAbsentDiagnostic != null => DataQualityReadiness(
        state: DataQualityState.withheld,
        explanation: _safeDiagnosticExplanation(
          readinessAbsentDiagnostic['note'],
        ),
      ),
      _ => const DataQualityReadiness(state: DataQualityState.absent),
    };

    return DataQualitySummary(
      wear: DataQualityWear(
        state: wearState,
        wornMinutes: _number(wear?['worn_min']),
        coveragePercent: _number(wear?['coverage_pct']),
      ),
      sleep: DataQualitySleep(
        state: sleepState,
        source: _sleepSource(sleep?['sleep_source']),
        stageEvidence: _stageEvidence(sleep?['stages_confidence']),
      ),
      hrv: DataQualityHrv(
        state: hrvState,
        rrBeats: _number(_map(hrv?['coverage'])?['rr_beats']),
        cleanBeats: _number(_map(hrv?['coverage'])?['nn_clean']),
        cleanFraction: _number(_map(hrv?['coverage'])?['clean_fraction']),
      ),
      respiratory: respiratory,
      readiness: readiness,
      partialStoredResult: partialFlag == true || partialFlag == 1,
    );
  }
}

DataQualityState _primaryNumberState(
  Map<String, dynamic>? projection,
  String key,
) {
  if (projection == null || !projection.containsKey(key)) {
    return DataQualityState.unavailable;
  }
  final value = projection[key];
  if (value == null) return DataQualityState.absent;
  return _number(value) == null
      ? DataQualityState.unavailable
      : DataQualityState.available;
}

DataQualityRespiratory _respiratory(
  Object? projection, {
  required bool projectionAvailable,
}) {
  if (!projectionAvailable) {
    return const DataQualityRespiratory(state: DataQualityState.unavailable);
  }
  if (projection == null) {
    return const DataQualityRespiratory(state: DataQualityState.absent);
  }
  final block = _map(projection);
  if (block == null) {
    return const DataQualityRespiratory(state: DataQualityState.unavailable);
  }
  final value = block['value'];
  if (value is num && value.isFinite) {
    return const DataQualityRespiratory(state: DataQualityState.available);
  }
  if (value != null) {
    return const DataQualityRespiratory(state: DataQualityState.unavailable);
  }

  final note = block['note'];
  if (note is String && note.trim().isNotEmpty) {
    return DataQualityRespiratory(
      state: DataQualityState.withheld,
      explanation: _safeDiagnosticExplanation(note),
    );
  }
  if (!block.containsKey('value')) {
    return const DataQualityRespiratory(state: DataQualityState.unavailable);
  }
  return const DataQualityRespiratory(state: DataQualityState.absent);
}

DataQualitySleepSource? _sleepSource(Object? value) => switch (value) {
  'auto' => DataQualitySleepSource.auto,
  'auto_fallback' => DataQualitySleepSource.autoFallback,
  'manual' => DataQualitySleepSource.manual,
  'confirmed' => DataQualitySleepSource.confirmed,
  'none' => DataQualitySleepSource.none,
  'rejected' => DataQualitySleepSource.rejected,
  _ => null,
};

/// Only known machine note grammars reach [whyFromNote]. That helper also
/// accepts arbitrary prose for other screens, which is outside this model's
/// privacy boundary. Unknown notes still establish withholding, but contribute
/// no explanation.
String? _safeDiagnosticExplanation(Object? value) {
  if (value is! String) return null;
  final note = value.trim();
  if (RegExp(r'^need_baseline:have=\d+,need=\d+$').hasMatch(note) ||
      RegExp(
        r'^need_input:name=[a-z0-9_]+(?:,have=\d+,need=\d+)?$',
      ).hasMatch(note) ||
      note == 'unknown_device_family' ||
      note == 'unknown_device_family:id=none') {
    return whyFromNote(note);
  }
  return null;
}

Map? _map(Object? value) => value is Map ? value : null;

num? _number(Object? value) => value is num && value.isFinite ? value : null;

num? _stageEvidence(Object? value) {
  final score = _number(value);
  if (score == null) return null;
  return score > 0.6 ? 0.6 : score;
}
