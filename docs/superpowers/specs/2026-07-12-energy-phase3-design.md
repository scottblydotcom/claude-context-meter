# Energy Phase 3 Design

**Date:** 2026-07-12
**Status:** Approved

## Problem

During active Claude Code sessions, Activity Monitor still shows very high sustained energy impact for ClaudeContextMeter (hundreds to low-thousands of points, spiking roughly every 5–10 seconds), making the app effectively unusable on battery while Claude is actively being used.

[Energy Phase 2](2026-06-06-energy-phase2-design.md) (PR #8) fixed *where* and *how often* refresh work happens: it moved I/O off the main thread, merged three separate directory scans into one shared scan per refresh, reduced FSEvents callback volume to per-directory-batch, and added a 5-second inter-refresh cooldown.

Phase 2 never addressed *how much work* each refresh does. Root cause, confirmed by tracing the current code:

1. `FileWatcher` watches `~/.claude/projects`, which includes the transcript file of whichever Claude Code session is currently active — including the one editing this app. Every append to that file fires an FSEvent.
2. `RefreshCoordinator`'s 5-second cooldown (`Services/RefreshCoordinator.swift:22`) caps how often a refresh *runs*, but every refresh that does run performs a **full recursive directory scan** (`JSONLParser.scanAllFiles`) and then **fully re-reads and re-JSON-decodes every file in the current windows** — every file modified in the last 11 hours for billing, and every file modified in the current weekly window (up to 7 days) for weekly usage — via `JSONLParser.parse(fileURL:)`, which loads the whole file into a `String` and decodes it line-by-line from scratch.
3. There is no caching: a file that hasn't changed since the previous refresh is re-read and re-decoded anyway. A file that appears in both the billing and weekly windows (common, since 11h ⊂ 7d) is parsed **twice per refresh** — once inside `BillingWindowCalculator.calculate(files:)`, once inside `WeeklyUsageCalculator.calculate(files:)`.

Net effect: while any Claude session is active, the app repeats "re-read and re-decode every recent session file" every 5 seconds indefinitely. Cost scales with total bytes across the billing/weekly windows, not with what actually changed — which is normally just the one live-growing file.

## Goals

1. Never re-parse a file whose contents haven't changed since the last refresh.
2. Parse each file at most once per refresh cycle, even if it's needed by more than one calculator.
3. Keep cached memory bounded to files currently inside the billing/weekly windows — don't accumulate stale entries forever.
4. Preserve all existing calculator behavior and public `calculate()` entry points used by existing tests.

## Non-Goals

- Changing the 5-second cooldown or FSEvents debounce (Phase 2 territory, not being revisited).
- Incremental/tail-only reads of the single actively-growing file (would help further, but mtime+size caching already removes ~all cost for every file *except* that one file, which gets fully re-read once per refresh regardless — that remaining cost is small: one file, not the whole window).

## Architecture

A new `JSONLParseCache` sits between `RefreshCoordinator` and `JSONLParser.parse(fileURL:)`. `RefreshCoordinator` owns one cache instance for the app's lifetime. On each refresh, instead of each calculator independently parsing its own file list, `RefreshCoordinator` resolves the *union* of files needed across all three calculators through the cache once, then hands each calculator pre-parsed `[SessionRecord]` instead of file URLs.

```
RefreshCoordinator.refresh()
  → scan = JSONLParser.scanAllFiles(relativeTo: now)          [unchanged]
  → relevantFiles = billingFiles ∪ weeklyFiles ∪ {mostRecent}
  → cache.prune(keeping: relevantFiles)                        [evict out-of-window entries]
  → for each url in relevantFiles: cache.records(for: url)     [parse only if changed]
  → ContextWindowCalculator.calculate(mostRecentFile:records:)
  → BillingWindowCalculator.calculate(records:)
  → WeeklyUsageCalculator.calculate(records:)
```

`RefreshCoordinator` is already an `actor`, so `JSONLParseCache` needs no locking of its own — it's a plain class whose mutable state is only ever touched from within the actor's isolation domain.

## Components

### JSONLParseCache (new)

`final class JSONLParseCache` in `Services/JSONLParseCache.swift`.

```swift
final class JSONLParseCache {
    private struct Entry {
        let modificationDate: Date
        let size: Int
        let records: [SessionRecord]
    }

    private var cache: [URL: Entry] = [:]
    private let parse: (URL) throws -> [SessionRecord]

    init(parse: @escaping (URL) throws -> [SessionRecord] = JSONLParser.parse) {
        self.parse = parse
    }

    /// Returns parsed records for `url`, reusing the cached result when the file's
    /// modification date and size are unchanged since the last call. Files are read
    /// via `parse` only on a cache miss (first sight of the file, or a changed
    /// mtime/size).
    func records(for url: URL) -> [SessionRecord] {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mdate = values?.contentModificationDate ?? .distantPast
        let size  = values?.fileSize ?? -1

        if let entry = cache[url], entry.modificationDate == mdate, entry.size == size {
            return entry.records
        }

        guard let parsed = try? parse(url) else { return [] }
        cache[url] = Entry(modificationDate: mdate, size: size, records: parsed)
        return parsed
    }

    /// Drops cached entries for files no longer inside any current window, so memory
    /// stays bounded to what's actually being displayed rather than growing across
    /// the app's lifetime.
    func prune(keeping validURLs: Set<URL>) {
        cache = cache.filter { validURLs.contains($0.key) }
    }
}
```

**mtime+size, not a content hash.** Claude session JSONL files are append-only — they only grow. A same-second rewrite that produces an identical size is not a real scenario for this file type, so mtime+size is a safe, cheap heuristic here. A cryptographic hash would require reading the whole file to compute, which defeats the point of the cache.

**Injectable `parse` closure.** Lets tests assert exact call counts (cache hit vs. miss) without depending on filesystem mtime resolution/timing.

### Calculator changes

Each calculator gains a `records:`-based entry point that does no file I/O. The existing `files:`-based entry points become thin wrappers (parse-then-delegate), preserving current behavior and all existing tests unmodified.

| Calculator | New signature | Existing signature (now a wrapper) |
|---|---|---|
| `ContextWindowCalculator` | `calculate(mostRecentFile: URL?, records: [SessionRecord]) -> ContextWindowMetrics?` | `calculate(mostRecentFile: URL?) -> ContextWindowMetrics?` |
| `BillingWindowCalculator` | `calculate(records: [SessionRecord]) -> BillingWindowMetrics` | `calculate(files: [URL]) -> BillingWindowMetrics` |
| `WeeklyUsageCalculator` | `calculate(records: [SessionRecord]) -> WeeklyUsageMetrics` | `calculate(files: [URL]) -> WeeklyUsageMetrics` |

Each `records:`-based method is exactly the body of the current `files:`-based method, minus the `for url in files { JSONLParser.parse(fileURL: url) }` loop — it operates directly on the flattened records passed in.

### RefreshCoordinator changes

```swift
actor RefreshCoordinator {
    private var lastRefreshDate: Date = .distantPast
    private let parseCache = JSONLParseCache()
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 5) {
        self.minimumInterval = minimumInterval
    }

    func refresh() async -> RefreshResult? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else { return nil }
        lastRefreshDate = now

        let scan = JSONLParser.scanAllFiles(relativeTo: now)

        var relevantFiles = Set(scan.billingFiles).union(scan.weeklyFiles)
        if let mostRecent = scan.mostRecent { relevantFiles.insert(mostRecent) }
        parseCache.prune(keeping: relevantFiles)

        var recordsByFile: [URL: [SessionRecord]] = [:]
        for url in relevantFiles {
            recordsByFile[url] = parseCache.records(for: url)
        }

        let billingRecords = scan.billingFiles.flatMap { recordsByFile[$0] ?? [] }
        let weeklyRecords  = scan.weeklyFiles.flatMap { recordsByFile[$0] ?? [] }
        let mostRecentRecords = scan.mostRecent.flatMap { recordsByFile[$0] } ?? []

        let context = ContextWindowCalculator.calculate(mostRecentFile: scan.mostRecent, records: mostRecentRecords)
        let billing = BillingWindowCalculator.calculate(records: billingRecords)
        let weekly  = WeeklyUsageCalculator.calculate(records: weeklyRecords)

        return RefreshResult(context: context, billing: billing, weekly: weekly)
    }
}
```

For testability, `parseCache` is exposed as `internal` (not `private`) so `@testable import` tests can construct a `RefreshCoordinator`-adjacent `JSONLParseCache` directly and assert hit/miss counts — the coordinator itself doesn't need a test-only initializer since `JSONLParseCache` is unit-tested independently.

## Data Flow

```
FSEvent fires (directory-level, unchanged from Phase 2)
  → MetricsViewModel.refresh() → Task { await coordinator.refresh() }
      → cooldown check (skip if < 5s since last) [unchanged]
      → JSONLParser.scanAllFiles()  [one scan, unchanged]
      → prune cache to current window's files
      → for each relevant file: cache.records(for:) — parses ONLY changed files
      → three calculators run on pre-parsed records, no file I/O
  → @MainActor: assign context/billing/weekly
  → SwiftUI re-renders
```

Steady state during an active session: one file (the live transcript) changes per refresh → one cache miss → one file read+decode. Every other file in the 11h/7d windows is a cache hit: one `resourceValues` stat call, no read, no decode.

## Error Handling

Unchanged. A parse failure on cache miss returns `[]` for that file (matching current `try?` swallow behavior) and the entry is **not** cached, so the next refresh retries rather than permanently treating a transient read error as "empty file forever."

## Testing

**Existing tests:** All current calculator/coordinator/parser tests keep passing unmodified — the `files:`/no-arg entry points are preserved as wrappers with identical behavior.

**New tests (`JSONLParseCacheTests` in `ClaudeContextMeterTests.swift`):**
- First call for a URL invokes the injected `parse` closure once and returns its result.
- Second call for the same unchanged file (same mtime + size) does **not** invoke `parse` again; returns the previously cached records.
- Changing the file's modification date (via `setAttributes(.modificationDate:)`, same pattern as `testScanAllFilesMostRecentExcludesSubagents`) causes the next call to invoke `parse` again and return the new result.
- Changing the file's size (rewrite with different content, same mtime forced) causes the next call to invoke `parse` again.
- `prune(keeping:)` removes an entry for a URL not in the kept set; the next `records(for:)` call for that URL is treated as a fresh miss (invokes `parse` again) even if the file itself hasn't changed.
- A `parse` closure that throws returns `[]` and does not poison the cache — a subsequent call (with the closure now succeeding) invokes `parse` again rather than returning a cached empty result.

**New tests (calculator `records:` entry points):**
- `BillingWindowCalculator.calculate(records:)` with a hand-built `[SessionRecord]` array produces the same `BillingWindowMetrics` as `calculate(files:)` given the equivalent file contents (mirrors the existing `testBillingCalculateFilesMatchesCalculateNoArg` pattern).
- Same pairing for `WeeklyUsageCalculator` and `ContextWindowCalculator`.

## Files Changed

| File | Change |
|---|---|
| `Services/JSONLParseCache.swift` | New |
| `Services/RefreshCoordinator.swift` | Own a `JSONLParseCache`; resolve records once per relevant file; pass records (not file lists) to calculators |
| `Services/BillingWindowCalculator.swift` | Add `calculate(records:)`; `calculate(files:)` becomes a wrapper |
| `Services/WeeklyUsageCalculator.swift` | Add `calculate(records:)`; `calculate(files:)` becomes a wrapper |
| `Services/ContextWindowCalculator.swift` | Add `calculate(mostRecentFile:records:)`; `calculate(mostRecentFile:)` becomes a wrapper |
| `ClaudeContextMeterTests/ClaudeContextMeterTests.swift` | Add `JSONLParseCacheTests` cases + `records:` entry-point parity tests |
