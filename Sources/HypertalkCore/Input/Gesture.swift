import Foundation

/// Turns hotkey edges into dictation actions (ADR-003). Pure, so the rules
/// are tested without an event tap.
///
/// The tap sees modifier changes only, so it cannot see the C in ⌘C. Two
/// rules keep a shortcut typed on the hotkey from producing text:
/// - A hold shorter than `minimumHold` is discarded without transcribing.
/// - A recording is cancelled if another modifier changes while the hotkey
///   is held, and a press while another modifier is already held does not
///   record. Either way the rest of that hold is ignored.
///
/// Recording still starts on key-down, so press latency is unchanged; a
/// discarded hold just throws its audio away.
///
/// Double-tap to lock: a tap, then a second press within `doubleTapWindow`,
/// keeps recording after the key is let go. The next press of the hotkey
/// stops it and transcribes. A second press held past `minimumHold` is an
/// ordinary hold instead.
struct Gesture {
    /// Holds shorter than this are taps or shortcuts, not dictation.
    static let minimumHold: TimeInterval = 0.3
    /// The longest gap from a tap's release to the next press that still
    /// counts as a double tap.
    static let doubleTapWindow: TimeInterval = 0.4

    /// Whether a double tap locks the recording on.
    var lockEnabled = true

    enum Input: Equatable {
        /// The hotkey went down. `othersHeld`: another modifier was already
        /// down, so this is a chord.
        case hotkeyDown(othersHeld: Bool)
        /// The hotkey went up.
        case hotkeyUp
        /// Another modifier changed while the hotkey was down.
        case otherModifier
    }

    enum Action: Equatable {
        /// Start recording.
        case start
        /// Stop recording and transcribe.
        case transcribe
        /// Stop recording and discard it.
        case cancel
        /// The key was let go but recording continues until the next press.
        case lock
    }

    private enum Phase: Equatable {
        case idle
        /// Recording since this time. `locking`: this press followed a tap,
        /// so a short hold locks instead of discarding.
        case recording(since: TimeInterval, locking: Bool)
        /// Recording with the key up, until the next press.
        case locked
        /// The hotkey is down but this hold is a chord: ignore it until release.
        case ignoring
    }

    private var phase: Phase = .idle
    /// When the last discarded tap was released, for double-tap detection.
    private var lastTapUp: TimeInterval?

    /// Whether the hotkey is down, as far as the edges seen so far say.
    var isHeld: Bool {
        switch phase {
        case .idle, .locked: return false
        case .recording, .ignoring: return true
        }
    }

    /// Whether a recording is running with the key up.
    var isLocked: Bool { phase == .locked }

    /// Feed one edge at `time` (seconds on a monotonic clock).
    mutating func handle(_ input: Input, at time: TimeInterval) -> Action? {
        switch (phase, input) {
        case (.idle, .hotkeyDown(let othersHeld)):
            let tapUp = lastTapUp
            lastTapUp = nil
            if othersHeld {
                phase = .ignoring
                return nil
            }
            let locking = lockEnabled && tapUp.map { time - $0 <= Self.doubleTapWindow } == true
            phase = .recording(since: time, locking: locking)
            return .start
        case (.recording(let since, let locking), .hotkeyUp):
            guard time - since < Self.minimumHold else {
                phase = .idle
                return .transcribe
            }
            if locking {
                phase = .locked
                return .lock
            }
            phase = .idle
            lastTapUp = time
            return .cancel
        case (.locked, .hotkeyDown):
            // Ignore this press's release, like a chord's.
            phase = .ignoring
            return .transcribe
        case (.recording, .otherModifier):
            phase = .ignoring
            return .cancel
        case (.ignoring, .hotkeyUp):
            phase = .idle
            return nil
        default:
            // A repeated down, an up with no down seen, or a modifier change
            // outside a recording.
            return nil
        }
    }

    /// Forget the current hold, for a switch to another key. A recording in
    /// progress is cancelled.
    mutating func reset() -> Action? {
        defer {
            phase = .idle
            lastTapUp = nil
        }
        switch phase {
        case .recording, .locked: return .cancel
        case .idle, .ignoring: return nil
        }
    }
}
