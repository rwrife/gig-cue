import SwiftUI

/// Composition seam for the performance workspace.
///
/// Today this is a standard single-screen iPhone layout: the primary song
/// deck on top and the persistent one-thumb control deck below it, both
/// kept in the same accessibility container so VoiceOver traversal order
/// matches the visual order (current song → next cue → controls).
///
/// Design target (planned iPhone Duo only): when the platform exposes
/// display topology, the same `primary` and `deck` content routes to two
/// screens — full song/order detail plus a persistent high-contrast
/// control deck. No fold SDK APIs exist today and none are referenced
/// here; native iPad support stays disabled (`TARGETED_DEVICE_FAMILY = 1`).
struct GigWorkspaceLayout<Primary: View, Deck: View>: View {
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var deck: () -> Deck

    var body: some View {
        VStack(spacing: 20) {
            primary()
            Spacer(minLength: 12)
            deck()
        }
        .accessibilityElement(children: .contain)
    }
}
