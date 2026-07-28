# Changelog

All notable changes to Claude Context Meter are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.4.0] - 2026-07-26

### Added
- Support for **Claude Opus 5** (`claude-opus-5`, 1M context), added to the model → context-window
  lookup ([#21](https://github.com/scottblydotcom/claude-context-meter/pull/21))
- **Configurable weekly reset** day and time in Settings, so the Weekly Usage window matches the
  reset shown in Claude's own usage settings (Anthropic doesn't expose the schedule in any readable
  file) ([#22](https://github.com/scottblydotcom/claude-context-meter/pull/22))

### Fixed
- Context-window denominator is now deterministic per (model, input tokens): a 1M-capable model
  sitting below 200k tokens correctly reports the **1M** window instead of 200k (a 178k session now
  reads 18%, not 89%). The safety net compares input-side tokens (excluding generated output), so a
  maxed-out 200k model is never falsely promoted to 1M
  ([#21](https://github.com/scottblydotcom/claude-context-meter/pull/21))
- The menu-bar meter now refreshes when the Settings window closes, so plan, token-limit, and weekly
  reset changes take effect immediately instead of on the next heartbeat
- Running the test suite no longer wipes the user's saved plan / token-limit preferences (tests now
  use an isolated UserDefaults suite) ([#22](https://github.com/scottblydotcom/claude-context-meter/pull/22))

### Internal
- De-flaked the live-file `calculate()` equivalence tests by parsing a frozen snapshot instead of
  comparing two independent scans of a live, actively-written `~/.claude`

## [1.3.0] - 2026-07-21

### Fixed
- Model list now recognizes 1M-context models via a data-driven lookup instead of a single
  hardcoded model name — previously only `claude-opus-4-7` was recognized as 1M-capable, which
  was stale against the current lineup ([#16](https://github.com/scottblydotcom/claude-context-meter/pull/16))
- Settings window now reliably comes to the foreground when reopened, including activating the
  app so it isn't left behind other windows ([#17](https://github.com/scottblydotcom/claude-context-meter/pull/17))
- Settings window attempts to follow the app across macOS Spaces via `.moveToActiveSpace`
  (documented limitation: doesn't reliably jump across an *inactive* Space on click)
  ([#18](https://github.com/scottblydotcom/claude-context-meter/pull/18))
- Single-instance guard no longer produces spurious failures when running under the test host
  ([#12](https://github.com/scottblydotcom/claude-context-meter/pull/12))
- `scan.sh` resolves security tool paths via `PATH` instead of a hardcoded `/usr/local/bin`
  ([#14](https://github.com/scottblydotcom/claude-context-meter/pull/14))

### Performance
- Session files are parsed once per refresh and cached (`JSONLParseCache`), removing redundant
  reparsing — part of the Energy Phase 3 efficiency work
  ([#11](https://github.com/scottblydotcom/claude-context-meter/pull/11))

### Chore
- Added Beads (`bd`) issue tracking and agent tooling configuration
  ([#15](https://github.com/scottblydotcom/claude-context-meter/pull/15))
- Documented that `bd init` (or `bd hooks install --beads`) auto-activates the tracked Gitleaks
  pre-commit hook, verified empirically against a fresh clone
  ([#19](https://github.com/scottblydotcom/claude-context-meter/pull/19))

## [1.2.0] - 2026-05-27

Tagged in git on 2026-05-27 but not published as a GitHub Release until 2026-07-27; the notes below
were reconstructed from the `v1.1.0..v1.2.0` commit range at that time. No binary is attached to the
backfilled release.

### Added
- **Opus 4.7 1M-context detection.** Both Opus 4.7 variants write the same `claude-opus-4-7` string
  to the session JSONL, so the 1M window can't be identified from the model name alone. Detection is
  reactive: once a session's observed tokens exceed 200k, the 1M limit is recorded in the
  `opusSessionLimits` UserDefaults dictionary keyed by session ID, so the denominator survives
  autocompaction. Entries are pruned after 30 days, throttled to once per 24h
  ([#3](https://github.com/scottblydotcom/claude-context-meter/pull/3))

### Changed
- Removed the cost-weighted and peak-adjusted weekly metrics — Anthropic eliminated peak pricing on
  2026-05-06, so both were measuring something that no longer exists
- README repositioned for Claude Code CLI users, documenting what the app can and cannot show
  relative to Anthropic's own native usage meter

### Performance
- JSONL files older than the start of the weekly window are skipped during the scan instead of being
  read and discarded

### Internal
- Session-limit storage consolidated into a single UserDefaults dictionary key rather than one key
  per session, avoiding namespace pollution and a `dictionaryRepresentation()` scan
- Guard against an empty session ID, which would otherwise collide in the limits dictionary

## [1.1.0]

See GitHub Releases.

## [1.0.0]

Initial release.
