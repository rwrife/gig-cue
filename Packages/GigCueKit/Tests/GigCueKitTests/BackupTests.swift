import Foundation
import Testing
@testable import GigCueKit

@Suite("Backup and export")
struct BackupTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func sampleShows() -> [Show] {
        [
            Show(title: "Friday", items: [
                .song(SongCard(title: "Opening", key: "E", tempo: 120, cues: [StageCue(text: "Lights down")])),
                .breakMarker(BreakMarker(title: "Tuning")),
                .song(SongCard(title: "Encore")),
            ], currentSongID: nil, cursorIndex: 2),
            Show(title: "Saturday", items: [.song(SongCard(title: "Solo set"))]),
        ]
    }

    @Test("backup round-trips identity, order, breaks, cues, and cursor")
    func roundTrip() throws {
        let shows = sampleShows()
        let data = try Backup.encode(shows)
        let decoded = try Backup.decode(data)
        #expect(decoded.shows == shows)
        #expect(decoded.shows[0].items.map(\.id) == shows[0].items.map(\.id))
        #expect(decoded.shows[0].cursorIndex == 2)
        #expect(decoded.shows[0].items[1].breakTitleOrEmpty == "Tuning")
    }

    @Test("restore preview classifies adds, replaces, removals, unchanged")
    func preview() throws {
        let shows = sampleShows()
        var mutated = shows[1]
        mutated.items = [.song(SongCard(title: "Different set"))]
        let added = Show(title: "New gig")
        let backup = BackupDocument(shows: [shows[0], mutated, added])
        let p = Backup.preview(backup: backup, current: shows)
        #expect(p.added.map(\.id) == [added.id])
        #expect(p.replaced.map(\.id) == [mutated.id])
        #expect(p.unchanged.map(\.id) == [shows[0].id])
        #expect(p.removed.isEmpty)
        #expect(p.changeCount == 2)
    }

    @Test("malformed input rejected before any write; live data preserved")
    func malformedRejected() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShowStore(directory: root)
        let shows = sampleShows()
        for show in shows { try store.save(show) }

        #expect(throws: BackupError.self) { try Backup.decode(Data("{ not json".utf8)) }
        #expect(throws: BackupError.unsupportedVersion(99)) {
            try Backup.decode(Data(#"{"schemaVersion":99,"shows":[]}"#.utf8))
        }
        // Duplicate item IDs inside a show must fail validation.
        let shared = UUID()
        let bad = Data("""
        {"schemaVersion":1,"shows":[{"id":"\(UUID().uuidString)","title":"Bad","items":[{"song":{"id":"\(shared.uuidString)","title":"A","cues":[]}},{"breakMarker":{"id":"\(shared.uuidString)","title":"B"}}]}]}
        """.utf8)
        #expect(throws: BackupError.self) { _ = try Backup.decode(bad) }

        // Live store untouched by every failed attempt.
        #expect(try store.list() == shows)
    }

    @Test("replaceAll swaps directories and preserves originals on staged failure")
    func replaceAll() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShowStore(directory: root)
        let originals = sampleShows()
        for show in originals { try store.save(show) }

        // Invalid candidate: rejected before touching live data.
        #expect(throws: ShowStoreError.invalidShow) {
            try store.replaceAll(with: [Show(title: "  ")])
        }
        #expect(try store.list() == originals)

        // Valid replacement: old show removed, new show present.
        let replacement = [Show(title: "Tour", items: [.song(SongCard(title: "New song"))])]
        try store.replaceAll(with: replacement)
        #expect(try store.list() == replacement)
        #expect(throws: (any Error).self) { try store.load(id: originals[0].id) }
    }

    @Test("plain-text export lists numbered songs, details, cues, breaks")
    func plainText() {
        let show = sampleShows()[0]
        let text = SetlistExport.plainText(show)
        #expect(text.contains("1. Opening — key E, 120 BPM"))
        #expect(text.contains("• Lights down"))
        #expect(text.contains("[BREAK] Tuning"))
        #expect(text.contains("2. Encore"))
        // Unknown key/tempo renders nothing rather than a guessed value.
        #expect(!text.contains("Encore —"))
    }
}

private extension SetItem {
    var breakTitleOrEmpty: String? {
        if case .breakMarker(let marker) = self { return marker.title }
        return nil
    }
}
