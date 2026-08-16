# Handy upstream policy

## Provenance

- Upstream repository: `https://github.com/cjpais/Handy.git`
- Pressay baseline: `98a4d80cce8ad41efec2a419b59d9e81229a35d7`
- Baseline tag context: Handy `v0.9.5` plus subsequent `main` fixes
- Last audited upstream commit: `98a4d80cce8ad41efec2a419b59d9e81229a35d7`
- Next review: before the first Pressay 2.0 beta, then monthly

## Remote guarantees

`origin` is the only push destination. `upstream` is fetch-only and its push URL
is intentionally set to `DISABLED`. `remote.pushDefault` must remain `origin`.

## Sync procedure

1. Fetch with `git fetch upstream --prune --tags`.
2. Review the delta from the last audited commit.
3. Classify every candidate as security, stability, feature, or not applicable.
4. Create `codex/sync-handy-YYYY-MM-DD` from `origin/main`.
5. Cherry-pick a small isolated fix or reimplement it against Pressay.
6. Run the local, privacy, paste, audio, and packaging regressions.
7. Merge through a Pressay pull request and update this file.

Do not merge or rebase Pressay `main` directly onto `upstream/main`. Do not stack
unmerged Handy pull-request branches into Pressay.

## Initial watch list

| Upstream item                         | Pressay action                              |
| ------------------------------------- | ------------------------------------------- |
| Handy #1910 toggle parity             | Monitor; port only with state-machine tests |
| Handy #1644 CPAL/macOS crash          | Audit and prioritize                        |
| Handy #1874/#1875 microphone fallback | Reimplement for macOS                       |
| Handy #1890 permission timeout        | Reimplement in Pressay onboarding           |
| Handy #1903 silent audio warning      | Reimplement narrowly                        |
| Handy #1767 Fn passthrough            | Monitor and test on Apple Silicon           |
| Handy #1533 exact replacements        | Reimplement in Pressay dictionary           |
| Handy #1610 selected text             | Reimplement in the mode pipeline            |

## Applied changes

No post-baseline upstream changes have been applied yet.
