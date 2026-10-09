import Foundation

/// The project a session belongs to: the git repository its working directory is in.
/// Linked worktrees resolve to their main checkout so they share one group and icon.
public struct ProjectInfo: Hashable, Sendable {
    /// Grouping key: the repository root (or the directory itself outside git).
    public var root: String
    public var name: String

    public init(root: String, name: String) {
        self.root = root
        self.name = name
    }

    /// Two-letter fallback when a project has no icon: initials for multi-word names
    /// ("shop-web" → "SW", "AgentCompanion" → "AC"), else the first two letters ("Cl").
    public var monogram: String {
        let words = Self.words(in: name)
        if words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        }
        let letters = name.filter { $0.isLetter || $0.isNumber }
        guard let first = letters.first else { return "?" }
        return String(first).uppercased() + String(letters.dropFirst().prefix(1)).lowercased()
    }

    /// Splits on separators and lower→upper camel-case boundaries.
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for ch in name {
            if !(ch.isLetter || ch.isNumber) {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLower = false
                continue
            }
            if ch.isUppercase && previousWasLower, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(ch)
            previousWasLower = ch.isLowercase
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// Resolves working directories to projects by walking up to the nearest `.git`.
/// Pure filesystem reads, cached per directory; never runs git.
public final class ProjectResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let home: String
    private var cache: [String: ProjectInfo] = [:]
    private let lock = NSLock()

    public init(fileManager: FileManager = .default, home: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.home = home
    }

    public func project(for cwd: String) -> ProjectInfo {
        let path = (cwd as NSString).standardizingPath
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[path] { return hit }
        let info = resolve(path)
        cache[path] = info
        return info
    }

    private func resolve(_ path: String) -> ProjectInfo {
        var dir = path
        // A dotfiles repo at $HOME must not swallow every project under it.
        while dir != home {
            let git = (dir as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: git, isDirectory: &isDir) {
                let root = isDir.boolValue ? dir : (mainCheckout(gitFile: git) ?? dir)
                return ProjectInfo(root: root, name: displayName(root))
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return ProjectInfo(root: path, name: displayName(path))
    }

    /// A linked worktree's `.git` is a file: `gitdir: <main>/.git/worktrees/<name>`.
    private func mainCheckout(gitFile: String) -> String? {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitdir.hasPrefix("/") {
            gitdir = ((gitFile as NSString).deletingLastPathComponent as NSString).appendingPathComponent(gitdir)
        }
        let parts = (gitdir as NSString).standardizingPath.components(separatedBy: "/.git/worktrees/")
        // Submodules (`.git/modules/...`) and other layouts keep their own directory.
        return parts.count == 2 ? parts[0] : nil
    }

    private func displayName(_ path: String) -> String {
        path == home ? "~" : (path as NSString).lastPathComponent
    }
}

/// Finds a project's own icon (web favicon, app icon, logo) without scanning the tree.
public enum ProjectIconLocator {
    /// Checked in order; vector and large raster files first.
    static let candidates = [
        "favicon.svg", "public/favicon.svg", "static/favicon.svg", "app/icon.svg", "src/app/icon.svg",
        "public/apple-touch-icon.png", "app/apple-icon.png", "src/app/apple-icon.png",
        "app/icon.png", "src/app/icon.png", "public/icon.png", "public/logo.svg", "public/logo.png",
        "favicon.png", "public/favicon.png", "static/favicon.png", "src/assets/favicon.png",
        "favicon.ico", "public/favicon.ico", "static/favicon.ico", "app/favicon.ico", "src/app/favicon.ico",
        "src/favicon.ico", "web/favicon.png",
        "assets/icon.png", "assets/images/icon.png", "icon.png", "icon.svg", "logo.svg", "logo.png",
        ".github/icon.png", ".github/logo.png", "docs/logo.png",
    ]

    /// Directories (relative to the root) that commonly hold an Xcode/Flutter `AppIcon.appiconset`.
    static let assetCatalogParents = ["", "ios/Runner", "macos/Runner", "Resources", "Sources", "App"]

    public static func iconURL(forProjectAt root: String, fileManager: FileManager = .default) -> URL? {
        let base = URL(fileURLWithPath: root, isDirectory: true)
        for rel in candidates {
            let url = base.appending(path: rel)
            if isNonEmptyFile(url, fileManager) { return url }
        }
        return appIcon(in: base, fileManager: fileManager)
    }

    /// Largest PNG in the first `AppIcon.appiconset` found within two levels of the
    /// usual parents (e.g. `MyApp/Assets.xcassets/AppIcon.appiconset`).
    private static func appIcon(in base: URL, fileManager: FileManager) -> URL? {
        var catalogs: [URL] = []
        for parent in assetCatalogParents {
            let dir = parent.isEmpty ? base : base.appending(path: parent)
            catalogs += children(of: dir, fileManager).filter { $0.pathExtension == "xcassets" }
            for child in children(of: dir, fileManager) where child.hasDirectoryPath && !skip(child) {
                catalogs += children(of: child, fileManager).filter { $0.pathExtension == "xcassets" }
            }
        }
        for catalog in catalogs {
            let set = catalog.appending(path: "AppIcon.appiconset")
            let pngs = children(of: set, fileManager).filter { $0.pathExtension.lowercased() == "png" }
            if let best = pngs.max(by: { size($0, fileManager) < size($1, fileManager) }) { return best }
        }
        return nil
    }

    private static func skip(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || ["node_modules", "build", "dist", "Pods", "DerivedData", "vendor"].contains(name)
    }

    private static func children(of dir: URL, _ fm: FileManager) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles])) ?? []
    }

    private static func size(_ url: URL, _ fm: FileManager) -> Int {
        ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func isNonEmptyFile(_ url: URL, _ fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue && size(url, fm) > 0
    }
}

/// Sessions grouped by project for the expanded panel, most urgent first.
public struct SessionGroup: Identifiable, Hashable, Sendable {
    public var project: ProjectInfo
    public var sessions: [AgentSession]
    public var id: String { project.root }

    public init(project: ProjectInfo, sessions: [AgentSession]) {
        self.project = project
        self.sessions = sessions
    }

    /// Lower is more urgent.
    public static func urgency(_ status: AgentSession.Status) -> Int {
        switch status {
        case .needsAttention: 0
        case .error: 1
        case .working: 2
        case .idle: 3
        }
    }

    /// Groups keep the order of their most urgent session; ties keep the input order
    /// (the store sorts by start time), so lists don't reshuffle on every update.
    public static func make(_ sessions: [AgentSession], project: (String) -> ProjectInfo) -> [SessionGroup] {
        var order: [String] = []
        var groups: [String: SessionGroup] = [:]
        for s in sessions {
            let p = project(s.cwd)
            if groups[p.root] == nil { order.append(p.root); groups[p.root] = SessionGroup(project: p, sessions: []) }
            groups[p.root]!.sessions.append(s)
        }
        let rank: (AgentSession) -> Int = { urgency($0.status) }
        var result = order.compactMap { groups[$0] }
        for i in result.indices {
            result[i].sessions = stableSorted(result[i].sessions, by: rank)
        }
        return stableSorted(result) { $0.sessions.map(rank).min() ?? 3 }
    }

    private static func stableSorted<T>(_ items: [T], by key: (T) -> Int) -> [T] {
        items.enumerated().sorted { (key($0.element), $0.offset) < (key($1.element), $1.offset) }.map(\.element)
    }
}

/// Compact elapsed time for session lines: "now", "4m", "2h 5m", "3d".
public enum ElapsedFormat {
    public static func short(since date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d"
    }
}
