import Foundation
import Testing
@testable import GigCueKit

@Suite("Show storage")
struct ShowStorageTests {
    @Test("ordered items and unknown key/tempo survive a round trip")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = SongCard(title: "Opening", cues: [StageCue(text: "Lights down")])
        let second = SongCard(title: "Encore", key: "G", tempo: 120)
        let show = Show(title: "Friday", items: [.song(second), .breakMarker(BreakMarker(title: "Intermission")), .song(first)], currentSongID: first.id)
        let store = ShowStore(directory: root)
        try store.save(show)
        let loaded = try store.load(id: show.id)
        #expect(loaded == show)
        #expect(loaded.items.compactMap { $0.song }.map(\.id) == [second.id, first.id])
        #expect(loaded.items.last?.song?.key == nil)
        #expect(loaded.items.last?.song?.tempo == nil)
    }

    @Test("truncated JSON surfaces error without overwriting last good file")
    func invalidJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let show = Show(title: "Friday", items: [.song(SongCard(title: "One"))])
        let store = ShowStore(directory: root)
        try store.save(show)
        let file = root.appendingPathComponent("\(show.id.uuidString).json")
        let good = try Data(contentsOf: file)
        try Data("{\"version\":".utf8).write(to: file)
        #expect(throws: (any Error).self) { try store.load(id: show.id) }
        #expect(try Data(contentsOf: file) != good)
        #expect(throws: (any Error).self) { try store.save(Show(id: show.id, title: "", items: [])) }
        #expect(try Data(contentsOf: file) == Data("{\"version\":".utf8))
    }

    @Test("legacy version 1 migrates without losing ordered songs")
    func migration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let song = UUID()
        let fixture = """
        {"version":1,"show":{"id":"\(id.uuidString)","title":"Friday","items":[{"song":{"id":"\(song.uuidString)","title":"Opening","cues":[]}}]}}
        """
        try Data(fixture.utf8).write(to: root.appendingPathComponent("\(id.uuidString).json"))
        let loaded = try ShowStore(directory: root).load(id: id)
        #expect(loaded.currentSongID == nil)
        #expect(loaded.items.first?.song?.id == song)
    }

    @Test("duplicate item IDs are rejected before disk write")
    func duplicateIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let show = Show(title: "Friday", items: [
            .song(SongCard(id: id, title: "One")),
            .breakMarker(BreakMarker(id: id, title: "Pause")),
        ])
        #expect(throws: ShowStoreError.invalidShow) { try ShowStore(directory: root).save(show) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("duplicate cue IDs are rejected")
    func duplicateCues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = StageCue(text: "Lights down")
        let show = Show(title: "Friday", items: [
            .song(SongCard(title: "One", cues: [cue, cue])),
        ])
        #expect(throws: ShowStoreError.invalidShow) { try ShowStore(directory: root).save(show) }
    }

    @Test("unknown document version is surfaced and cannot be overwritten")
    func unsupportedVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let show = Show(title: "Friday")
        let file = root.appendingPathComponent("\(show.id.uuidString).json")
        let fixture = Data("{\"version\":99,\"show\":{}}".utf8)
        try fixture.write(to: file)
        #expect(throws: ShowStoreError.unsupportedVersion(99)) { try ShowStore(directory: root).save(show) }
        #expect(try Data(contentsOf: file) == fixture)
    }

    @Test("write failure leaves existing document unchanged")
    func failedWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let show = Show(title: "Friday")
        let store = ShowStore(directory: root)
        try store.save(show)
        let file = root.appendingPathComponent("\(show.id.uuidString).json")
        let before = try Data(contentsOf: file)
        // FileManager atomic writes use temporary files in this directory;
        // a directory path at destination is a deterministic write failure.
        let blocked = ShowStore(directory: file)
        #expect(throws: (any Error).self) { try blocked.save(show) }
        #expect(try Data(contentsOf: file) == before)
    }
}
