# Energy Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop ClaudeContextMeter from re-reading and re-JSON-decoding every recent session file on every 5-second refresh; only files that actually changed since the last refresh should be parsed.

**Architecture:** Add a `JSONLParseCache` keyed by `(URL → mtime, size, parsed records)`, owned by `RefreshCoordinator`. Calculators gain `records:`-based entry points that take pre-parsed `[SessionRecord]` instead of file URLs, so parsing happens exactly once per changed file per refresh, shared across all three calculators. See [design spec](../specs/2026-07-12-energy-phase3-design.md) for full rationale.

**Tech Stack:** Swift 6, XCTest, Foundation (`FileManager`, `URL.resourceValues`).

---

### Task 1: JSONLParseCache — cache hit/miss on unchanged/changed files

**Files:**
- Create: `ClaudeContextMeter/ClaudeContextMeter/Services/JSONLParseCache.swift`
- Test: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `ClaudeContextMeterTests.swift`, under a new `// MARK: - JSONLParseCache` section (after the `RefreshCoordinator` section, before the closing brace of `ClaudeContextMeterTests`):

```swift
// MARK: - JSONLParseCache

func testParseCacheFirstCallInvokesParseOnce() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_first_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        return []
    }

    _ = cache.records(for: file)
    XCTAssertEqual(callCount, 1, "First call for a URL must invoke parse exactly once")
}

func testParseCacheUnchangedFileIsNotReparsed() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_unchanged_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        return []
    }

    _ = cache.records(for: file)
    _ = cache.records(for: file)
    XCTAssertEqual(callCount, 1, "Second call for an unchanged file must be a cache hit (no reparse)")
}

func testParseCacheChangedModificationDateReparsesFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_mtime_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        return []
    }

    _ = cache.records(for: file)
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(3600)],
        ofItemAtPath: file.path
    )
    _ = cache.records(for: file)
    XCTAssertEqual(callCount, 2, "A changed modification date must trigger a reparse")
}

func testParseCacheChangedSizeReparsesFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_size_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)
    let fixedDate = Date()
    try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: file.path)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        return []
    }

    _ = cache.records(for: file)
    try "{}\n{}".write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: file.path)
    _ = cache.records(for: file)
    XCTAssertEqual(callCount, 2, "A changed file size (same mtime) must trigger a reparse")
}

func testParseCachePruneEvictsUnkeptURLs() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_prune_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        return []
    }

    _ = cache.records(for: file)
    cache.prune(keeping: [])
    _ = cache.records(for: file)
    XCTAssertEqual(callCount, 2, "Pruning a URL out of the cache must force a reparse on next access")
}

func testParseCacheParseFailureIsNotCached() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache_failure_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)

    var callCount = 0
    let cache = JSONLParseCache { _ in
        callCount += 1
        throw NSError(domain: "test", code: 1)
    }

    let first = cache.records(for: file)
    let second = cache.records(for: file)
    XCTAssertEqual(first, [])
    XCTAssertEqual(second, [])
    XCTAssertEqual(callCount, 2, "A parse failure must not be cached — every call should retry")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests/testParseCacheFirstCallInvokesParseOnce`
Expected: FAIL / build error — `JSONLParseCache` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `ClaudeContextMeter/ClaudeContextMeter/Services/JSONLParseCache.swift`:

```swift
//
//  JSONLParseCache.swift
//  ClaudeContextMeter
//

import Foundation

/// Caches parsed `SessionRecord`s per file, keyed by modification date + size, so
/// unchanged files are not re-read and re-decoded on every refresh cycle. Claude
/// session JSONL files are append-only, so mtime+size is a safe, cheap heuristic —
/// far cheaper than hashing file contents, which would defeat the point of caching.
///
/// Not thread-safe on its own. Intended to be owned by a single actor (RefreshCoordinator)
/// so all access is naturally serialized.
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
    /// modification date and size are unchanged since the last call. On a cache miss
    /// (new file, or changed mtime/size), calls `parse` and caches the result. A parse
    /// failure returns `[]` without caching, so the next call retries.
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

    /// Drops cached entries for URLs not in `validURLs`, so memory stays bounded to
    /// files currently inside the billing/weekly windows instead of growing forever.
    func prune(keeping validURLs: Set<URL>) {
        cache = cache.filter { validURLs.contains($0.key) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests`
Expected: PASS (all `testParseCache*` tests, plus all pre-existing tests still pass)

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/JSONLParseCache.swift ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add JSONLParseCache — skip reparsing unchanged session files"
```

---

### Task 2: BillingWindowCalculator — add records: entry point

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/BillingWindowCalculator.swift:66-96`
- Test: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write the failing test**

Add near `testBillingCalculateFilesMatchesCalculateNoArg` (after it, still inside the billing `// MARK:` section):

```swift
func testBillingCalculateRecordsMatchesCalculateFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("billing_records_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = """
    {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
    """
    try line.write(to: file, atomically: true, encoding: .utf8)

    let viaFiles = BillingWindowCalculator.calculate(files: [file])
    let records = try JSONLParser.parse(fileURL: file)
    let viaRecords = BillingWindowCalculator.calculate(records: records)

    XCTAssertEqual(viaFiles.outputTokens, viaRecords.outputTokens)
    XCTAssertEqual(viaFiles.windowStart, viaRecords.windowStart)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests/testBillingCalculateRecordsMatchesCalculateFiles`
Expected: FAIL — `calculate(records:)` does not exist yet.

- [ ] **Step 3: Write the implementation**

In `Services/BillingWindowCalculator.swift`, replace the existing `calculate(files:)` (lines 64-96) with:

```swift
    /// Core calculation: accepts pre-parsed records (avoids redundant file I/O when
    /// called from RefreshCoordinator, which resolves records once per file across
    /// all three calculators via JSONLParseCache).
    static func calculate(records: [SessionRecord]) -> BillingWindowMetrics {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let lookback = now.addingTimeInterval(-10 * 3600)

        var earliestTimestamp: [String: Date] = [:]
        var outputTokensByRequestId: [String: Int64] = [:]

        for record in records {
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

        var recordsList: [(timestamp: Date, outputTokens: Int64)] = []
        for (rid, outputTokens) in outputTokensByRequestId {
            guard let timestamp = earliestTimestamp[rid] else { continue }
            recordsList.append((timestamp: timestamp, outputTokens: outputTokens))
        }
        recordsList.sort { $0.timestamp < $1.timestamp }

        let timestamps = recordsList.map { $0.timestamp }
        guard let windowStart = findWindowStart(from: timestamps, relativeTo: now) else {
            return BillingWindowMetrics(outputTokens: 0, tokenLimit: tokenLimit,
                                        windowStart: now, nextReset: now.addingTimeInterval(windowDuration))
        }

        let nextReset = windowStart.addingTimeInterval(windowDuration)
        let totalOutputTokens: Int64 = recordsList
            .filter { $0.timestamp >= windowStart }
            .reduce(0) { $0 + $1.outputTokens }

        return BillingWindowMetrics(
            outputTokens: totalOutputTokens,
            tokenLimit: tokenLimit,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }

    /// Convenience wrapper: parses each file, then delegates to calculate(records:).
    /// Prefer calculate(records:) directly when records are already available (e.g.
    /// from RefreshCoordinator's JSONLParseCache) to avoid redundant parsing.
    static func calculate(files: [URL]) -> BillingWindowMetrics {
        let records = files.flatMap { (try? JSONLParser.parse(fileURL: $0)) ?? [] }
        return calculate(records: records)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests`
Expected: PASS (new test + all existing billing tests, e.g. `testBillingCalculateFilesMatchesCalculateNoArg`, `testBillingCalculateFilesEmptyReturnsZeroTokens`)

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/BillingWindowCalculator.swift ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "refactor: BillingWindowCalculator.calculate(records:) — decouple from file I/O"
```

---

### Task 3: WeeklyUsageCalculator — add records: entry point

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/WeeklyUsageCalculator.swift:61-99`
- Test: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write the failing test**

Add near `testWeeklyCalculateFilesMatchesCalculateNoArg`:

```swift
func testWeeklyCalculateRecordsMatchesCalculateFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("weekly_records_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = """
    {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
    """
    try line.write(to: file, atomically: true, encoding: .utf8)

    let viaFiles = WeeklyUsageCalculator.calculate(files: [file])
    let records = try JSONLParser.parse(fileURL: file)
    let viaRecords = WeeklyUsageCalculator.calculate(records: records)

    XCTAssertEqual(viaFiles.allTokens, viaRecords.allTokens)
    XCTAssertEqual(viaFiles.windowStart, viaRecords.windowStart)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests/testWeeklyCalculateRecordsMatchesCalculateFiles`
Expected: FAIL — `calculate(records:)` does not exist yet.

- [ ] **Step 3: Write the implementation**

In `Services/WeeklyUsageCalculator.swift`, replace the existing `calculate(files:)` (lines 61-99) with:

```swift
    /// Core calculation: accepts pre-parsed records (avoids redundant file I/O when
    /// called from RefreshCoordinator, which resolves records once per file across
    /// all three calculators via JSONLParseCache).
    static func calculate(records: [SessionRecord]) -> WeeklyUsageMetrics {
        let now         = Date()
        let windowStart = findWeeklyWindowStart(relativeTo: now)
        let nextReset   = Calendar.current.date(byAdding: .day, value: 7, to: windowStart)!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var byRequest: [String: Tally] = [:]

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

        let totals = accumulateTotals(byRequest.values)
        return WeeklyUsageMetrics(
            allTokens: totals.input + totals.cacheCreate + totals.cacheRead + totals.output,
            noCacheRead: totals.input + totals.cacheCreate + totals.output,
            inputOutputOnly: totals.input + totals.output,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }

    /// Convenience wrapper: parses each file, then delegates to calculate(records:).
    /// Prefer calculate(records:) directly when records are already available (e.g.
    /// from RefreshCoordinator's JSONLParseCache) to avoid redundant parsing.
    static func calculate(files: [URL]) -> WeeklyUsageMetrics {
        let records = files.flatMap { (try? JSONLParser.parse(fileURL: $0)) ?? [] }
        return calculate(records: records)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests`
Expected: PASS (new test + all existing weekly tests, e.g. `testWeeklyCalculateFilesMatchesCalculateNoArg`, `testWeeklyCalculateFilesEmptyReturnsZeroTokens`)

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/WeeklyUsageCalculator.swift ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "refactor: WeeklyUsageCalculator.calculate(records:) — decouple from file I/O"
```

---

### Task 4: ContextWindowCalculator — add records: entry point

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/ContextWindowCalculator.swift:10-57`
- Test: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write the failing test**

Add near `testContextCalculateMostRecentFileMatchesCalculateNoArg`:

```swift
func testContextCalculateRecordsMatchesCalculateMostRecentFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("context_records_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    let line = """
    {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"2026-07-12T10:00:00.000Z","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
    """
    try line.write(to: file, atomically: true, encoding: .utf8)

    let viaFile = ContextWindowCalculator.calculate(mostRecentFile: file)
    let records = try JSONLParser.parse(fileURL: file)
    let viaRecords = ContextWindowCalculator.calculate(mostRecentFile: file, records: records)

    XCTAssertEqual(viaFile?.totalTokens, viaRecords?.totalTokens)
    XCTAssertEqual(viaFile?.model, viaRecords?.model)
}

func testContextCalculateRecordsNilFileReturnsNil() {
    XCTAssertNil(ContextWindowCalculator.calculate(mostRecentFile: nil, records: []))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests/testContextCalculateRecordsMatchesCalculateMostRecentFile`
Expected: FAIL — `calculate(mostRecentFile:records:)` does not exist yet.

- [ ] **Step 3: Write the implementation**

In `Services/ContextWindowCalculator.swift`, replace the existing `calculate(mostRecentFile:)` (lines 10-57) with:

```swift
    /// Core calculation: accepts the most-recent session file URL plus its pre-parsed
    /// records (avoids redundant file I/O when called from RefreshCoordinator, which
    /// resolves records once per file across all three calculators via JSONLParseCache).
    static func calculate(mostRecentFile: URL?, records: [SessionRecord]) -> ContextWindowMetrics? {
        guard let url = mostRecentFile else { return nil }

        var seen = Set<String>()
        let complete = records.filter { record in
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId else { return false }
            return seen.insert(rid).inserted
        }

        guard let last = complete.last,
              let usage = last.message?.usage,
              let model = last.message?.model else { return nil }

        // A nil sessionId means the JSONL record is malformed. Skip 1M detection entirely
        // rather than coalescing to a shared "unknown" key, which would let one 1M session
        // permanently mark all future nil-sessionId Opus 4.7 sessions as 1M.
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

    /// Convenience wrapper: parses mostRecentFile, then delegates to
    /// calculate(mostRecentFile:records:). Prefer the records: overload directly when
    /// records are already available (e.g. from RefreshCoordinator's JSONLParseCache)
    /// to avoid redundant parsing.
    static func calculate(mostRecentFile: URL?) -> ContextWindowMetrics? {
        guard let url = mostRecentFile, let records = try? JSONLParser.parse(fileURL: url) else { return nil }
        return calculate(mostRecentFile: url, records: records)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests`
Expected: PASS (new tests + all existing context tests, e.g. `testContextCalculateMostRecentFileNilReturnsNil`, `testContextCalculateMostRecentFileMatchesCalculateNoArg`)

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/ContextWindowCalculator.swift ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "refactor: ContextWindowCalculator.calculate(records:) — decouple from file I/O"
```

---

### Task 5: RefreshCoordinator — wire up the cache, parse each file once per refresh

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Services/RefreshCoordinator.swift`
- Test: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

- [ ] **Step 1: Write the failing test**

Add near `testCoordinatorCallAfterIntervalIsNotDebounced` (in the `// MARK: - RefreshCoordinator` section):

```swift
func testCoordinatorDoesNotReparseUnchangedFileAcrossRefreshes() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("coord_cache_\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let file = tempDir.appendingPathComponent("session.jsonl")
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = """
    {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
    """
    try line.write(to: file, atomically: true, encoding: .utf8)

    let coordinator = RefreshCoordinator(minimumInterval: 0, projectsDir: tempDir)
    _ = await coordinator.refresh()
    let billingAfterFirst = await coordinator.refresh()

    XCTAssertNotNil(billingAfterFirst, "Second call after interval elapses should not be debounced")
    XCTAssertEqual(billingAfterFirst?.billing.outputTokens, 20,
                   "Unchanged file must still be reflected correctly on a cache-hit refresh")
}
```

This test exercises the integration path end-to-end (it would already pass with the pre-Phase-3 implementation too — cache hits are an internal optimization, not an externally-observable behavior change). Its purpose here is to pin down the new `RefreshCoordinator(minimumInterval:projectsDir:)` initializer added in this task and confirm correctness is unaffected by the caching change.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests/testCoordinatorDoesNotReparseUnchangedFileAcrossRefreshes`
Expected: FAIL — `RefreshCoordinator.init(minimumInterval:projectsDir:)` does not exist yet (current initializer takes only `minimumInterval:`, and `refresh()` always scans `~/.claude/projects`).

- [ ] **Step 3: Write the implementation**

Replace the full contents of `Services/RefreshCoordinator.swift`:

```swift
//
//  RefreshCoordinator.swift
//  ClaudeContextMeter
//

import Foundation

struct RefreshResult {
    let context: ContextWindowMetrics?
    let billing: BillingWindowMetrics
    let weekly: WeeklyUsageMetrics
}

/// Off-main-thread coordinator: performs one directory scan per refresh cycle, resolves
/// each relevant file's records through a JSONLParseCache (so unchanged files are never
/// re-read or re-decoded), and passes derived records to the three metric calculators.
/// Returns nil when called within `minimumInterval` of the previous refresh (debounced).
actor RefreshCoordinator {

    private var lastRefreshDate: Date = .distantPast
    private let parseCache = JSONLParseCache()
    let minimumInterval: TimeInterval
    private let projectsDir: URL?

    init(minimumInterval: TimeInterval = 5, projectsDir: URL? = nil) {
        self.minimumInterval = minimumInterval
        self.projectsDir = projectsDir
    }

    func refresh() async -> RefreshResult? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else {
            return nil
        }
        lastRefreshDate = now

        let scan = JSONLParser.scanAllFiles(relativeTo: now, projectsDir: projectsDir)

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

`JSONLParser.scanAllFiles(relativeTo:projectsDir:)` already accepts an optional `projectsDir` (used by the existing `testScanAllFiles*` tests) and defaults to `~/.claude/projects` when `nil`, so no change is needed there.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS' -only-testing:ClaudeContextMeterTests/ClaudeContextMeterTests`
Expected: PASS — all tests, including the pre-existing `testCoordinatorFirstCallReturnsResult`, `testCoordinatorImmediateSecondCallIsDebounced`, `testCoordinatorCallAfterIntervalIsNotDebounced` (these use the default `projectsDir: nil`, still valid).

- [ ] **Step 5: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Services/RefreshCoordinator.swift ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "perf: RefreshCoordinator parses each relevant file once per refresh via JSONLParseCache"
```

---

### Task 6: Full suite + manual energy verification

**Files:** None (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -scheme ClaudeContextMeter -destination 'platform=macOS'`
Expected: PASS — all tests (pre-existing + new from Tasks 1-5).

- [ ] **Step 2: Run the security scan gate**

Run: `./scripts/scan.sh`
Expected: Gitleaks, Semgrep, and Trivy all pass (per `CLAUDE.md` Security Gate — required before every commit on this repo).

- [ ] **Step 3: Manual energy verification**

Build and run the app (Scott: Cmd+R in Xcode — do not drive Xcode via automation, see [[feedback_xcode_control]]). With the app running, open Activity Monitor's Energy tab and actively use Claude Code in another window/session for several minutes (so the watched directory is being written to, reproducing the original report). Compare the 12-hr Power and Energy Impact columns for `ClaudeContextMeter` against the before-Phase-3 baseline (328.3 Energy Impact / 231.62 12-hr Power observed in the original bug report). Confirm the sustained-spike pattern (spike every 5-10s) is gone or substantially reduced, and that context/billing/weekly numbers in the popover still update correctly and match what the CLI-based Claude usage would suggest.

- [ ] **Step 4: Commit is already done per-task — no further commit needed here.**

This task is verification-only; if energy impact is still unacceptably high after Task 5, do not attempt further ad-hoc fixes — return to Phase 1 of systematic-debugging with fresh profiling data (Instruments' Time Profiler while the app is under the reproduction load) rather than guessing at a Phase 4.
