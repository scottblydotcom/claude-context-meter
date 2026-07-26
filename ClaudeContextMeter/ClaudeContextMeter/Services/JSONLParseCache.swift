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
/// A value type owned by a single actor (RefreshCoordinator) as a stored `var`. All access is
/// serialized by that actor, and the `mutating` methods make the compiler enforce exclusive
/// access to the cache — compiler-checked thread safety, no manual lock (claude-context-meter-5ww).
/// Marked `nonisolated` because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// without this, every member would implicitly inherit @MainActor isolation and calls from
/// RefreshCoordinator (an actor, not @MainActor) would be Swift 6 language-mode errors.
nonisolated struct JSONLParseCache {
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
    mutating func records(for url: URL) -> [SessionRecord] {
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
    mutating func prune(keeping validURLs: Set<URL>) {
        cache = cache.filter { validURLs.contains($0.key) }
    }
}
