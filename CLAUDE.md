# CLAUDE.md — Claude Context Meter

Instructions for AI assistants (Claude, Gemini) working on this repo.

## Security Gate (every change)

Run `./scripts/scan.sh` before every commit. All three tools must pass:
- Gitleaks — secret detection
- Semgrep — static analysis
- Trivy — dependency vulnerability scan

The pre-commit hook runs Gitleaks automatically as a backstop.

## CI Pipeline Order

Gitleaks runs first. Semgrep, Trivy, and SwiftLint will not start until Gitleaks passes. No tokens or keys may ever reach the repo.

## PR Review Checklist (CSSLP Audit)

When reviewing a pull request, act as a CSSLP auditor and check all of the following:

1. **File I/O paths** — The app reads `~/.claude/projects/` (intentionally unsandboxed). Flag any writes to paths outside the user's home directory or any hardcoded absolute paths.
2. **No secrets in logs** — Reject any code that logs billing amounts, token counts, or file contents to syslog, os_log, or print statements at non-debug levels.
3. **Billing window edge cases** — Verify that the 5-hour window anchor logic handles: system clock changes, power sleep/wake cycles, daylight saving transitions, and leap seconds.
4. **Integer safety** — Check token math for integer overflow. Token counts can reach tens of millions; use Int64 or guard against overflow.
5. **Non-standard crypto** — Flag any custom hashing, encoding, or encryption. Use system APIs only.

## Hardened Runtime (Xcode 26.4)

Hardened Runtime is required for Apple notarization and is independent of App Sandbox.

**Status: already enabled.** Hardened Runtime is active in Signing & Capabilities with all exceptions unchecked — correct for this app.

The section has two sub-groups:
- **Runtime Exceptions** — relaxations for JIT, unsigned memory, library validation (leave all off for this app)
- **Resource Access** — TCC entitlements for camera, mic, location, etc. (leave all off for this app)

This app reads files from `~/.claude/` via Foundation APIs (String, FileManager) and FSEvents. No Hardened Runtime entitlements are needed for file system access — those restrictions belong to App Sandbox, not Hardened Runtime. Enable the capability as-is with no boxes checked.

**Note:** Xcode 26 also introduces a separate "Enhanced Security" capability (new in 2026, opt-in, adds pointer authentication and memory integrity enforcement). It is not the same as Hardened Runtime and is not required for this app.

## Architecture Notes

- No App Sandbox (required to read `~/.claude/projects/` — sandboxed apps cannot access arbitrary home directory paths)
- No network calls, no API keys, no remote data
- Reads JSONL files via FSEvents + 30s heartbeat timer fallback
- Deduplicates by `requestId`; sums output_tokens from all complete assistant records
- Bundle ID: `com.scottbly.ClaudeContextMeter`


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
