import Foundation

/// Restart-safe stage navigation for one show: the cursor is a persisted
/// item index on `Show`, so leaving and reopening resumes the same card,
/// including break banners. Song-to-song advances require a deliberate
/// second tap; moves onto a break banner are immediate (no song is skipped).
public struct StageFlow: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Advance is pending confirmation; carries the card it would move to.
        case requiresConfirmation(SetItem)
        /// The cursor moved (break transitions and confirmed advances).
        case moved(SetItem)
        /// The cursor is already on the last item.
        case atEnd
    }

    public private(set) var show: Show
    /// True while a song-to-song advance is awaiting the confirming tap.
    public private(set) var pendingNext: Bool = false

    private var cursor: Int? {
        get { show.cursorIndex }
        set { show.cursorIndex = newValue }
    }

    public init(show: Show) {
        self.show = show
        // Resume by song identity first (survives reorders), else the saved
        // index, else the first item. A saved ID that no longer resolves
        // (deleted while inactive) re-anchors instead of stranding progress.
        let items = show.items
        if let idx = show.cursorIndex, items.indices.contains(idx),
           case .breakMarker = items[idx] {
            cursor = idx // persisted break banner outranks the preceding song ID
        } else if let id = show.currentSongID, let idx = items.firstIndex(where: { $0.song?.id == id }) {
            cursor = idx
        } else if let idx = show.cursorIndex, items.indices.contains(idx) {
            cursor = idx
        } else {
            cursor = items.isEmpty ? nil : 0
            if !items.isEmpty { self.show.currentSongID = items[0].song?.id }
        }
    }

    public var current: SetItem? {
        cursor.flatMap { show.items.indices.contains($0) ? show.items[$0] : nil }
    }

    public var currentSongID: UUID? { show.currentSongID }

    /// The card after the cursor, for the "next" preview. Pure lookup.
    public var next: SetItem? {
        guard let idx = cursor, show.items.indices.contains(idx + 1) else { return nil }
        return show.items[idx + 1]
    }

    /// Re-anchor the cursor after external edits (delete/reorder while the
    /// show is active): follow the current song's identity, else fall to the
    /// next song at the old position, then the previous, else clear.
    public mutating func sync(items: [SetItem]) {
        let previous = current
        show.items = items
        guard let previous else {
            cursor = nil
            show.currentSongID = nil
            return
        }
        if let idx = items.firstIndex(where: { $0.id == previous.id }) {
            cursor = idx
            show.currentSongID = items[idx].song?.id ?? show.currentSongID
            return
        }
        let anchor = min(cursor ?? 0, max(items.count - 1, 0))
        if items.isEmpty {
            cursor = nil
            show.currentSongID = nil
        } else {
            cursor = items[anchor..<items.count].firstIndex(where: { $0.song != nil })
                ?? items[...anchor].lastIndex(where: { $0.song != nil })
                ?? (items.indices.contains(anchor) ? anchor : nil)
            show.currentSongID = cursor.flatMap { items[$0].song?.id }
        }
        pendingNext = false
    }

    public mutating func requestNext() -> Step {
        guard let idx = cursor, show.items.indices.contains(idx) else { return .atEnd }
        guard idx + 1 < show.items.count else {
            pendingNext = false
            return .atEnd
        }
        let target = show.items[idx + 1]
        if case .breakMarker = target {
            return move(to: idx + 1) // No song is skipped; no guard needed.
        }
        if !pendingNext {
            pendingNext = true
            return .requiresConfirmation(target)
        }
        return move(to: idx + 1)
    }

    public mutating func confirmPendingNext() -> Step {
        guard pendingNext else { return requestNext() }
        return requestNext()
    }

    @discardableResult
    public mutating func back() -> SetItem? {
        pendingNext = false
        guard let idx = cursor else { return nil }
        var target = idx - 1
        while target >= 0, show.items[target].song == nil { target -= 1 }
        guard target >= 0 else { return nil }
        show.cursorIndex = target
        show.currentSongID = show.items[target].song?.id
        cursor = target
        return show.items[target]
    }

    private mutating func move(to index: Int) -> Step {
        pendingNext = false
        cursor = index
        if let song = show.items[index].song { show.currentSongID = song.id }
        return .moved(show.items[index])
    }
}
