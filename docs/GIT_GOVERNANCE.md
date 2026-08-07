# Git Governance Runbook

## Branch Model

`main` → `dev` → `feature/*`. All new work targets **`dev`**; `dev` opens a release PR into `main`.
PRs are required at every merge — no local merges.

This was undocumented until 2026-08-07 and drifted silently as a result: PRs #21, #22, #23, #24 and
#25 all went straight to `main`. Two supports keep the model real rather than aspirational:

- **`dev` is a protected branch** (deletion and force-push blocked, no required checks so it stays
  cheap to fast-forward). Protection exists specifically because `delete_branch_on_merge: true`
  deletes `dev` on every `dev`→`main` release merge — that is what removed it after PR #23, and a
  stale remote-tracking ref then made it look like ordinary drift rather than a deleted branch. If
  `dev` ever does go missing, recreate it with `git push origin origin/main:refs/heads/dev` and
  `git fetch --prune`.
- **`.coderabbit.yaml` lists `dev` under `reviews.auto_review.base_branches`.** CodeRabbit only
  auto-reviews the default branch otherwise, so every feature PR was being skipped. PR #24 merged
  with no review at all for this reason.

## Controls in Force

### Branch Protection (main)
- PRs required; no human approval required (solo project — CI is the gate)
- enforce_admins: true — admin cannot bypass
- Required checks: all four security scan jobs must pass
  - Gitleaks — Secret Detection
  - Semgrep — Static Analysis
  - Trivy — Vulnerability Scan
  - SwiftLint — Swift Style & Lint
- allow_force_pushes: false
- allow_deletions: false
- delete_branch_on_merge: true (merge-only — branches deleted on close are NOT auto-deleted)
- strict: true (branch must be up to date with main before merge)

### Off-GitHub Backup
- Nightly non-pruning bare mirror + dated bundle snapshots run on an always-on backup host
- Script: `~/backups/<repo>/backup.sh` (cron: 0 2 * * *)
- Bundles retained 90 days, then swept
- fetch.prune is false — refs deleted on origin are retained in the mirror

## Discipline Rules

1. **Open a draft PR immediately.** The moment you push a feature branch, open a draft PR.
   A PR retains its head commits even if the branch is later deleted. This is the single habit
   that prevents branch loss.

2. **Never delete a branch until PR reads "Merged".** Closed != Merged. A closed PR does NOT
   protect commits. Merged != Closed either — always verify the PR status badge before deletion.

3. **Tag reviewed work.**
   ```
   git tag -a reviewed-<topic>-<YYYY-MM-DD> -m "Reviewed and ready"
   git push origin reviewed-<topic>-<YYYY-MM-DD>
   ```
   Annotated tags are not pruned and survive branch deletion.

4. **Update WORKSTREAMS.md** in the same commit that creates or closes a branch.

## Security Gates (every PR)
- All four required checks must pass — a failing check cannot merge.
- Run `./scripts/scan.sh` locally before pushing to catch issues early.
- GuardDog on dependency changes; gitleaks/ggshield before touching secrets or config.

## Recovery Procedures

### From a PR head (branch deleted but PR exists)
```
git fetch origin refs/pull/<PR-NUMBER>/head:recover/<branch-name>
git checkout recover/<branch-name>
```

### From a milestone tag
```
git fetch origin tag reviewed-<topic>-<date>
git checkout -b recover/<topic> reviewed-<topic>-<date>
```

### From the off-GitHub mirror
```
# Inspect what the mirror has retained (including refs deleted from origin)
git -C ~/backups/<repo>/repo.git log --all --oneline | head -20
git -C ~/backups/<repo>/repo.git branch -a

# Pull a lost branch from the mirror back into your local clone
git fetch ~/backups/<repo>/repo.git refs/heads/<branch>:recover/<branch>
git checkout recover/<branch>
```

### From a bundle snapshot
```
# Inspect available refs in a bundle
git bundle list-heads ~/backups/<repo>/bundles/snap-<stamp>.bundle
# Fetch a specific ref from the bundle
git fetch ~/backups/<repo>/bundles/snap-<stamp>.bundle refs/heads/main:recover/main-from-bundle
git checkout recover/main-from-bundle
```

### From dangling objects (last resort)
```
git fsck --lost-found
# Check .git/lost-found/commit/ for dangling commits
git show <sha>
```
