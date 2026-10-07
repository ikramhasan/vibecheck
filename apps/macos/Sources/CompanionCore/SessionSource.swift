import Foundation

/// Anything that can discover live agent sessions.
///
/// Most agents never need their own source: they report through the shared
/// status-file contract (`integrations/core`), which `StatusDirectorySource` reads.
/// Implement this only for an agent that can't run a reporter and has to be
/// observed some other way (e.g. by tailing its own log files).
@MainActor
public protocol SessionSource: AnyObject {
    /// Called with the source's complete current set whenever it changes.
    var onChange: (([AgentSession]) -> Void)? { get set }
    func start()
    func stop()
}
