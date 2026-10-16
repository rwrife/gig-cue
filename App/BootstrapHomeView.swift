import GigCueKit
import SwiftUI

struct BootstrapHomeView: View {
    @State private var activeShow: Show?
    @State private var storageError: String?
    private let store = ShowStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Gig Cue")
                        .font(.largeTitle.bold())
                    Text("An offline stage setlist and cue companion for one-thumb performance navigation.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Native iPhone foundation is ready", systemImage: "checkmark.circle")
                        Text("Reorderable setlists, restart-safe stage progress, and high-contrast performance mode land in the next milestones.")
                            .foregroundStyle(.secondary)
                        Text("Domain core milestone: \(GigCueKit.milestone).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: openSampleStage) {
                    Label("Enter stage mode", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("stage.enter")
            }
            .padding(24)
            .navigationTitle("Home")
            .navigationDestination(item: $activeShow) { show in
                StageModeView(initialShow: show, store: store)
            }
            .alert("Storage error", isPresented: Binding(
                get: { storageError != nil },
                set: { if !$0 { storageError = nil } }
            )) { Button("OK", role: .cancel) { storageError = nil } } message: {
                Text(storageError ?? "Unable to save show")
            }
        }
        .accessibilityIdentifier("bootstrap.home")
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

struct StageModeView: View {
    @State private var flow: StageFlow
    @State private var storageError: String?
    private let store: ShowStore

    init(initialShow: Show, store: ShowStore) {
        _flow = State(initialValue: StageFlow(show: initialShow))
        self.store = store
    }

    var body: some View {
        VStack(spacing: 20) {
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
                .background(Color(.secondarySystemBackground))
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
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let next = flow.next {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    switch next {
                    case .song(let song): Text(song.title).font(.title3.bold())
                    case .breakMarker(let marker): Label(marker.title, systemImage: "pause.circle").font(.title3.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stage.nextCard")
            }
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
                .accessibilityIdentifier("stage.nextButton")
            }
        }
        .padding()
        .navigationTitle(flow.show.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Storage error", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) { Button("OK", role: .cancel) { storageError = nil } } message: {
            Text(storageError ?? "Unable to save stage progress")
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
