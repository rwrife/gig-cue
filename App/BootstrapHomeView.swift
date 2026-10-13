import GigCueKit
import SwiftUI

struct BootstrapHomeView: View {
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
            }
            .padding(24)
            .navigationTitle("Home")
        }
        .accessibilityIdentifier("bootstrap.home")
    }
}
