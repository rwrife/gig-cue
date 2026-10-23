import Foundation

/// Schema-versioned, device-local backup document covering every saved show.
///
/// Backups are plain Codable JSON. They are only ever written or shared when
/// the user explicitly invokes export/restore; nothing here touches the
/// network. `decode` validates before anything is written so a malformed or
/// future-version document can never overwrite live data.
public struct BackupDocument: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var shows: [Show]

    /// Stable identity for SwiftUI sheet presentation; not encoded.
    public var id: UUID = UUID()

    public init(schemaVersion: Int = BackupDocument.currentVersion, shows: [Show]) {
        self.schemaVersion = schemaVersion
        self.shows = shows
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, shows }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        shows = try container.decode([Show].self, forKey: .shows)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(shows, forKey: .shows)
    }
}

public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case malformed(String)
}

public enum Backup {
    /// Parse + validate a candidate backup without touching the store.
    /// Unknown schema versions and structurally invalid shows (duplicate IDs,
    /// empty titles, non-positive tempos) are rejected here, before any write.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let document: BackupDocument
        do {
            document = try JSONDecoder().decode(BackupDocument.self, from: data)
        } catch let error as ShowStoreError {
            throw BackupError.malformed(error.localizedDescription)
        } catch {
            throw BackupError.malformed(error.localizedDescription)
        }
        guard document.schemaVersion == BackupDocument.currentVersion else {
            throw BackupError.unsupportedVersion(document.schemaVersion)
        }
        let store = ShowStore(directory: FileManager.default.temporaryDirectory)
        for show in document.shows where !store.isValid(show) {
            throw BackupError.malformed("Show \(show.id.uuidString) failed validation")
        }
        let ids = document.shows.map(\.id)
        guard Set(ids).count == ids.count else {
            throw BackupError.malformed("Duplicate show IDs")
        }
        return document
    }

    public static func encode(_ shows: [Show]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(BackupDocument(shows: shows))
    }

    /// Non-destructive preview of a restore: what `apply` would change.
    public struct Preview: Equatable, Sendable {
        public var added: [Show]
        public var replaced: [Show]
        public var removed: [Show]
        public var unchanged: [Show]

        public init(added: [Show], replaced: [Show], removed: [Show], unchanged: [Show]) {
            self.added = added
            self.replaced = replaced
            self.removed = removed
            self.unchanged = unchanged
        }

        public var isEmpty: Bool { added.isEmpty && replaced.isEmpty && removed.isEmpty }
        public var changeCount: Int { added.count + replaced.count + removed.count }
    }

    public static func preview(backup: BackupDocument, current: [Show]) -> Preview {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let backupIDs = Set(backup.shows.map(\.id))
        let added = backup.shows.filter { currentByID[$0.id] == nil }
        let replaced = backup.shows.filter { show in
            currentByID[show.id].map { $0 != show } ?? false
        }
        let unchanged = backup.shows.filter { show in currentByID[show.id] == show }
        let removed = current.filter { !backupIDs.contains($0.id) }
        return Preview(added: added, replaced: replaced, removed: removed, unchanged: unchanged)
    }
}

/// Plain-text setlist handout for bandmates: ordered rows, break markers,
/// key/tempo when known, and cue notes.
public enum SetlistExport {
    public static func plainText(_ show: Show) -> String {
        var lines: [String] = [show.title, String(repeating: "=", count: show.title.count)]
        var number = 0
        for item in show.items {
            switch item {
            case .song(let song):
                number += 1
                var line = "\(number). \(song.title)"
                var details: [String] = []
                if let key = song.key { details.append("key \(key)") }
                if let tempo = song.tempo { details.append("\(tempo) BPM") }
                if !details.isEmpty { line += " — " + details.joined(separator: ", ") }
                lines.append(line)
                for cue in song.cues { lines.append("   • \(cue.text)") }
            case .breakMarker(let marker):
                lines.append("[BREAK] \(marker.title)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
