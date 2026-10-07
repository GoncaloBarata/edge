import '../models/metric.dart';

enum SupportSnapshotStatus { present, absent, unavailable }

enum SupportSnapshotSource { onDeviceDerived, imported, unknown }

/// A typed value with an explicit absence state. A measured zero is present;
/// it is never collapsed into either absence or unavailable data.
class SupportSnapshotValue<T> {
  const SupportSnapshotValue._(this.status, this.value);

  const SupportSnapshotValue.present(T value)
    : this._(SupportSnapshotStatus.present, value);

  const SupportSnapshotValue.absent()
    : this._(SupportSnapshotStatus.absent, null);

  const SupportSnapshotValue.unavailable()
    : this._(SupportSnapshotStatus.unavailable, null);

  final SupportSnapshotStatus status;
  final T? value;
}

class ReadinessInputDiagnostic {
  const ReadinessInputDiagnostic({
    required this.name,
    required this.measured,
    required this.baselineNights,
    required this.settledFraction,
  });

  final String name;
  final SupportSnapshotValue<bool> measured;
  final SupportSnapshotValue<int> baselineNights;
  final SupportSnapshotValue<double> settledFraction;
}

/// Immutable, privacy-allowlisted data for the copy-only support report.
///
/// [fromStoredData] is the sole boundary that accepts repository projections.
/// It copies known scalar fields into this model and never retains a source map.
class SupportSnapshot {
  SupportSnapshot({
    required this.appVersion,
    required this.buildNumber,
    required this.deviceFamily,
    required this.day,
    required this.source,
    required this.algorithmVersion,
    required this.wearMinutes,
    required this.wearCoveragePercent,
    required this.sleepStatus,
    required this.sleepSource,
    required this.sleepWindowStart,
    required this.sleepWindowEnd,
    required this.sleepDurationMinutes,
    required this.sleepStageConfidence,
    required this.hrvStatus,
    required this.hrvRmssd,
    required this.hrvRrBeats,
    required this.hrvCleanBeats,
    required this.hrvCleanFraction,
    required this.hrvConfidence,
    required this.hrvNote,
    required this.respiratoryStatus,
    required this.respiratoryRate,
    required this.respiratoryConfidence,
    required this.respiratoryNote,
    required this.readinessScore,
    required this.readinessDiagnosticStatus,
    required this.readinessDiagnosticNote,
    required List<ReadinessInputDiagnostic> readinessInputs,
  }) : readinessInputs = List.unmodifiable(readinessInputs);

  final SupportSnapshotValue<String> appVersion;
  final SupportSnapshotValue<String> buildNumber;
  final String deviceFamily;
  final SupportSnapshotValue<String> day;
  final SupportSnapshotSource source;
  final SupportSnapshotValue<int> algorithmVersion;
  final SupportSnapshotValue<int> wearMinutes;
  final SupportSnapshotValue<int> wearCoveragePercent;
  final SupportSnapshotStatus sleepStatus;
  final SupportSnapshotValue<String> sleepSource;
  final SupportSnapshotValue<String> sleepWindowStart;
  final SupportSnapshotValue<String> sleepWindowEnd;
  final SupportSnapshotValue<int> sleepDurationMinutes;
  final SupportSnapshotValue<double> sleepStageConfidence;
  final SupportSnapshotStatus hrvStatus;
  final SupportSnapshotValue<double> hrvRmssd;
  final SupportSnapshotValue<int> hrvRrBeats;
  final SupportSnapshotValue<int> hrvCleanBeats;
  final SupportSnapshotValue<double> hrvCleanFraction;
  final SupportSnapshotValue<double> hrvConfidence;
  final SupportSnapshotValue<String> hrvNote;
  final SupportSnapshotStatus respiratoryStatus;
  final SupportSnapshotValue<double> respiratoryRate;
  final SupportSnapshotValue<double> respiratoryConfidence;
  final SupportSnapshotValue<String> respiratoryNote;
  final SupportSnapshotValue<double> readinessScore;
  final SupportSnapshotStatus readinessDiagnosticStatus;
  final SupportSnapshotValue<String> readinessDiagnosticNote;
  final List<ReadinessInputDiagnostic> readinessInputs;

  factory SupportSnapshot.fromStoredData({
    required String? appVersion,
    required String? buildNumber,
    required String? day,
    required int? algorithmVersion,
    required String? importedFrom,
    required Object? deviceFamily,
    required Map<String, dynamic> wear,
    required Map<String, dynamic> sleep,
    required Map<String, dynamic> hrv,
    required Map<String, dynamic> heart,
    required Map<String, dynamic> lungs,
    required Map<String, dynamic>? readinessAbsentDiagnostic,
  }) {
    final sleepStatus = _sleepStatus(sleep);
    final rmssd = _numberAt(hrv, 'rmssd');
    final respiratory = _lookup(lungs, 'resp');
    final respiratoryValue = _respiratoryValue(
      respiratory,
      projectionPresent: lungs.containsKey('resp'),
    );
    final readiness = _numberAt(heart, 'recovery');
    final readinessDiagnosticStatus = switch (readiness.status) {
      SupportSnapshotStatus.present => SupportSnapshotStatus.absent,
      SupportSnapshotStatus.absent =>
        readinessAbsentDiagnostic == null
            ? SupportSnapshotStatus.unavailable
            : SupportSnapshotStatus.present,
      SupportSnapshotStatus.unavailable => SupportSnapshotStatus.unavailable,
    };

    return SupportSnapshot(
      appVersion: _packageField(appVersion),
      buildNumber: _packageField(buildNumber),
      deviceFamily: _deviceFamilyLabel(deviceFamily),
      day: _dayField(day),
      source: _source(importedFrom, algorithmVersion),
      algorithmVersion: algorithmVersion == null
          ? const SupportSnapshotValue.unavailable()
          : SupportSnapshotValue.present(algorithmVersion),
      wearMinutes: _integerAt(wear, 'worn_min'),
      wearCoveragePercent: _integerAt(wear, 'coverage_pct'),
      sleepStatus: sleepStatus,
      sleepSource: _sleepSource(sleep),
      sleepWindowStart: _localTimeAt(sleep, 'onset_ts'),
      sleepWindowEnd: _localTimeAt(sleep, 'wake_ts'),
      sleepDurationMinutes: _integerAt(sleep, 'duration_min'),
      sleepStageConfidence: _boundedFractionAt(sleep, 'stages_confidence'),
      hrvStatus: rmssd.status,
      hrvRmssd: rmssd,
      hrvRrBeats: _integerAt(_lookup(hrv, 'coverage'), 'rr_beats'),
      hrvCleanBeats: _integerAt(_lookup(hrv, 'coverage'), 'nn_clean'),
      hrvCleanFraction: _boundedFractionAt(
        _lookup(hrv, 'coverage'),
        'clean_fraction',
      ),
      hrvConfidence: _metricConfidence(_lookup(hrv, 'hrv_time')),
      hrvNote: _safeMetricNote(_lookup(hrv, 'hrv_time')),
      respiratoryStatus: respiratoryValue.status,
      respiratoryRate: respiratoryValue,
      respiratoryConfidence: _metricConfidence(respiratory),
      respiratoryNote: _safeMetricNote(respiratory),
      readinessScore: readiness,
      readinessDiagnosticStatus: readinessDiagnosticStatus,
      readinessDiagnosticNote:
          readinessDiagnosticStatus == SupportSnapshotStatus.present
          ? _safeMetricNote(readinessAbsentDiagnostic)
          : readinessDiagnosticStatus == SupportSnapshotStatus.absent
          ? const SupportSnapshotValue.absent()
          : const SupportSnapshotValue.unavailable(),
      readinessInputs: _readinessInputs(readinessAbsentDiagnostic),
    );
  }

  String format() => formatSupportSnapshot(this);
}

String formatSupportSnapshot(SupportSnapshot snapshot) {
  final out = StringBuffer()
    ..writeln('OpenStrap support snapshot')
    ..writeln('App version: ${_display(snapshot.appVersion, (v) => v)}')
    ..writeln('Build: ${_display(snapshot.buildNumber, (v) => v)}')
    ..writeln('Device family: ${snapshot.deviceFamily}')
    ..writeln('Selected local day: ${_display(snapshot.day, (v) => v)}')
    ..writeln('Data source: ${_sourceLabel(snapshot.source)}')
    ..writeln(
      'Stored algorithm version: ${_display(snapshot.algorithmVersion, (v) => 'v$v')}',
    )
    ..writeln('Wear time: ${_display(snapshot.wearMinutes, (v) => '$v min')}')
    ..writeln(
      'Wear coverage: ${_display(snapshot.wearCoveragePercent, (v) => '$v%')}',
    )
    ..writeln('Sleep status: ${_statusLabel(snapshot.sleepStatus)}')
    ..writeln('Sleep source: ${_display(snapshot.sleepSource, (v) => v)}')
    ..writeln(
      'Sleep window start: ${_display(snapshot.sleepWindowStart, (v) => v)}',
    )
    ..writeln(
      'Sleep window end: ${_display(snapshot.sleepWindowEnd, (v) => v)}',
    )
    ..writeln(
      'Sleep duration: ${_display(snapshot.sleepDurationMinutes, (v) => '$v min')}',
    )
    ..writeln(
      'Sleep stage confidence: ${_display(snapshot.sleepStageConfidence, (v) => v.toStringAsFixed(2))}',
    )
    ..writeln('HRV status: ${_statusLabel(snapshot.hrvStatus)}')
    ..writeln(
      'HRV RMSSD: ${_display(snapshot.hrvRmssd, (v) => '${v.toStringAsFixed(1)} ms')}',
    )
    ..writeln('HRV RR beats: ${_display(snapshot.hrvRrBeats, (v) => '$v')}')
    ..writeln(
      'HRV clean beats: ${_display(snapshot.hrvCleanBeats, (v) => '$v')}',
    )
    ..writeln(
      'HRV clean fraction: ${_display(snapshot.hrvCleanFraction, (v) => v.toStringAsFixed(2))}',
    )
    ..writeln(
      'HRV confidence: ${_display(snapshot.hrvConfidence, (v) => v.toStringAsFixed(2))}',
    )
    ..writeln('HRV note: ${_display(snapshot.hrvNote, (v) => v)}')
    ..writeln('Respiratory status: ${_statusLabel(snapshot.respiratoryStatus)}')
    ..writeln(
      'Respiratory rate: ${_display(snapshot.respiratoryRate, (v) => '${v.toStringAsFixed(1)} breaths/min')}',
    )
    ..writeln(
      'Respiratory confidence: ${_display(snapshot.respiratoryConfidence, (v) => v.toStringAsFixed(2))}',
    )
    ..writeln(
      'Respiratory note: ${_display(snapshot.respiratoryNote, (v) => v)}',
    )
    ..writeln(
      'Readiness score: ${_display(snapshot.readinessScore, (v) => v.toStringAsFixed(1))}',
    )
    ..writeln(
      'Readiness absent diagnostic: ${_statusLabel(snapshot.readinessDiagnosticStatus)}',
    )
    ..writeln(
      'Readiness diagnostic note: ${_display(snapshot.readinessDiagnosticNote, (v) => v)}',
    );

  for (final input in snapshot.readinessInputs) {
    final name = _readinessInputLabel(input.name);
    if (input.measured.status != SupportSnapshotStatus.unavailable) {
      out.writeln(
        '$name measured: ${_display(input.measured, (v) => v ? 'yes' : 'no')}',
      );
    }
    if (input.baselineNights.status != SupportSnapshotStatus.unavailable) {
      out.writeln(
        '$name baseline nights: ${_display(input.baselineNights, (v) => '$v')}',
      );
    }
    if (input.settledFraction.status != SupportSnapshotStatus.unavailable) {
      out.writeln(
        '$name settled fraction: ${_display(input.settledFraction, (v) => v.toStringAsFixed(2))}',
      );
    }
  }
  return out.toString().trimRight();
}

String _display<T>(SupportSnapshotValue<T> field, String Function(T) render) {
  switch (field.status) {
    case SupportSnapshotStatus.present:
      final value = field.value;
      return value == null ? 'Unavailable' : 'Present (${render(value)})';
    case SupportSnapshotStatus.absent:
      return 'Absent';
    case SupportSnapshotStatus.unavailable:
      return 'Unavailable';
  }
}

String _statusLabel(SupportSnapshotStatus status) => switch (status) {
  SupportSnapshotStatus.present => 'Present',
  SupportSnapshotStatus.absent => 'Absent',
  SupportSnapshotStatus.unavailable => 'Unavailable',
};

SupportSnapshotValue<String> _packageField(String? value) {
  if (value == null || value.isEmpty) {
    return const SupportSnapshotValue.unavailable();
  }
  return RegExp(r'^[A-Za-z0-9.+_-]{1,40}$').hasMatch(value)
      ? SupportSnapshotValue.present(value)
      : const SupportSnapshotValue.unavailable();
}

SupportSnapshotValue<String> _dayField(String? value) {
  if (value == null || value.isEmpty) {
    return const SupportSnapshotValue.unavailable();
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return const SupportSnapshotValue.unavailable();
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year.toString().padLeft(4, '0') != value.substring(0, 4) ||
      date.month.toString().padLeft(2, '0') != value.substring(5, 7) ||
      date.day.toString().padLeft(2, '0') != value.substring(8, 10)) {
    return const SupportSnapshotValue.unavailable();
  }
  return SupportSnapshotValue.present(value);
}

SupportSnapshotSource _source(String? importedFrom, int? algorithmVersion) {
  if (importedFrom != null) return SupportSnapshotSource.imported;
  if (algorithmVersion != null) return SupportSnapshotSource.onDeviceDerived;
  return SupportSnapshotSource.unknown;
}

String _sourceLabel(SupportSnapshotSource source) => switch (source) {
  SupportSnapshotSource.onDeviceDerived => 'On-device derived',
  SupportSnapshotSource.imported => 'Imported',
  SupportSnapshotSource.unknown => 'Unknown',
};

String _deviceFamilyLabel(Object? family) => switch (family) {
  'gen4' => 'WHOOP 4',
  'gen5' => 'WHOOP 5',
  _ => 'Unknown',
};

SupportSnapshotStatus _sleepStatus(Object? sleep) {
  if (sleep is! Map || !sleep.containsKey('has_sleep')) {
    return SupportSnapshotStatus.unavailable;
  }
  return switch (sleep['has_sleep']) {
    true => SupportSnapshotStatus.present,
    false => SupportSnapshotStatus.absent,
    _ => SupportSnapshotStatus.unavailable,
  };
}

SupportSnapshotValue<String> _sleepSource(Object? sleep) {
  if (sleep is! Map || !sleep.containsKey('sleep_source')) {
    return const SupportSnapshotValue.unavailable();
  }
  final raw = sleep['sleep_source'];
  if (raw == null) return const SupportSnapshotValue.absent();
  final label = switch (raw) {
    'auto' => 'Auto',
    'auto_fallback' => 'Auto fallback',
    'manual' => 'Manual',
    'confirmed' => 'Confirmed',
    'none' => 'None',
    _ => 'Unknown',
  };
  return SupportSnapshotValue.present(label);
}

SupportSnapshotValue<double> _numberAt(Object? source, String key) {
  if (source is! Map || !source.containsKey(key)) {
    return const SupportSnapshotValue.unavailable();
  }
  final raw = source[key];
  if (raw == null) return const SupportSnapshotValue.absent();
  if (raw is! num || !raw.isFinite) {
    return const SupportSnapshotValue.unavailable();
  }
  return SupportSnapshotValue.present(raw.toDouble());
}

SupportSnapshotValue<int> _integerAt(Object? source, String key) {
  if (source is! Map || !source.containsKey(key)) {
    return const SupportSnapshotValue.unavailable();
  }
  final raw = source[key];
  if (raw == null) return const SupportSnapshotValue.absent();
  if (raw is! num || !raw.isFinite || raw != raw.toInt()) {
    return const SupportSnapshotValue.unavailable();
  }
  return SupportSnapshotValue.present(raw.toInt());
}

SupportSnapshotValue<double> _boundedFractionAt(Object? source, String key) {
  final value = _numberAt(source, key);
  if (value.status != SupportSnapshotStatus.present) return value;
  final fraction = value.value!;
  if (fraction < 0 || fraction > 1) {
    return const SupportSnapshotValue.unavailable();
  }
  return value;
}

SupportSnapshotValue<double> _metricConfidence(Object? raw) {
  if (raw is! Map || !raw.containsKey('confidence')) {
    return const SupportSnapshotValue.unavailable();
  }
  final confidence = raw['confidence'];
  if (confidence == null) return const SupportSnapshotValue.absent();
  if (confidence is! num ||
      !confidence.isFinite ||
      confidence < 0 ||
      confidence > 1) {
    return const SupportSnapshotValue.unavailable();
  }
  return SupportSnapshotValue.present(confidence.toDouble());
}

SupportSnapshotValue<double> _metricNumber(Metric metric) {
  final value = metric.value;
  if (value == null) return const SupportSnapshotValue.absent();
  if (!value.isFinite || metric.confidence <= 0) {
    return const SupportSnapshotValue.absent();
  }
  return SupportSnapshotValue.present(value.toDouble());
}

SupportSnapshotValue<double> _respiratoryValue(
  Object? raw, {
  required bool projectionPresent,
}) {
  if (!projectionPresent) return const SupportSnapshotValue.unavailable();
  if (raw == null) return const SupportSnapshotValue.absent();
  if (raw is! Map) return const SupportSnapshotValue.unavailable();
  return _metricNumber(Metric.parse(raw));
}

SupportSnapshotValue<String> _safeMetricNote(Object? raw) {
  if (raw is! Map || !raw.containsKey('note')) {
    return const SupportSnapshotValue.unavailable();
  }
  final note = raw['note'];
  if (note == null || note == '') {
    return const SupportSnapshotValue.absent();
  }
  if (note is! String) return const SupportSnapshotValue.unavailable();
  if (!_isAllowlistedMetricNote(note)) {
    return const SupportSnapshotValue.absent();
  }
  final explanation = whyFromNote(note);
  return explanation == null || explanation.isEmpty
      ? const SupportSnapshotValue.absent()
      : SupportSnapshotValue.present(explanation);
}

// Support Snapshot copies diagnostic notes off-device, so only notes with a
// reviewed application meaning may reach whyFromNote(). That helper also
// passes arbitrary prose through for ordinary UI surfaces.
bool _isAllowlistedMetricNote(String note) {
  if (RegExp(r'^need_baseline:have=\d+,need=\d+$').hasMatch(note)) {
    return true;
  }

  final input = RegExp(
    r'^need_input:name=([a-z0-9_]+)(?:,have=\d+,need=\d+)?$',
  ).firstMatch(note);
  if (input != null && _safeNeedInputNames.contains(input.group(1))) {
    return true;
  }

  return RegExp(
    r'^unknown_device_family(?::id=[A-Za-z0-9_-]+)?$',
  ).hasMatch(note);
}

// Keep this list explicit: a new need_input key must be reviewed for copied
// support output instead of becoming shareable automatically.
const _safeNeedInputNames = <String>{
  'age',
  'weight_kg',
  'height_cm',
  'sex',
  'wake_hr',
  'hr_samples',
  'resting_hr',
  'scored_night',
  'nn_beats',
  'resp_windows',
  'accel_1hz',
  'imported_day',
  'today_activity',
  'tst_min',
  'wake_time',
  'efficiency',
  'observed_ceiling',
  'maximal_effort',
  'resting_hr_days',
  'manual_zones',
  'sessions',
};

SupportSnapshotValue<String> _localTimeAt(Object? source, String key) {
  final seconds = _integerAt(source, key);
  if (seconds.status != SupportSnapshotStatus.present) {
    return switch (seconds.status) {
      SupportSnapshotStatus.absent => const SupportSnapshotValue.absent(),
      SupportSnapshotStatus.unavailable =>
        const SupportSnapshotValue.unavailable(),
      SupportSnapshotStatus.present => const SupportSnapshotValue.unavailable(),
    };
  }
  try {
    final local = DateTime.fromMillisecondsSinceEpoch(seconds.value! * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return SupportSnapshotValue.present(
      '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)} local',
    );
  } catch (_) {
    return const SupportSnapshotValue.unavailable();
  }
}

Object? _lookup(Object? source, String key) =>
    source is Map ? source[key] : null;

SupportSnapshotValue<bool> _boolAt(Object? source, String key) {
  if (source is! Map || !source.containsKey(key)) {
    return const SupportSnapshotValue.unavailable();
  }
  final value = source[key];
  if (value == null) return const SupportSnapshotValue.absent();
  if (value is! bool) return const SupportSnapshotValue.unavailable();
  return SupportSnapshotValue.present(value);
}

SupportSnapshotValue<double> _boundedFractionField(
  Object? source,
  String key,
) => _boundedFractionAt(source, key);

List<ReadinessInputDiagnostic> _readinessInputs(Object? diagnostic) {
  if (diagnostic is! Map) return const [];
  const names = <String, String>{
    'hrv': 'HRV',
    'rhr': 'Resting heart rate',
    'resp': 'Respiratory rate',
    'temp': 'Temperature',
  };
  final out = <ReadinessInputDiagnostic>[];
  for (final entry in names.entries) {
    final raw = diagnostic[entry.key];
    if (raw is! Map) continue;
    final temp = entry.key == 'temp';
    final item = ReadinessInputDiagnostic(
      name: entry.key,
      measured: temp
          ? const SupportSnapshotValue.unavailable()
          : _boolAt(raw, 'value'),
      baselineNights: temp
          ? const SupportSnapshotValue.unavailable()
          : _integerAt(raw, 'baseline_n'),
      settledFraction: temp
          ? _boundedFractionField(raw, 'settled_frac')
          : const SupportSnapshotValue.unavailable(),
    );
    if (item.measured.status != SupportSnapshotStatus.unavailable ||
        item.baselineNights.status != SupportSnapshotStatus.unavailable ||
        item.settledFraction.status != SupportSnapshotStatus.unavailable) {
      out.add(item);
    }
  }
  return out;
}

String _readinessInputLabel(String key) => switch (key) {
  'hrv' => 'HRV',
  'rhr' => 'Resting heart rate',
  'resp' => 'Respiratory rate',
  'temp' => 'Temperature',
  _ => 'Readiness input',
};
