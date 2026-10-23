import Foundation

public struct StageCue: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct SongCard: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var key: String?
    public var tempo: Int?
    public var cues: [StageCue]

    public init(id: UUID = UUID(), title: String, key: String? = nil, tempo: Int? = nil, cues: [StageCue] = []) {
        self.id = id
        self.title = title
        self.key = key
        self.tempo = tempo
        self.cues = cues
    }
}

public struct BreakMarker: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

public enum SetItem: Equatable, Hashable, Sendable, Codable {
    case song(SongCard)
    case breakMarker(BreakMarker)

    private enum Kind: String, CodingKey { case song, breakMarker }

    public var id: UUID {
        switch self {
        case .song(let song): song.id
        case .breakMarker(let marker): marker.id
        }
    }

    public var song: SongCard? {
        if case .song(let song) = self { return song }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Kind.self)
        guard container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one item kind"))
        }
        switch container.allKeys[0] {
        case .song: self = .song(try container.decode(SongCard.self, forKey: .song))
        case .breakMarker: self = .breakMarker(try container.decode(BreakMarker.self, forKey: .breakMarker))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Kind.self)
        switch self {
        case .song(let song): try container.encode(song, forKey: .song)
        case .breakMarker(let marker): try container.encode(marker, forKey: .breakMarker)
        }
    }
}

public struct Show: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var items: [SetItem]
    public var currentSongID: UUID?
    /// Persisted stage cursor (index into `items`). Absent until the show is
    /// opened on stage; optional so older documents still decode.
    public var cursorIndex: Int?

    public init(id: UUID = UUID(), title: String, items: [SetItem] = [], currentSongID: UUID? = nil, cursorIndex: Int? = nil) {
        self.id = id
        self.title = title
        self.items = items
        self.currentSongID = currentSongID
        self.cursorIndex = cursorIndex
    }
}

public enum ShowStoreError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidShow
}

public extension Show {
    func duplicated() -> Show {
        Show(title: title + " Copy", items: items.map { item in
            switch item {
            case .song(let song):
                return .song(SongCard(title: song.title, key: song.key, tempo: song.tempo,
                                      cues: song.cues.map { StageCue(text: $0.text) }))
            case .breakMarker(let marker):
                return .breakMarker(BreakMarker(title: marker.title))
            }
        })
    }
}

public extension ShowStore {
    static func validTitle(_ title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct ShowStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GigCue", isDirectory: true)
    }

    private struct Document: Codable {
        var version: Int
        var show: Show
    }

    private struct LegacyShow: Codable {
        var id: UUID
        var title: String
        var items: [SetItem]
    }

    private struct LegacyDocument: Codable {
        var version: Int
        var show: LegacyShow
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func list() throws -> [Show] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in UUID(uuidString: url.deletingPathExtension().lastPathComponent) }
            .map { try load(id: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func load(id: UUID) throws -> Show {
        let data = try Data(contentsOf: file(for: id))
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).version
        let show: Show
        switch version {
        case 1:
            let legacy = try decoder.decode(LegacyDocument.self, from: data).show
            show = Show(id: legacy.id, title: legacy.title, items: legacy.items)
        case 2:
            show = try decoder.decode(Document.self, from: data).show
        default:
            throw ShowStoreError.unsupportedVersion(version)
        }
        guard show.id == id, isValid(show) else { throw ShowStoreError.invalidShow }
        return show
    }

    private struct Version: Decodable { var version: Int }

    public func isValid(_ show: Show) -> Bool {
        guard Self.validTitle(show.title),
              Set(show.items.map(\.id)).count == show.items.count else { return false }
        let songs = show.items.compactMap(\.song)
        guard songs.allSatisfy({ Self.validTitle($0.title) && ($0.tempo.map { $0 > 0 } ?? true) }),
              show.items.allSatisfy({ item in
                  if case .breakMarker(let marker) = item { return Self.validTitle(marker.title) }
                  return true
              }) else { return false }
        let cues = songs.flatMap(\.cues)
        guard Set(cues.map(\.id)).count == cues.count else { return false }
        return show.currentSongID.map { id in show.items.contains { $0.song?.id == id } } ?? true
    }

    public func save(_ show: Show) throws {
        guard isValid(show) else { throw ShowStoreError.invalidShow }
        let destination = file(for: show.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try load(id: show.id) // Never overwrite unreadable or unsupported documents.
        }
        let data = try JSONEncoder().encode(Document(version: 2, show: show))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    /// Stage every file before touching live data; swap directories only after
    /// validation and successful writes. Restore old directory on swap error.
    public func replaceAll(with shows: [Show]) throws {
        for show in shows where !isValid(show) { throw ShowStoreError.invalidShow }
        let ids = shows.map(\.id)
        guard Set(ids).count == ids.count else { throw ShowStoreError.invalidShow }
        _ = try list() // Reject unreadable or future-version live documents.

        let parent = directory.deletingLastPathComponent()
        let stage = parent.appendingPathComponent("GigCue-stage-\(UUID().uuidString)", isDirectory: true)
        let rollback = parent.appendingPathComponent("GigCue-rollback-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        do {
            let candidateStore = ShowStore(directory: stage)
            try manager.createDirectory(at: stage, withIntermediateDirectories: true)
            for show in shows { try candidateStore.save(show) }
            let hadLive = manager.fileExists(atPath: directory.path)
            if hadLive { try manager.moveItem(at: directory, to: rollback) }
            do {
                try manager.moveItem(at: stage, to: directory)
            } catch {
                if hadLive { try manager.moveItem(at: rollback, to: directory) }
                throw error
            }
            if hadLive { try? manager.removeItem(at: rollback) }
        } catch {
            try? manager.removeItem(at: stage)
            throw error
        }
    }
}
