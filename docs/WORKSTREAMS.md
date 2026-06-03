# Workstreams

Living manifest of every active branch. A missing row here means a branch may be dangling unprotected.
Update this file in the same commit that creates or closes a branch.

## Active Branches

| Branch | PR | Protective Tag | Notes |
|---|---|---|---|
| main | — | — | Protected default branch |
| feature/weekly-gauge | n/a | — | Open draft PR before next push |
| ci/harden-pipeline-add-gemini-config | n/a | — | Open draft PR before next push |
| feature/v1.2-reposition | n/a | — | Remote-only orphan; verify or prune |

## Closed / Merged Branches
_(moved here when PR reads "Merged")_

## Discipline Rules
1. Open a DRAFT PR the moment a feature branch is first pushed. PRs retain head commits even if the branch is later deleted.
2. Never delete a branch until its PR reads **Merged** (not Closed).
3. Tag reviewed work: `git tag -a reviewed-<topic>-<date> -m "reviewed"` then `git push origin <tag>`.
4. A row disappearing from this table is a tripwire — investigate before merging anything else.
