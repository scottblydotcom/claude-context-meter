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
