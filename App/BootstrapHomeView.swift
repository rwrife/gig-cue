import GigCueKit
import SwiftUI
import UIKit

struct BootstrapHomeView: View {
    @State private var shows: [Show] = []
    @State private var activeShow: Show?
    @State private var editingShow: Show?
    @State private var newTitle = ""
    @State private var storageError: String?
    @State private var showImportPicker = false
    @State private var pendingRestore: BackupDocument?
    @State private var restorePreview: Backup.Preview?
    @State private var shareItems: [URL] = []
    @State private var showShareSheet = false
    private let store = ShowStore()

    var body: some View {
        NavigationStack {
            List {
                Section("New show") {
                    TextField("Show name", text: $newTitle)
                        .submitLabel(.done)
                        .accessibilityIdentifier("show.newTitle")
                    Button("Create show") {
                        let show = Show(title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                        persist(show)
                        if storageError == nil { newTitle = ""; editingShow = show }
                    }
                    .disabled(!ShowStore.validTitle(newTitle))
                    .accessibilityIdentifier("show.create")
                }
                // Keep fixture entry visible ahead of saved-show rows at AX text sizes.
                if CommandLine.arguments.contains("-ui-testing") {
                    Button("Enter sample stage mode", action: openSampleStage)
                        .accessibilityIdentifier("stage.enter")
                }
                Section("Saved shows") {
                    ForEach(shows, id: \.id) { show in
                        VStack(alignment: .leading) {
                            Text(show.title).font(.headline)
                            HStack {
                                Button("Edit") { editingShow = show }
                                    .accessibilityIdentifier("show.edit.\(show.id)")
                                Button("Duplicate") { persist(show.duplicated()) }
                                    .accessibilityIdentifier("show.duplicate.\(show.id)")
                                Button("Stage") { activeShow = show }
                                    .accessibilityIdentifier("show.stage.\(show.id)")
                                Button("Export") { exportText(show) }
                                    .accessibilityIdentifier("show.export.\(show.id)")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section("Backup & restore") {
                    Button("Export JSON backup") { exportBackup() }
                        .accessibilityIdentifier("backup.export")
                        .accessibilityHint("Shares a local JSON copy of all shows; you choose the destination.")
                    Button("Restore from JSON file") { showImportPicker = true }
                        .accessibilityIdentifier("backup.restore")
                        .accessibilityHint("Preview changes first; nothing is replaced until you confirm.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reload") { reload() }
                }
            }
            .navigationTitle("Gig Cue")
            .navigationDestination(item: $activeShow) { show in
                StageModeView(initialShow: show, store: store)
            }
            .sheet(item: $editingShow, onDismiss: reload) { show in
                ShowEditorView(initialShow: show, store: store, onSave: reload)
            }
            .sheet(isPresented: $showImportPicker) {
                JSONDocumentPicker { data in
                    showImportPicker = false
                    guard let data else { return }
                    inspectRestore(data)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(item: $pendingRestore) { backup in
                RestorePreviewSheet(
                    preview: restorePreview ?? Backup.preview(backup: backup, current: shows),
                    onConfirm: {
                        do {
                            try store.replaceAll(with: backup.shows)
                            pendingRestore = nil
                            restorePreview = nil
                            reload()
                        } catch {
                            storageError = error.localizedDescription
                        }
                    },
                    onCancel: {
                        pendingRestore = nil
                        restorePreview = nil
                    }
                )
            }
            .onAppear(perform: reload)
            .alert("Storage error", isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )) { Button("OK", role: .cancel) { storageError = nil } } message: {
                Text(storageError ?? "Unable to save show")
            }
        }
    }

    private func persist(_ show: Show) {
        do { try store.save(show); reload() }
        catch { storageError = error.localizedDescription }
    }

    private func reload() {
        do { shows = try store.list() }
        catch { storageError = error.localizedDescription }
    }

    private func exportBackup() {
        do {
            let data = try Backup.encode(try store.list())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GigCue-Backup-\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)
            shareItems = [url]
            showShareSheet = true
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func exportText(_ show: Show) {
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GigCue-Setlist-\(UUID().uuidString).txt")
            try Data(SetlistExport.plainText(show).utf8).write(to: url, options: .atomic)
            shareItems = [url]
            showShareSheet = true
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func inspectRestore(_ data: Data) {
        do {
            let backup = try Backup.decode(data)
            restorePreview = Backup.preview(backup: backup, current: try store.list())
            pendingRestore = backup
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func openSampleStage() {
        let sampleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let resetForUITest = CommandLine.arguments.contains("-ui-reset-stage")
        let exists = FileManager.default.fileExists(
            atPath: store.directory.appendingPathComponent("\(sampleID.uuidString).json").path
        )
        if exists && !resetForUITest {
            do { activeShow = try store.load(id: sampleID) }
            catch { storageError = error.localizedDescription }
            return
        }
        if resetForUITest, exists {
            do {
                try FileManager.default.removeItem(
                    at: store.directory.appendingPathComponent("\(sampleID.uuidString).json")
                )
            } catch {
                storageError = error.localizedDescription
                return
            }
        }
        let sample = Show(
            id: sampleID,
            title: "Standard Set",
            items: [
                .song(SongCard(title: "First Track", key: "Em", tempo: 110, cues: [StageCue(text: "Intro loop 4 bars")])),
                .breakMarker(BreakMarker(title: "Band Tuning Break")),
                .song(SongCard(title: "Closing Track", key: "A", tempo: 130, cues: [StageCue(text: "Fade to black on final hit")])),
            ]
        )
        do {
            try store.save(sample)
            activeShow = sample
        } catch {
            storageError = error.localizedDescription
        }
    }
}

/// Non-destructive restore preview with explicit replace confirmation.
struct RestorePreviewSheet: View {
    let preview: Backup.Preview
    let onConfirm: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void

    var body: some View {
        NavigationStack {
            List {
                if preview.isEmpty {
                    Text("Backup matches current shows. Nothing to replace.")
                        .accessibilityIdentifier("restore.summary")
                } else {
                    Section("Summary") {
                        Text("Adds \(preview.added.count), replaces \(preview.replaced.count), removes \(preview.removed.count).")
                            .accessibilityIdentifier("restore.summary")
                    }
                    if !preview.added.isEmpty {
                        Section("Added shows") { ForEach(preview.added) { Text($0.title) } }
                    }
                    if !preview.replaced.isEmpty {
                        Section("Replaced shows") { ForEach(preview.replaced) { Text($0.title) } }
                    }
                    if !preview.removed.isEmpty {
                        Section("Removed shows") { ForEach(preview.removed) { Text($0.title) } }
                    }
                }
            }
            .navigationTitle("Restore preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("restore.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Replace", role: .destructive, action: onConfirm)
                        .disabled(preview.isEmpty)
                        .accessibilityHint("Replaces all saved shows with backup contents. This cannot be undone.")
                        .accessibilityIdentifier("restore.confirm")
                }
            }
        }
    }
}

struct StageModeView: View {
    @State private var flow: StageFlow
    @State private var storageError: String?
    @State private var stageDimmed = false
    @State private var keepScreenAwake = false
    private let store: ShowStore

    init(initialShow: Show, store: ShowStore) {
        _flow = State(initialValue: StageFlow(show: initialShow))
        self.store = store
    }

    var body: some View {
        GigWorkspaceLayout {
            ScrollView {
                VStack(spacing: 20) {
                    currentCard
                    nextCard
                }
                .frame(maxWidth: .infinity)
            }
        } deck: {
            controlDeck
        }
        .padding()
        .background(stageDimmed ? Color.black : Color(.systemBackground))
        .foregroundStyle(stageDimmed ? Color.white : Color.primary)
        .tint(stageDimmed ? Color.yellow : Color.accentColor)
        .navigationTitle(flow.show.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .alert("Storage error", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) { Button("OK", role: .cancel) { storageError = nil } } message: {
            Text(storageError ?? "Unable to save stage progress")
        }
    }

    @ViewBuilder private var currentCard: some View {
        Group {
            switch flow.current {
            case .song(let song):
                VStack(alignment: .leading, spacing: 12) {
                    Text("CURRENT")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(song.title)
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("stage.currentSongTitle")
                    HStack(spacing: 16) {
                        if let key = song.key {
                            Label("Key \(key)", systemImage: "music.note")
                        } else {
                            Text("Key unknown").foregroundStyle(.secondary)
                        }
                        if let tempo = song.tempo {
                            Label("\(tempo) BPM", systemImage: "metronome")
                        } else {
                            Text("Tempo unknown").foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    if !song.cues.isEmpty {
                        Divider()
                        Text("CUES")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(song.cues, id: \.id) { cue in
                            Text(cue.text)
                                .font(.body)
                                .accessibilityIdentifier("stage.cueText")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(stageDimmed ? Color.white.opacity(0.12) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .breakMarker(let marker):
                VStack(spacing: 8) {
                    Label(marker.title, systemImage: "pause.circle")
                        .font(.title2.bold())
                    Text("Set intermission — stage paused")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stage.breakBanner")

            case .none:
                Text("Set is empty")
                    .foregroundStyle(stageDimmed ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var nextCard: some View {
        if let next = flow.next {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT")
                    .font(.caption.bold())
                    .foregroundStyle(stageDimmed ? Color.white.opacity(0.8) : Color.secondary)
                switch next {
                case .song(let song):
                    Text(song.title)
                        .font(.title3.bold())
                        .accessibilityIdentifier("stage.nextSongTitle")
                case .breakMarker(let marker):
                    Label(marker.title, systemImage: "pause.circle").font(.title3.bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(stageDimmed ? Color.white.opacity(0.12) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stage.nextCard")
        }
    }

    private var controlDeck: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: handleBack) {
                    Label("Back", systemImage: "backward.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stage.backButton")

                Button(action: handleNext) {
                    Label(flow.pendingNext ? "Tap again to confirm" : "Next", systemImage: flow.pendingNext ? "exclamationmark.triangle.fill" : "forward.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(flow.pendingNext ? .orange : .accentColor)
                .accessibilityHint(flow.pendingNext
                    ? "Press again to skip to the next song."
                    : "Press twice to skip to the next song; a confirmation step prevents accidental skips.")
                .accessibilityIdentifier("stage.nextButton")
            }
            HStack(spacing: 16) {
                Toggle(isOn: $stageDimmed) {
                    Label("Stage dim", systemImage: "circle.lefthalf.filled")
                        .font(.footnote)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("stage.dimToggle")

                Toggle(isOn: $keepScreenAwake) {
                    Label("Keep awake", systemImage: "sun.max")
                        .font(.footnote)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("stage.awakeToggle")

                Spacer()
            }
        }
    }

    private func handleBack() {
        var updated = flow
        updated.back()
        commit(updated)
    }

    private func handleNext() {
        var updated = flow
        _ = updated.requestNext()
        commit(updated)
    }

    private func commit(_ updated: StageFlow) {
        do {
            try store.save(updated.show)
            flow = updated
        } catch {
            storageError = error.localizedDescription
        }
    }
}

struct ShowEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var show: Show
    @State private var songTitle = ""
    @State private var songKey = ""
    @State private var songTempo = ""
    @State private var songCue = ""
    @State private var breakTitle = ""
    @State private var editingSongID: UUID?
    @State private var editTitle = ""
    @State private var editKey = ""
    @State private var editTempo = ""
    @State private var editCue = ""
    @State private var storageError: String?
    private let store: ShowStore
    private let onSave: @MainActor @Sendable () -> Void

    init(initialShow: Show, store: ShowStore, onSave: @escaping @MainActor @Sendable () -> Void) {
        _show = State(initialValue: initialShow)
        self.store = store
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Add song") {
                    TextField("Title", text: $songTitle)
                        .accessibilityIdentifier("editor.songTitle")
                    TextField("Key (optional)", text: $songKey)
                        .accessibilityIdentifier("editor.songKey")
                    TextField("Tempo BPM (optional)", text: $songTempo)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("editor.songTempo")
                    TextField("Cue note (optional)", text: $songCue)
                        .accessibilityIdentifier("editor.songCue")
                    Button("Add song") {
                        let cue = songCue.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cues = cue.isEmpty ? [] : [StageCue(text: cue)]
                        let tempo = Int(songTempo.trimmingCharacters(in: .whitespacesAndNewlines))
                        let keyStr = songKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let card = SongCard(
                            title: songTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            key: keyStr.isEmpty ? nil : keyStr,
                            tempo: tempo,
                            cues: cues
                        )
                        var updated = show
                        updated.items.append(.song(card))
                        if save(updated) { songTitle = ""; songKey = ""; songTempo = ""; songCue = "" }
                    }
                    .disabled(!ShowStore.validTitle(songTitle) || !validTempo(songTempo))
                    .accessibilityIdentifier("editor.addSong")
                }

                Section("Add break") {
                    TextField("Break label (e.g. Intermission)", text: $breakTitle)
                        .accessibilityIdentifier("editor.breakTitle")
                    Button("Insert break") {
                        let title = breakTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        var updated = show
                        updated.items.append(.breakMarker(BreakMarker(title: title.isEmpty ? "Break" : title)))
                        if save(updated) { breakTitle = "" }
                    }
                    .accessibilityIdentifier("editor.insertBreak")
                }

                Section("Set order (\(show.items.count) items)") {
                    ForEach(Array(show.items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .song(let song):
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(index + 1). \(song.title)").font(.headline)
                                    Spacer()
                                    if let key = song.key { Text(key).font(.caption).foregroundStyle(.secondary) }
                                    if let tempo = song.tempo { Text("\(tempo) bpm").font(.caption).foregroundStyle(.secondary) }
                                }
                                if let cue = song.cues.first {
                                    Text("Cue: \(cue.text)").font(.caption).foregroundStyle(.secondary)
                                }
                                Button {
                                    moveSong(song.id, direction: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Move up")
                                .accessibilityIdentifier("editor.moveUp.\(song.id)")
                                Button {
                                    moveSong(song.id, direction: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Move down")
                                .accessibilityIdentifier("editor.moveDown.\(song.id)")
                                Button("Edit song details") {
                                    editingSongID = song.id
                                    editTitle = song.title
                                    editKey = song.key ?? ""
                                    editTempo = song.tempo.map(String.init) ?? ""
                                    editCue = song.cues.first?.text ?? ""
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("editor.editSong.\(song.id)")
                            }
                        case .breakMarker(let marker):
                            HStack {
                                Image(systemName: "pause.circle.fill")
                                Text(marker.title).bold()
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .onDelete { indices in
                        var updated = show
                        updated.items.remove(atOffsets: indices)
                        if updated.currentSongID.map({ id in !updated.items.contains { $0.song?.id == id } }) == true {
                            updated.currentSongID = nil
                            updated.cursorIndex = nil
                        }
                        _ = save(updated)
                    }
                    .onMove { indices, newOffset in
                        var updated = show
                        updated.items.move(fromOffsets: indices, toOffset: newOffset)
                        _ = save(updated)
                    }
                }
            }
            .navigationTitle(show.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
            }
            .sheet(isPresented: Binding(
                get: { editingSongID != nil },
                set: { if !$0 { editingSongID = nil } }
            )) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $editTitle)
                            .accessibilityIdentifier("editor.songEditTitle")
                        TextField("Key", text: $editKey)
                            .accessibilityIdentifier("editor.songEditKey")
                        TextField("Tempo BPM", text: $editTempo)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("editor.songEditTempo")
                        TextField("Cue note", text: $editCue)
                            .accessibilityIdentifier("editor.songEditCue")
                    }
                    .navigationTitle("Edit song")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { editingSongID = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") { applySongEdit() }
                            .disabled(!ShowStore.validTitle(editTitle) || !validTempo(editTempo))
                            .accessibilityIdentifier("editor.songEditSave")
                        }
                    }
                }
            }
            .alert("Storage error", isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )) { Button("OK", role: .cancel) { storageError = nil } } message: {
                Text(storageError ?? "Unable to save show")
            }
        }
    }

    private func moveSong(_ id: UUID, direction: Int) {
        guard let index = show.items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard show.items.indices.contains(target) else { return }
        var updated = show
        updated.items.swapAt(index, target)
        _ = save(updated)
    }

    private func applySongEdit() {
        guard let id = editingSongID,
              let idx = show.items.firstIndex(where: { $0.song?.id == id }) else { return }
        let trimmedCue = editCue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cues = trimmedCue.isEmpty ? [] : [StageCue(text: trimmedCue)]
        let tempo = Int(editTempo.trimmingCharacters(in: .whitespacesAndNewlines))
        let key = editKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedSong = SongCard(
            id: id,
            title: editTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            key: key.isEmpty ? nil : key,
            tempo: tempo,
            cues: cues
        )
        var updated = show
        updated.items[idx] = .song(updatedSong)
        if save(updated) { editingSongID = nil }
    }

    /// Empty is valid (unknown tempo); otherwise must parse to a positive BPM.
    private func validTempo(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return (Int(trimmed).map { $0 > 0 }) ?? false
    }

    /// Persist a candidate; only adopt it into local state when the store
    /// accepts it, so failed validations never corrupt the on-screen show.
    @discardableResult
    private func save(_ candidate: Show) -> Bool {
        do {
            try store.save(candidate)
            show = candidate
            onSave()
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }
}
