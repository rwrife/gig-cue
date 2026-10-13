import Foundation
import Testing
@testable import GigCueKit

private func song(_ title: String) -> SongCard { SongCard(title: title) }

@Suite("Stage flow")
struct StageFlowTests {
    private func show(_ items: [SetItem], current: UUID? = nil) -> Show {
        Show(title: "Friday", items: items, currentSongID: current)
    }

    @Test("resume lands on the saved song and forward needs a confirming second tap")
    func resumeAndGuardedNext() throws {
        let a = song("A"), b = song("B")
        let flow = StageFlow(show: show([.song(a), .song(b)], current: b.id))
        #expect(flow.current == .song(b))
        #expect(flow.currentSongID == b.id)

        // B is last; guard arming on a real song-to-song move happens at A.
        var entering = StageFlow(show: show([.song(a), .song(b)]))
        #expect(entering.current == .song(a))
        #expect(entering.requestNext() == .requiresConfirmation(.song(b)))
        #expect(entering.current == .song(a)) // not moved yet
        #expect(entering.confirmPendingNext() == .moved(.song(b)))
        #expect(entering.currentSongID == b.id)
    }

    @Test("back is immediate and cancels a pending skip")
    func backCancelsPending() throws {
        let a = song("A"), b = song("B")
        var flow = StageFlow(show: show([.song(a), .song(b)]))
        _ = flow.requestNext()
        #expect(flow.back() == nil) // already first; cancels pending latch
        // Pending latch cleared: advancing again must ask for confirmation again.
        #expect(flow.requestNext() == .requiresConfirmation(.song(b)))
        _ = flow.confirmPendingNext()
        #expect(flow.back() == .song(a))
        #expect(flow.back() == nil) // already first
    }

    @Test("break transitions are unguarded banners and resume keeps place before the break")
    func breakTransitions() throws {
        let a = song("A"), b = song("B")
        let pause = BreakMarker(title: "Intermission")
        let items: [SetItem] = [.song(a), .breakMarker(pause), .song(b)]

        var flow = StageFlow(show: show(items))
        #expect(flow.requestNext() == .moved(.breakMarker(pause))) // no confirm for breaks
        #expect(flow.currentSongID == a.id) // saved place stays before the break
        #expect(flow.requestNext() == .requiresConfirmation(.song(b)))
        #expect(flow.confirmPendingNext() == .moved(.song(b)))

        // Persist the stage snapshot; reopening mid-break resumes the banner.
        let reopened = StageFlow(show: flow.show)
        #expect(reopened.current == .song(b))
        var midBreak = StageFlow(show: show(items))
        _ = midBreak.requestNext()
        #expect(StageFlow(show: midBreak.show).current == .breakMarker(pause))
    }

    @Test("break banner persists across process restart")
    func persistedBreak() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = song("A"), pause = BreakMarker(title: "Intermission")
        var flow = StageFlow(show: show([.song(a), .breakMarker(pause)]))
        _ = flow.requestNext()
        let store = ShowStore(directory: root)
        try store.save(flow.show)
        let reloaded = StageFlow(show: try store.load(id: flow.show.id))
        #expect(reloaded.current == .breakMarker(pause))
        #expect(reloaded.currentSongID == a.id)
    }

    @Test("deleting the current song while active falls to the next song, then previous")
    func deleteWhileActive() throws {
        let a = song("A"), b = song("B"), c = song("C")
        let items: [SetItem] = [.song(a), .song(b), .song(c)]
        var flow = StageFlow(show: show(items, current: b.id))

        flow.sync(items: [.song(a), .song(c)]) // B deleted
        #expect(flow.current == .song(c))
        #expect(flow.currentSongID == c.id)

        flow.sync(items: [.song(a)]) // C deleted too
        #expect(flow.current == .song(a))

        flow.sync(items: [])
        #expect(flow.current == nil)
        #expect(flow.currentSongID == nil)
    }

    @Test("reordering while active follows the song identity, not the old index")
    func reorderWhileActive() throws {
        let a = song("A"), b = song("B"), c = song("C")
        var flow = StageFlow(show: show([.song(a), .song(b), .song(c)], current: a.id))
        flow.sync(items: [.song(c), .song(b), .song(a)])
        #expect(flow.current == .song(a)) // still A, now last
        #expect(flow.requestNext() == .atEnd)
    }

    @Test("dangling saved ID after external edits cannot strand progress")
    func danglingSavedID() throws {
        let a = song("A"), b = song("B")
        let flow = StageFlow(show: show([.song(a), .song(b)], current: UUID()))
        #expect(flow.current == .song(a))
        #expect(flow.currentSongID == a.id)
    }

    @Test("unknown key/tempo stay unknown on the stage focus")
    func noInferredMetadata() throws {
        let plain = song("Plain")
        let flow = StageFlow(show: show([.song(plain)]))
        guard case .song(let card) = flow.current else { Issue.record("expected song focus"); return }
        #expect(card.key == nil)
        #expect(card.tempo == nil)
    }
}
