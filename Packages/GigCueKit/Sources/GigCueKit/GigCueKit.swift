/// GigCueKit — pure-domain core for Gig Cue.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 (domain) lands the Show/SongCard/StageCue/BreakMarker
/// models with unique identities and deterministic reorder round-trips,
/// the unknown-safe key/tempo handling, and the versioned atomic Codable
/// JSON persistence contract here. The stage navigation reducer arrives
/// with issue #3.
public enum GigCueKit {
    /// Namespace marker for the domain layer.
    public static let domain = "GigCueKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M0-skeleton"
}
