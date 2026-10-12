import CoreServices
import Foundation

@MainActor
final class CheckoutWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(checkout: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let watcher = Unmanaged<CheckoutWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.received(paths.prefix(count)) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [checkout] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func received(_ paths: ArraySlice<String>) {
        if paths.contains(where: { !Self.isInsideGitDirectory($0) }) { onChange() }
    }

    nonisolated static func isInsideGitDirectory(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }
}
