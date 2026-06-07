# Energy Phase 2 Design

**Date:** 2026-06-06
**Status:** Approved

## Problem

During active Claude Code sessions, the app exhibits 3000–4000% energy usage in Activity Monitor and a spinning pinwheel on popover click. Root cause: `refresh()` runs three calculators synchronously on the main thread, each doing a separate `FileManager.enumerator` scan and file I/O, triggered up to once per second by `kFSEventStreamCreateFlagFileEvents`.

Phase 1 (PR #4) fixed the file-count problem in `BillingWindowCalculator` by adding a modification-date filter. Phase 2 fixes the remaining causes: main-thread I/O, per-file FSEvents volume, redundant directory scans, and insufficient debouncing.

## Goals

1. Move all refresh I/O off the main thread
2. Reduce FSEvents callback volume from per-file to per-directory-batch
3. Share one directory enumeration across all three calculators per refresh
4. Add a 5-second inter-refresh cooldown
5. Increase heartbeat from 30s to 60s

## Architecture

A new `RefreshCoordinator` actor sits between file change triggers and `MetricsViewModel`. The ViewModel's `refresh()` spawns a `Task` to `await coordinator.refresh()`, which runs entirely off the main thread. The coordinator returns all three metrics as a tuple; the ViewModel assigns them on `@MainActor`.

```
FileWatcher ──┐
              ├──▶ MetricsViewModel.refresh()
heartbeat ────┘         │
                        └──▶ Task { await coordinator.refresh() }
                                        │
                                        ▼
                              RefreshCoordinator (actor)
                              ├─ 5s cooldown gate
                              ├─ JSONLParser.scanAllFiles(relativeTo:)  [one scan]
                              ├─ ContextWindowCalculator.calculate(mostRecentFile:)
                              ├─ BillingWindowCalculator.calculate(files:)
                              └─ WeeklyUsageCalculator.calculate(files:)
                                        │
                                   returns tuple
                                        │
                              ViewModel assigns on @MainActor
```

## Components

### RefreshCoordinator (new)

`actor RefreshCoordinator` in `Services/RefreshCoordinator.swift`.

- Tracks `lastRefreshDate: Date` (initially `.distantPast`)
- `refresh() async -> (ContextWindowMetrics?, BillingWindowMetrics, WeeklyUsageMetrics)`:
  - If `Date().timeIntervalSince(lastRefreshDate) < 5`, return without scanning (no-op)
  - Otherwise: call `JSONLParser.scanAllFiles(relativeTo: now)`, pass derived lists to each calculator, update `lastRefreshDate`, return tuple

### JSONLParser.scanAllFiles (new method)

`static func scanAllFiles(relativeTo now: Date) -> (mostRecent: URL?, billingFiles: [URL], weeklyFiles: [URL])`

One `FileManager.enumerator` pass. From the collected `(url, modificationDate)` pairs, derives:

- `mostRecent` — non-subagent `.jsonl` file with latest modification date
- `billingFiles` — files modified since `now - 11h` (10h lookback + 1h clock-drift buffer)
- `weeklyFiles` — files modified since `WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)`

Existing `allSessionFiles(modifiedSince:)` and `mostRecentSessionFile()` are unchanged.

### Calculator new entry points

Each calculator gets a new static method accepting a pre-built file list. The existing no-arg `calculate()` methods become thin wrappers that call `JSONLParser` then delegate to the new entry point — all 43 existing tests continue to pass without modification.

| Calculator | New signature |
|---|---|
| `ContextWindowCalculator` | `calculate(mostRecentFile: URL?) -> ContextWindowMetrics?` |
| `BillingWindowCalculator` | `calculate(files: [URL]) -> BillingWindowMetrics` |
| `WeeklyUsageCalculator` | `calculate(files: [URL]) -> WeeklyUsageMetrics` |

### FileWatcher changes

Remove `kFSEventStreamCreateFlagFileEvents` from the FSEventStream flags. Use `kFSEventStreamCreateFlagUseCFTypes` only. Directory-level events fire once per write batch rather than once per file written, reducing callback volume significantly during active sessions.

### MetricsViewModel changes

- Add `private let coordinator = RefreshCoordinator()`
- `refresh()` becomes: `Task { let (ctx, b, w) = await coordinator.refresh(); self.context = ctx; self.billing = b; self.weekly = w }`
- Heartbeat interval: `30` → `60` seconds

## Data Flow

```
FSEvent fires (directory-level)
  → DispatchQueue.main.async { onChanged() }
  → MetricsViewModel.refresh()
  → Task { await coordinator.refresh() }
      → cooldown check (skip if < 5s since last)
      → JSONLParser.scanAllFiles()  [background thread, one scan]
      → three calculators in sequence [background thread]
      → return (ctx, billing, weekly)
  → @MainActor: self.context = ctx; self.billing = b; self.weekly = w
  → SwiftUI re-renders
```

## Error Handling

No changes to error handling. Calculators already return safe defaults (empty metrics) when no files are found or parsing fails. The coordinator propagates whatever the calculators return.

## Testing

**Existing tests (43):** All pass without modification. The no-arg `calculate()` wrappers preserve existing behaviour exactly.

**New tests:**
- `RefreshCoordinatorTests`:
  - Verify a second `refresh()` call within 5s returns without triggering a scan (mock `JSONLParser` or check `lastRefreshDate`)
  - Verify a call after 5s does scan
- `JSONLParserTests` (new cases):
  - `scanAllFiles` returns correct `mostRecent` (non-subagent, latest mdate)
  - `scanAllFiles` correctly partitions `billingFiles` vs `weeklyFiles` by date
  - `scanAllFiles` on empty directory returns three empty/nil results

## Files Changed

| File | Change |
|---|---|
| `Services/RefreshCoordinator.swift` | New |
| `Services/JSONLParser.swift` | Add `scanAllFiles(relativeTo:)` |
| `Services/ContextWindowCalculator.swift` | Add `calculate(mostRecentFile:)`; wrap existing `calculate()` |
| `Services/BillingWindowCalculator.swift` | Add `calculate(files:)`; wrap existing `calculate()` |
| `Services/WeeklyUsageCalculator.swift` | Add `calculate(files:)`; wrap existing `calculate()` |
| `Services/FileWatcher.swift` | Remove `kFSEventStreamCreateFlagFileEvents` |
| `ViewModels/MetricsViewModel.swift` | Use coordinator; heartbeat 30s → 60s |
| `Tests/RefreshCoordinatorTests.swift` | New |
| `Tests/JSONLParserTests.swift` | Add `scanAllFiles` cases |
