import Foundation

/// Runs `body` on the main actor, from wherever the caller happens to be.
///
/// Use this — not `MainActor.assumeIsolated` — for anything a run loop can call
/// back into: timers, and event monitors.
///
/// `assumeIsolated` is an assertion, and the assumption behind it does not hold
/// in this app. `NSAppleScript` is executed off the main thread on purpose, since
/// a blocked Apple Event can take seconds and must not freeze the panel. While it
/// waits for the reply, AppleScript pumps a nested Carbon event loop on the
/// sending thread, and that loop services the *main* run loop's timers — so a
/// `Timer` added to `RunLoop.main` can be delivered on a background thread for as
/// long as an Apple Event is in flight. `assumeIsolated` then traps, taking the
/// whole app with it.
///
/// Hopping is correct in a way that asserting is not: the work lands on the main
/// queue, properly serialised against everything else on the main actor.
func onMainActor(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated(body) }
}
