# Changelog

All notable changes to Claude Context Meter are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

Tagged in git but not previously published as a GitHub Release.

## [1.1.0]

See GitHub Releases.

## [1.0.0]

Initial release.
