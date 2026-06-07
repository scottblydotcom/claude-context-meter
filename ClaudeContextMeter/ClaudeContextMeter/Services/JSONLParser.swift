//
//  JSONLParser.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

enum JSONLParser {

    struct SessionScan {
        let mostRecent: URL?
        let billingFiles: [URL]
        let weeklyFiles: [URL]
    }

    /// Parses a JSONL file and returns all decodable SessionRecords.
    static func parse(fileURL: URL) throws -> [SessionRecord] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        var records: [SessionRecord] = []

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8) else { continue }
            if let record = try? decoder.decode(SessionRecord.self, from: data) {
                records.append(record)
            }
        }

        return records
    }

    /// Returns all JSONL files across all Claude projects, including subagents.
    static func allSessionFiles() -> [URL] {
        allSessionFiles(modifiedSince: .distantPast)
    }

    /// Returns JSONL files last modified on or after `date`, skipping older files.
    static func allSessionFiles(modifiedSince date: Date) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return (enumerator.allObjects as? [URL] ?? [])
            .filter {
                guard $0.pathExtension == "jsonl" else { return false }
                let values = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                let modified = values?.contentModificationDate ?? .distantPast
                return modified >= date
            }
    }

    /// Returns the most recently modified non-subagent JSONL file across all Claude projects.
    static func mostRecentSessionFile() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (url: URL, date: Date)?

        for case let url as URL in enumerator {
            // Skip subagent files (path contains "/subagents/")
            guard url.pathExtension == "jsonl",
                  !url.path.contains("/subagents/") else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values?.contentModificationDate ?? .distantPast
            if best == nil || date > best!.date {
                best = (url, date)
            }
        }

        return best?.url
    }

    /// Scans all JSONL files in the projects directory and returns a `SessionScan` containing:
    /// - mostRecent: URL of the most recently modified non-subagent file
    /// - billingFiles: files modified within the last 11 hours
    /// - weeklyFiles: files modified within the current weekly window
    static func scanAllFiles(
        relativeTo now: Date,
        projectsDir: URL? = nil
    ) -> SessionScan {
        let dir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return SessionScan(mostRecent: nil, billingFiles: [], weeklyFiles: []) }
        let billingCutoff = now.addingTimeInterval(-11 * 3600)
        let weeklyCutoff = WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)
        var mostRecent: (url: URL, date: Date)?
        var billingFiles: [URL] = []
        var weeklyFiles: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let mdate = values?.contentModificationDate ?? .distantPast
            if mdate >= billingCutoff { billingFiles.append(url) }
            if mdate >= weeklyCutoff { weeklyFiles.append(url) }
            if !url.pathComponents.contains("subagents") {
                if mostRecent == nil || mdate > mostRecent!.date {
                    mostRecent = (url, mdate)
                }
            }
        }
        return SessionScan(mostRecent: mostRecent?.url, billingFiles: billingFiles, weeklyFiles: weeklyFiles)
    }
}
