# Workstreams

Living manifest of every active branch. A missing row here means a branch may be dangling unprotected.
Update this file in the same commit that creates or closes a branch.

## Active Branches

| Branch | PR | Protective Tag | Notes |
|---|---|---|---|
| main | — | — | Protected default branch |
| fix/billing-window-allsessions | #4 | — | Energy fix: billing window file filter |
| docs/git-governance | #5 | — | This PR — governance runbook + workstreams |

## Closed / Merged Branches
_(moved here when PR reads "Merged")_

| Branch | PR | Notes |
|---|---|---|
| ci/harden-pipeline-add-gemini-config | #1 | Merged 2026-04-08 |
| feature/weekly-gauge | #2 | Merged 2026-04-15 |
| feature/v1.2-reposition | #3 | Merged 2026-05-28 |

## Discipline Rules
1. Open a DRAFT PR the moment a feature branch is first pushed. PRs retain head commits even if the branch is later deleted.
2. Never delete a branch until its PR reads **Merged** (not Closed).
3. Tag reviewed work: `git tag -a reviewed-<topic>-<date> -m "reviewed"` then `git push origin reviewed-<topic>-<date>`.
4. A row disappearing from this table is a tripwire — investigate before merging anything else.
