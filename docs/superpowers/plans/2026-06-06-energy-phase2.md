# Energy Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all JSONL refresh I/O off the main thread, share one directory scan across all three calculators, add a 5-second inter-refresh cooldown, drop per-file FSEvents, and bump the heartbeat to 60s — eliminating the 3000–4000% energy usage seen in Activity Monitor during active Claude Code sessions.

**Architecture:** A new `RefreshCoordinator` actor handles all I/O off the main thread. It calls one `JSONLParser.scanAllFiles(relativeTo:)` per refresh, derives three file lists, passes each to the appropriate calculator, and returns all three metrics as an optional tuple (`nil` = debounced). `MetricsViewModel.refresh()` becomes `Task { guard let r = await coordinator.refresh() else { return }; self.x = r.x ... }`. FSEvents switches to directory-level events; the 5-second cooldown lives in the coordinator.

**Tech Stack:** Swift 6, SwiftUI, XCTest, FSEvents (CoreServices), Swift Actors

**Test command (run from repo root):**
```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED|error:"
```

---

### Task 1: `JSONLParser.scanAllFiles` — tests then implementation

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/JSONLParser.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write failing tests**

Add this `// MARK: - JSONLParser.scanAllFiles` section at the bottom of `ClaudeContextMeterTests.swift` (before the final `}`):

```swift
// MARK: - JSONLParser.scanAllFiles

func testScanAllFilesOnEmptyDirectoryReturnsNilAndEmpty() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("scan_empty_\(Int.random(in: 0..<Int.max))")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
    XCTAssertNil(result.mostRecent)
    XCTAssertTrue(result.billingFiles.isEmpty)
    XCTAssertTrue(result.weeklyFiles.isEmpty)
}

func testScanAllFilesIgnoresNonJsonlFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("scan_nojsonl_\(Int.random(in: 0..<Int.max))")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let txtFile = tempDir.appendingPathComponent("session.txt")
    try "data".write(to: txtFile, atomically: true, encoding: .utf8)

    let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
    XCTAssertNil(result.mostRecent)
    XCTAssertTrue(result.billingFiles.isEmpty)
}

func testScanAllFilesMostRecentExcludesSubagents() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("scan_subagent_\(Int.random(in: 0..<Int.max))")
    let subagentDir = tempDir.appendingPathComponent("subagents")
    try FileManager.default.createDirectory(at: subagentDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let mainFile = tempDir.appendingPathComponent("main.jsonl")
    let subagentFile = subagentDir.appendingPathComponent("sub.jsonl")
    try "{}".write(to: mainFile, atomically: true, encoding: .utf8)
    try "{}".write(to: subagentFile, atomically: true, encoding: .utf8)

    // Make subagent file appear newer
    let future = Date().addingTimeInterval(3600)
    try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: subagentFile.path)

    let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
    XCTAssertEqual(result.mostRecent?.lastPathComponent, "main.jsonl",
                   "mostRecent must never be a file inside a subagents/ directory")
}

func testScanAllFilesBillingCutoffIs11Hours() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("scan_billing_\(Int.random(in: 0..<Int.max))")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let now = Date()
    let recent = tempDir.appendingPathComponent("recent.jsonl")  // -10h: inside billing window
    let old    = tempDir.appendingPathComponent("old.jsonl")     // -12h: outside billing window
    try "{}".write(to: recent, atomically: true, encoding: .utf8)
    try "{}".write(to: old,    atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 3600)],
                                          ofItemAtPath: recent.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-12 * 3600)],
                                          ofItemAtPath: old.path)

    let result = JSONLParser.scanAllFiles(relativeTo: now, projectsDir: tempDir)
    XCTAssertTrue(result.billingFiles.contains(recent),
                  "File modified 10h ago should be inside the 11h billing window")
    XCTAssertFalse(result.billingFiles.contains(old),
                   "File modified 12h ago should be outside the 11h billing window")
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|failed"
```

Expected: compile error — `scanAllFiles(relativeTo:projectsDir:)` not found.

- [ ] **Step 3: Implement `scanAllFiles` in `JSONLParser.swift`**

Add this method to the `JSONLParser` enum, after `mostRecentSessionFile()`:

```swift
/// Single-pass scan: derives mostRecent, billingFiles, and weeklyFiles from one
/// FileManager enumeration. Pass `projectsDir` in tests to target a temp directory.
static func scanAllFiles(
    relativeTo now: Date,
    projectsDir: URL? = nil
) -> (mostRecent: URL?, billingFiles: [URL], weeklyFiles: [URL]) {
    let dir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    guard let enumerator = FileManager.default.enumerator(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return (nil, [], []) }

    let billingCutoff = now.addingTimeInterval(-11 * 3600)
    let weeklyCutoff  = WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)

    var mostRecent: (url: URL, date: Date)?
    var billingFiles: [URL] = []
    var weeklyFiles: [URL]  = []

    for case let url as URL in enumerator {
        guard url.pathExtension == "jsonl" else { continue }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let mdate  = values?.contentModificationDate ?? .distantPast

        if mdate >= billingCutoff { billingFiles.append(url) }
        if mdate >= weeklyCutoff  { weeklyFiles.append(url) }

        if !url.path.contains("/subagents/") {
            if mostRecent == nil || mdate > mostRecent!.date {
                mostRecent = (url, mdate)
            }
        }
    }

    return (mostRecent?.url, billingFiles, weeklyFiles)
}
```

- [ ] **Step 4: Run tests — all 4 new tests plus existing 43 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

Expected: `Test Suite 'ClaudeContextMeterTests' passed` with 47 tests.

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/JSONLParser.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add JSONLParser.scanAllFiles — single-pass directory scan"
```

---

### Task 2: `BillingWindowCalculator.calculate(files:)`

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/BillingWindowCalculator.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write a failing test**

Add to the `// MARK: - BillingWindowCalculator rolling window math` section in `ClaudeContextMeterTests.swift`:

```swift
func testBillingCalculateFilesEmptyReturnsZeroTokens() throws {
    // Passing an empty file list returns the zero-token default metrics.
    let result = BillingWindowCalculator.calculate(files: [])
    XCTAssertEqual(result.outputTokens, 0)
}

func testBillingCalculateFilesMatchesCalculateNoArg() throws {
    // calculate(files:) with the same file list that calculate() uses must produce
    // the same output tokens (within 1 token rounding tolerance).
    let now = Date()
    let lookback = now.addingTimeInterval(-10 * 3600)
    let files = JSONLParser.allSessionFiles(modifiedSince: lookback.addingTimeInterval(-3600))
    let fromFiles = BillingWindowCalculator.calculate(files: files)
    let fromNoArg = BillingWindowCalculator.calculate()
    XCTAssertEqual(fromFiles.outputTokens, fromNoArg.outputTokens)
    XCTAssertEqual(fromFiles.tokenLimit,   fromNoArg.tokenLimit)
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|failed"
```

Expected: compile error — `calculate(files:)` not found.

- [ ] **Step 3: Implement `calculate(files:)` and update `calculate()`**

Replace the entire contents of `BillingWindowCalculator.calculate()` in `BillingWindowCalculator.swift` with two methods. The existing method becomes a thin wrapper; all logic moves to the new `calculate(files:)`:

```swift
/// Core calculation: accepts a pre-built file list (avoids redundant directory scans
/// when called from RefreshCoordinator).
static func calculate(files: [URL]) -> BillingWindowMetrics {
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let lookback = now.addingTimeInterval(-10 * 3600)

    var earliestTimestamp: [String: Date] = [:]
    var outputTokensByRequestId: [String: Int64] = [:]

    for url in files {
        guard let parsed = try? JSONLParser.parse(fileURL: url) else { continue }
        for record in parsed {
            guard record.type == "assistant" || record.type == "user",
                  let rid = record.requestId,
                  let timestamp = formatter.date(from: record.timestamp),
                  timestamp >= lookback
            else { continue }

            if let existing = earliestTimestamp[rid] {
                if timestamp < existing { earliestTimestamp[rid] = timestamp }
            } else {
                earliestTimestamp[rid] = timestamp
            }

            if record.isCompleteAssistantRecord,
               let outputTokens = record.message?.usage?.outputTokens {
                outputTokensByRequestId[rid] = outputTokens
            }
        }
    }

    var records: [(timestamp: Date, outputTokens: Int64)] = []
    for (rid, outputTokens) in outputTokensByRequestId {
        guard let timestamp = earliestTimestamp[rid] else { continue }
        records.append((timestamp: timestamp, outputTokens: outputTokens))
    }
    records.sort { $0.timestamp < $1.timestamp }

    let timestamps = records.map { $0.timestamp }
    guard let windowStart = findWindowStart(from: timestamps, relativeTo: now) else {
        return BillingWindowMetrics(outputTokens: 0, tokenLimit: tokenLimit,
                                    windowStart: now, nextReset: now.addingTimeInterval(windowDuration))
    }

    let nextReset = windowStart.addingTimeInterval(windowDuration)
    let totalOutputTokens: Int64 = records
        .filter { $0.timestamp >= windowStart }
        .reduce(0) { $0 + $1.outputTokens }

    return BillingWindowMetrics(
        outputTokens: totalOutputTokens,
        tokenLimit: tokenLimit,
        windowStart: windowStart,
        nextReset: nextReset
    )
}

/// Convenience wrapper: scans files using the standard 11h lookback, then delegates
/// to calculate(files:). Use calculate(files:) directly from RefreshCoordinator.
///
/// IMPORTANT: if you widen/narrow the lookback interval here, update the record-level
/// `timestamp >= lookback` guard inside calculate(files:) together — they must stay in sync.
static func calculate() -> BillingWindowMetrics {
    let now = Date()
    let lookback = now.addingTimeInterval(-10 * 3600)
    let fileModifiedSince = lookback.addingTimeInterval(-1 * 3600)
    return calculate(files: JSONLParser.allSessionFiles(modifiedSince: fileModifiedSince))
}
```

Note: delete the old `calculate()` body entirely and replace with these two methods. The old body content is now inside `calculate(files:)`.

- [ ] **Step 4: Run tests — 49 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/BillingWindowCalculator.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add BillingWindowCalculator.calculate(files:)"
```

---

### Task 3: `WeeklyUsageCalculator.calculate(files:)`

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/WeeklyUsageCalculator.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write failing tests**

Add to the `// MARK: - WeeklyUsageCalculator window start` section in `ClaudeContextMeterTests.swift`:

```swift
func testWeeklyCalculateFilesEmptyReturnsZeroTokens() {
    let result = WeeklyUsageCalculator.calculate(files: [])
    XCTAssertEqual(result.allTokens, 0)
    XCTAssertEqual(result.noCacheRead, 0)
    XCTAssertEqual(result.inputOutputOnly, 0)
}

func testWeeklyCalculateFilesMatchesCalculateNoArg() {
    let windowStart = WeeklyUsageCalculator.findWeeklyWindowStart()
    let files = JSONLParser.allSessionFiles(modifiedSince: windowStart)
    let fromFiles = WeeklyUsageCalculator.calculate(files: files)
    let fromNoArg = WeeklyUsageCalculator.calculate()
    XCTAssertEqual(fromFiles.allTokens,      fromNoArg.allTokens)
    XCTAssertEqual(fromFiles.noCacheRead,    fromNoArg.noCacheRead)
    XCTAssertEqual(fromFiles.inputOutputOnly, fromNoArg.inputOutputOnly)
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|failed"
```

- [ ] **Step 3: Implement `calculate(files:)` and update `calculate()`**

Replace the existing `calculate()` body in `WeeklyUsageCalculator.swift` with two methods:

```swift
/// Core calculation: accepts a pre-built file list.
static func calculate(files: [URL]) -> WeeklyUsageMetrics {
    let now         = Date()
    let windowStart = findWeeklyWindowStart(relativeTo: now)
    let nextReset   = Calendar.current.date(byAdding: .day, value: 7, to: windowStart)!

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var byRequest: [String: Tally] = [:]

    for url in files {
        guard let records = try? JSONLParser.parse(fileURL: url) else { continue }
        for record in records {
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId,
                  let timestamp = formatter.date(from: record.timestamp),
                  timestamp >= windowStart, timestamp <= now,
                  let usage = record.message?.usage
            else { continue }

            byRequest[rid] = Tally(
                input: usage.inputTokens,
                cacheCreate: usage.cacheCreationInputTokens ?? 0,
                cacheRead: usage.cacheReadInputTokens ?? 0,
                output: usage.outputTokens
            )
        }
    }

    let totals = accumulateTotals(byRequest.values)
    return WeeklyUsageMetrics(
        allTokens: totals.input + totals.cacheCreate + totals.cacheRead + totals.output,
        noCacheRead: totals.input + totals.cacheCreate + totals.output,
        inputOutputOnly: totals.input + totals.output,
        windowStart: windowStart,
        nextReset: nextReset
    )
}

/// Convenience wrapper: scans files since the current weekly window start.
static func calculate() -> WeeklyUsageMetrics {
    let windowStart = findWeeklyWindowStart()
    let files = JSONLParser.allSessionFiles(modifiedSince: windowStart)
    return calculate(files: files)
}
```

Delete the old `calculate()` body entirely.

- [ ] **Step 4: Run tests — 51 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/WeeklyUsageCalculator.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add WeeklyUsageCalculator.calculate(files:)"
```

---

### Task 4: `ContextWindowCalculator.calculate(mostRecentFile:)`

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/ContextWindowCalculator.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ClaudeContextMeterTests.swift`:

```swift
// MARK: - ContextWindowCalculator.calculate(mostRecentFile:)

func testContextCalculateMostRecentFileNilReturnsNil() {
    let result = ContextWindowCalculator.calculate(mostRecentFile: nil)
    XCTAssertNil(result)
}

func testContextCalculateMostRecentFileMatchesCalculateNoArg() throws {
    // Both entry points, given the same file, must produce the same metrics.
    guard let url = JSONLParser.mostRecentSessionFile() else {
        throw XCTSkip("No session files available — skipping live-file test")
    }
    let fromFile  = ContextWindowCalculator.calculate(mostRecentFile: url)
    let fromNoArg = ContextWindowCalculator.calculate()
    XCTAssertEqual(fromFile?.totalTokens,  fromNoArg?.totalTokens)
    XCTAssertEqual(fromFile?.contextLimit, fromNoArg?.contextLimit)
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|failed"
```

- [ ] **Step 3: Implement `calculate(mostRecentFile:)` and update `calculate()`**

Replace `ContextWindowCalculator.swift` with:

```swift
//
//  ContextWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum ContextWindowCalculator {

    /// Core calculation: accepts the most-recent session file URL (avoids redundant
    /// directory scans when called from RefreshCoordinator).
    static func calculate(mostRecentFile: URL?) -> ContextWindowMetrics? {
        guard let url = mostRecentFile else { return nil }
        guard let records = try? JSONLParser.parse(fileURL: url) else { return nil }

        var seen = Set<String>()
        let complete = records.filter { record in
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId else { return false }
            return seen.insert(rid).inserted
        }

        guard let last = complete.last,
              let usage = last.message?.usage,
              let model = last.message?.model else { return nil }

        guard let sessionId = last.sessionId else {
            let limit = ModelLimits.defaultContextWindow
            return ContextWindowMetrics(
                fileName: url.lastPathComponent,
                model: model,
                totalTokens: usage.totalTokens,
                contextLimit: limit,
                inputTokens: usage.inputTokens,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                outputTokens: usage.outputTokens
            )
        }
        let limit = ModelLimits.contextWindow(
            for: model,
            sessionId: sessionId,
            observedTokens: usage.totalTokens
        )

        return ContextWindowMetrics(
            fileName: url.lastPathComponent,
            model: model,
            totalTokens: usage.totalTokens,
            contextLimit: limit,
            inputTokens: usage.inputTokens,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            outputTokens: usage.outputTokens
        )
    }

    /// Convenience wrapper: finds the most recent session file, then delegates to
    /// calculate(mostRecentFile:).
    static func calculate() -> ContextWindowMetrics? {
        calculate(mostRecentFile: JSONLParser.mostRecentSessionFile())
    }
}
```

- [ ] **Step 4: Run tests — 53 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/ContextWindowCalculator.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add ContextWindowCalculator.calculate(mostRecentFile:)"
```

---

### Task 5: Create `RefreshCoordinator`

**Files:**
- Create: `ClaudeContextMeter/ClaudeContextMeter/Services/RefreshCoordinator.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

> **⚠️ Xcode project step:** After creating `RefreshCoordinator.swift`, open Xcode, right-click the `Services` group in the Project Navigator, choose "Add Files to ClaudeContextMeter…", select `RefreshCoordinator.swift`, ensure "ClaudeContextMeter" target is checked, and click Add. Do this before running tests.

- [ ] **Step 1: Write failing tests**

Add to `ClaudeContextMeterTests.swift`:

```swift
// MARK: - RefreshCoordinator

func testCoordinatorFirstCallReturnsResult() async {
    let coordinator = RefreshCoordinator()
    let result = await coordinator.refresh()
    XCTAssertNotNil(result, "First call should never be debounced")
}

func testCoordinatorImmediateSecondCallIsDebounced() async {
    let coordinator = RefreshCoordinator()
    _ = await coordinator.refresh()           // first call — runs
    let second = await coordinator.refresh()  // immediate second call — debounced
    XCTAssertNil(second, "Call within minimumInterval should return nil (debounced)")
}

func testCoordinatorCallAfterIntervalIsNotDebounced() async throws {
    // Use a near-zero interval so the test doesn't actually sleep 5 seconds.
    let coordinator = RefreshCoordinator(minimumInterval: 0.01)
    _ = await coordinator.refresh()
    try await Task.sleep(nanoseconds: 20_000_000)  // 20ms > 10ms interval
    let second = await coordinator.refresh()
    XCTAssertNotNil(second, "Call after minimumInterval should not be debounced")
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|failed"
```

Expected: compile error — `RefreshCoordinator` not found.

- [ ] **Step 3: Create `Services/RefreshCoordinator.swift`**

Create the file at `ClaudeContextMeter/ClaudeContextMeter/Services/RefreshCoordinator.swift`:

```swift
//
//  RefreshCoordinator.swift
//  ClaudeContextMeter
//

import Foundation

/// Off-main-thread coordinator: performs one directory scan per refresh cycle and
/// passes derived file lists to the three metric calculators. Returns nil when called
/// within `minimumInterval` of the previous refresh (debounced).
actor RefreshCoordinator {

    private var lastRefreshDate: Date = .distantPast
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 5) {
        self.minimumInterval = minimumInterval
    }

    func refresh() async -> (context: ContextWindowMetrics?,
                              billing: BillingWindowMetrics,
                              weekly: WeeklyUsageMetrics)? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else {
            return nil
        }
        lastRefreshDate = now

        let (mostRecent, billingFiles, weeklyFiles) = JSONLParser.scanAllFiles(relativeTo: now)

        let context = ContextWindowCalculator.calculate(mostRecentFile: mostRecent)
        let billing = BillingWindowCalculator.calculate(files: billingFiles)
        let weekly  = WeeklyUsageCalculator.calculate(files: weeklyFiles)

        return (context, billing, weekly)
    }
}
```

- [ ] **Step 4: Add `RefreshCoordinator.swift` to the Xcode project**

In Xcode: right-click the **Services** group → "Add Files to ClaudeContextMeter…" → select `RefreshCoordinator.swift` → confirm "ClaudeContextMeter" target is checked → Add.

- [ ] **Step 5: Run tests — 56 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 6: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/RefreshCoordinator.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift \
        ClaudeContextMeter/ClaudeContextMeter.xcodeproj/project.pbxproj
git commit -m "feat: add RefreshCoordinator actor — off-main-thread I/O + 5s debounce"
```

---

### Task 6: Update `FileWatcher` — directory-level events

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/FileWatcher.swift`

- [ ] **Step 1: Remove `kFSEventStreamCreateFlagFileEvents` from the stream flags**

In `FileWatcher.swift`, change line 46 from:

```swift
FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
```

to:

```swift
FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
```

This switches from per-file events (fires once per JSONL line appended) to directory-level events (fires once per batch of writes to the directory). The 1-second latency coalescing is kept.

- [ ] **Step 2: Build to confirm no compile errors**

```bash
cd ClaudeContextMeter && xcodebuild build \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  2>&1 | grep -E "Build FAILED|error:|warning: 'kFSEventStreamCreateFlagFileEvents'"
```

Expected: `Build SUCCEEDED` with no errors.

- [ ] **Step 3: Run tests — all 56 still pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 4: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/FileWatcher.swift
git commit -m "perf: switch FSEvents to directory-level events (drop kFSEventStreamCreateFlagFileEvents)"
```

---

### Task 7: Update `MetricsViewModel` — use coordinator, heartbeat 60s

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/ViewModels/MetricsViewModel.swift`

- [ ] **Step 1: Replace `MetricsViewModel.swift` with the coordinator-based version**

Replace the entire file contents with:

```swift
//
//  MetricsViewModel.swift
//  ClaudeContextMeter
//

import SwiftUI
import Combine

@MainActor
class MetricsViewModel: ObservableObject {
    @Published var context: ContextWindowMetrics?
    @Published var billing: BillingWindowMetrics?
    @Published var weekly: WeeklyUsageMetrics?

    nonisolated(unsafe) private var fileWatcher: FileWatcher?
    nonisolated(unsafe) private var heartbeat: Timer?
    private let coordinator = RefreshCoordinator()

    init() {
        refresh()
        startWatching()
    }

    func refresh() {
        Task {
            guard let result = await coordinator.refresh() else { return }
            self.context = result.context
            self.billing = result.billing
            self.weekly  = result.weekly
        }
    }

    private func startWatching() {
        let projectsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .path

        fileWatcher = FileWatcher(paths: [projectsPath]) { [weak self] in
            self?.refresh()
        }
        fileWatcher?.start()

        // 60-second heartbeat as failsafe in case FSEvents misses an event.
        // FSEvents handles live updates; this is a backstop only.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }
}
```

- [ ] **Step 2: Run tests — all 56 must pass**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/ViewModels/MetricsViewModel.swift
git commit -m "perf: use RefreshCoordinator in MetricsViewModel; heartbeat 30s → 60s"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run the full test suite one last time**

```bash
cd ClaudeContextMeter && xcodebuild test \
  -project ClaudeContextMeter.xcodeproj \
  -scheme ClaudeContextMeter \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|Build FAILED|error:"
```

Expected: `Test Suite 'ClaudeContextMeterTests' passed` with **56 tests** (43 original + 13 new).

- [ ] **Step 2: Run security scan**

```bash
cd .. && ./scripts/scan.sh
```

Expected: `3 passed, 0 failed`.

- [ ] **Step 3: Update backlog memory**

Mark "Energy Phase 2" as complete in `~/.claude/projects/-Users-scottbly-Git-claude-context-meter/memory/project_backlog.md`. Remove the "UI click latency / spinning pinwheel" item (same fix).
