import AppKit
import CompanionCore
import WebKit

@MainActor
final class DiffWindowController: NSObject, NSWindowDelegate, WKScriptMessageHandler {
    private let diffs: DiffStatsStore
    private let window: NSWindow
    private let webView: WKWebView
    private var ready = false
    private var session: AgentSession?
    private var projectName = ""
    private var pending: [FilePatch]?
    private var loading = false
    private var loadAgain = false

    init?(diffs: DiffStatsStore) {
        guard let root = Self.viewerDirectory() else { return nil }
        self.diffs = diffs
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DiffViewerScheme(root: root), forURLScheme: DiffViewerScheme.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        configuration.userContentController.add(self, name: "vibecheck")
        window.contentView = webView
        window.contentMinSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("DiffWindow")
        webView.load(URLRequest(url: URL(string: "\(DiffViewerScheme.scheme)://viewer/index.html")!))
    }

    func show(_ session: AgentSession, project: ProjectInfo) {
        if self.session?.id != session.id { reset() }
        self.session = session
        window.title = StatusPresentation.headline(session)
        projectName = project.name
        window.subtitle = "\(project.name) · changes since the session started"
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        refresh()
        observe()
    }

    func windowWillClose(_ notification: Notification) {
        session = nil
        reset()
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            ready = true
            if let pending { send(pending) }
            pending = nil
        }
    }

    private func observe() {
        guard let id = session?.id else { return }
        _ = withObservationTracking { diffs.revisions[id] } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.session?.id == id else { return }
                self.refresh()
                self.observe()
            }
        }
    }

    private func refresh() {
        guard let session else { return }
        guard !loading else { loadAgain = true; return }
        loading = true
        Task {
            let patches = await diffs.patches(for: session)
            let comparison = await diffs.comparison(for: session)
            loading = false
            if self.session?.id == session.id {
                if let patches { send(patches) }
                if let comparison {
                    window.subtitle = "\(projectName) · " + comparison.summary(since: comparison.since.map(Self.format))
                }
            }
            if loadAgain {
                loadAgain = false
                refresh()
            }
        }
    }

    private func send(_ patches: [FilePatch]) {
        guard ready else { pending = patches; return }
        let files = patches.map { ["patch": $0.patch, "untracked": $0.untracked] as [String: Any] }
        webView.callAsyncJavaScript("vibecheck.show({ files })", arguments: ["files": files], in: nil, in: .page)
    }

    private func reset() {
        pending = nil
        guard ready else { return }
        webView.callAsyncJavaScript("vibecheck.reset()", arguments: [:], in: nil, in: .page)
    }

    private static func format(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private static func viewerDirectory() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appending(path: "DiffViewer"),
           fm.fileExists(atPath: bundled.appending(path: "index.html").path) {
            return bundled
        }
        #if DEBUG
        let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "vendor/diff-viewer")
        if fm.fileExists(atPath: vendor.appending(path: "index.html").path) { return vendor }
        #endif
        return nil
    }
}

final class DiffViewerScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "vibecheck"
    private let root: URL

    init(root: URL) { self.root = root.standardizedFileURL }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.path ?? ""
        let file = root.appending(path: path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.mimeType(file.pathExtension),
                                                      "Content-Length": String(data.count)])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private static func mimeType(_ ext: String) -> String {
        switch ext {
        case "html": "text/html; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "wasm": "application/wasm"
        case "json": "application/json"
        default: "application/octet-stream"
        }
    }
}
