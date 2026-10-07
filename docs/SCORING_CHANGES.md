# Scoring and analytics changes

Use this workflow for every scoring or analytics change. Keep the investigation
evidence with the change so reviewers can trace the reported failure to the
result and its regression coverage.

```text
BUG
  ->
reproducing data
  ->
current result
  ->
hypothesis
  ->
regression test
  ->
change
  ->
new result
  ->
regression suite
  ->
holdout validation
  ->
merge
```

## Required workflow

1. **BUG:** State the observed failure and which output is wrong or missing.
2. **Reproducing data:** Find the smallest data set that reliably reproduces
   it. Record relevant input coverage, source, and algorithm version. Never
   change an algorithm based only on intuition; reproduce the failure first.
3. **Current result:** Run the current implementation on that data and record
   the result, including any absence reason or provenance that explains it.
4. **Hypothesis:** Describe the specific cause that could produce the observed
   result. Keep it testable against the reproducing data.
5. **Regression test:** Add a test that expresses the failure and verify that
   it fails before the fix. Put scoring and metric tests in
   `OpenStrap/analytics`; add an `edge` integration test only when it covers
   edge-owned storage, orchestration, or UI behavior.
6. **Change:** Make the smallest change in the repository that owns the
   behavior. Absent or insufficient input must remain absent; never fabricate,
   impute, or substitute a metric.
7. **New result:** Run the same reproducing data again and compare the result
   with the recorded current result. Explain the intended change and any other
   output differences.
8. **Regression suite:** Run the focused regression tests and the relevant
   repository suite before proposing a merge. Preserve existing coverage for
   absence, provenance, repeat derivation, and other affected behavior.
9. **Holdout validation:** Check representative data that was not used to form
   the hypothesis or tune the change. Holdout data may be tested locally, but
   personal or raw WHOOP data must stay outside Git.
10. **Merge:** Merge only after the before/after comparison, regression suite,
    and holdout validation have been reviewed.

## Data and repository boundaries

- Keep real or personal WHOOP data outside Git. Commit only synthetic fixtures
  or anonymized and date-shifted fixtures. Never commit secrets, exports,
  database dumps, personal identifiers, or real raw fixtures.
- Metric and scoring logic belongs in `OpenStrap/analytics`, not `edge`.
  Protocol-level byte, GATT, framing, opcode, or decode changes belong in
  `OpenStrap/protocol`. `edge` owns storage, orchestration, BLE flows, and UI.
- Missing or insufficient inputs must produce an absent value and an honest
  reason where available. A zero, default, or plausible substitute is not a
  valid replacement for an absent measurement.
- Any analytics output change must follow [`AGENTS.md`](../AGENTS.md): pin the
  sibling dependency by its full commit SHA in `pubspec.yaml`, verify that SHA
  contains the intended change, and bump `kAlgoVersion` in
  `lib/compute/derivation_engine.dart` with a changelog entry above the
  constant. A lockfile change does not replace the required sibling pin.
