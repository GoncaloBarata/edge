# Fork workflow

## Remotes and branches

- `origin` is this fork: <https://github.com/GoncaloBarata/edge.git>.
- `upstream` is the OpenStrap project: <https://github.com/OpenStrap/edge.git>.
- Treat `upstream` as fetch-only. Fetch changes from it; never push to it.
- Keep `main` close to the corresponding upstream branch. Develop on focused
  `feature/*` or `chore/*` branches created from an up-to-date `main`.
- Push fork work to `origin` only after review and validation.

## Safe upstream sync

Start with a clean working tree. Preserve or finish any local changes on their
current branch before syncing; do not discard them to make the sync proceed.
Then review and fast-forward the fork's `main`:

```sh
git status --short
git switch main
git status --short
git fetch upstream --prune
git log --oneline --left-right main...upstream/main
git merge --ff-only upstream/main
```

Confirm the upstream default branch is `main` before using `upstream/main`.
Review the fetched commits and resulting `main` before pushing that fast-forward
to `origin`. If the fast-forward is refused or the branches have fork-only
commits, stop and inspect the divergence before choosing a reviewed integration
plan. Do not reset, force-push, or merge blindly to make the histories line up.

Create work branches from the reviewed `main`:

```sh
git switch -c feature/<short-name>   # or chore/<short-name>
```

Keep changes scoped to the owning repository below, run the relevant validation,
and merge reviewed work back through the fork's normal review process. Keep
`main` synchronized with upstream; do not develop directly on it.

## Repository ownership

| Repository | Owns |
|---|---|
| `OpenStrap/protocol` | Bytes, GATT, framing, opcodes, and record decoding |
| `OpenStrap/analytics` | Metrics and sleep, readiness, HRV, respiratory, and strain algorithms |
| `OpenStrap/edge` | Storage, orchestration, BLE flows, and UI |

Put a change in the repository that owns the behavior. `edge` may integrate and
present analytics results, but scoring and metric logic belongs in
`OpenStrap/analytics`.

## Data and secrets

Personal and raw data must never be committed. Do not add secrets, exports,
database dumps, personal identifiers, or real raw fixtures to Git. Tests may
use synthetic fixtures or anonymized and date-shifted fixtures only. Keep
personal WHOOP data used for local reproduction or holdout validation outside
the repository and outside Git.
