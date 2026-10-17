import Foundation

/// The project a session belongs to: the git repository its working directory is in.
/// Linked worktrees resolve to their main checkout so they share one group and icon.
public struct ProjectInfo: Hashable, Sendable {
    /// Grouping key: the repository root (or the directory itself outside git).
    public var root: String
    public var name: String
    /// The ssh host the project lives on; `nil` for this Mac.
    public var host: String?

    public init(root: String, name: String, host: String? = nil) {
        self.root = root
        self.name = name
        self.host = host
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

    public func checkout(for path: String) -> String {
        repository(for: path) ?? (path as NSString).standardizingPath
    }

    public func repository(for path: String) -> String? {
        gitDirectory(above: (path as NSString).standardizingPath).map { ($0 as NSString).deletingLastPathComponent }
    }

    public func mainCheckoutPath(for path: String) -> String {
        Self.relocate(path, from: checkout(for: path), to: project(for: path).root)
    }

    public func path(_ path: String, inCheckout target: String) -> String {
        Self.relocate(path, from: checkout(for: path), to: (target as NSString).standardizingPath)
    }

    static func relocate(_ path: String, from source: String, to target: String) -> String {
        let path = (path as NSString).standardizingPath
        guard path == source || path.hasPrefix(source + "/") else { return path }
        return target + path.dropFirst(source.count)
    }

    private func resolve(_ path: String) -> ProjectInfo {
        guard let git = gitDirectory(above: path) else { return ProjectInfo(root: path, name: displayName(path)) }
        let dir = (git as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: git, isDirectory: &isDir)
        let root = isDir.boolValue ? dir : (mainCheckout(gitFile: git) ?? dir)
        return ProjectInfo(root: root, name: displayName(root))
    }

    private func gitDirectory(above path: String) -> String? {
        var dir = path
        // A dotfiles repo at $HOME must not swallow every project under it.
        while dir != home {
            let git = (dir as NSString).appendingPathComponent(".git")
            if fileManager.fileExists(atPath: git) { return git }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { return nil }
            dir = parent
        }
        return nil
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

/// Finds a project's own icon (favicon, app icon, logo) anywhere in its tree, so monorepos
/// (`apps/web/app/icon.png`), Xcode/Flutter/Tauri/Android apps and plain websites all match.
/// Walks breadth-first within a fixed budget, skipping dependencies, build output and simple
/// names from the root `.gitignore`.
public enum ProjectIconLocator {
    static let maxDepth = 6
    static let maxDirectories = 3000

    static let skippedDirectories: Set<String> = [
        "node_modules", "bower_components", "vendor", "Pods", "Carthage", "DerivedData",
        "build", "dist", "out", "target", "coverage", "tmp",
        "test", "tests", "__tests__", "spec", "fixtures", "Fixtures", "example", "examples", "samples",
    ]

    enum Kind: Int, Comparable {
        case vector, appIcon, raster, ico, logo
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public static func iconURLs(forProjectAt root: String, fileManager: FileManager = .default) -> [URL] {
        let base = URL(fileURLWithPath: root, isDirectory: true)
        let skipped = skippedDirectories.union(gitIgnoredNames(in: base))
        let depthLimit = fileManager.fileExists(atPath: base.appending(path: ".git").path) ? maxDepth : 0
        var found: [(kind: Kind, depth: Int, bytes: Int, url: URL)] = []
        var queue: [(dir: URL, depth: Int)] = [(base, 0)]
        var next = 0
        while next < queue.count, next < maxDirectories {
            let (dir, depth) = queue[next]
            next += 1
            for child in children(of: dir, fileManager) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                let name = child.lastPathComponent
                if values?.isDirectory == true {
                    if depth < depthLimit, !skipped.contains(name), !name.hasPrefix(".") || name == ".github" {
                        queue.append((child, depth + 1))
                    }
                    continue
                }
                guard values?.isRegularFile == true, let bytes = values?.fileSize, bytes > 0,
                      let kind = kind(of: child) else { continue }
                found.append((kind, depth, bytes, child))
            }
        }
        return found.sorted { ($0.kind, $0.depth, -$0.bytes) < ($1.kind, $1.depth, -$1.bytes) }.map(\.url)
    }

    static func kind(of url: URL) -> Kind? {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let folder = url.deletingLastPathComponent().lastPathComponent
        switch name {
        case "favicon.svg", "icon.svg": return .vector
        case "apple-icon.png", "apple-touch-icon.png", "icon-512.png", "icon-512x512.png",
             "android-chrome-512x512.png": return .appIcon
        case "icon.png", "favicon.png", "icon-192.png", "android-chrome-192x192.png": return .raster
        case "favicon.ico", "icon.ico": return .ico
        case "logo.svg", "logo.png": return .logo
        default: break
        }
        if ext == "icns" { return .appIcon }
        if ext == "png", folder.hasPrefix("AppIcon"), folder.hasSuffix(".appiconset") { return .appIcon }
        if name == "ic_launcher.png", folder.hasPrefix("mipmap-") { return .appIcon }
        return nil
    }

    static func gitIgnoredNames(in base: URL) -> Set<String> {
        guard let text = try? String(contentsOf: base.appending(path: ".gitignore"), encoding: .utf8) else { return [] }
        var names: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            var entry = line.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty || entry.hasPrefix("#") || entry.hasPrefix("!") { continue }
            if entry.hasPrefix("/") { entry.removeFirst() }
            if entry.hasSuffix("/") { entry.removeLast() }
            if entry.isEmpty || entry.contains(where: { "/*?[".contains($0) }) { continue }
            names.insert(entry)
        }
        return names
    }

    private static func children(of dir: URL, _ fm: FileManager) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])) ?? []
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

    /// Groups keep the order of their most urgent session; ties keep the input order
    /// (the store sorts by start time), so lists don't reshuffle on every update.
    public static func make(_ sessions: [AgentSession], project: (String) -> ProjectInfo) -> [SessionGroup] {
        var order: [String] = []
        var groups: [String: SessionGroup] = [:]
        for s in sessions {
            let p = s.host.map { host in
                let root = s.remoteCheckout ?? s.cwd
                return ProjectInfo(root: "\(host):\(root)", name: (root as NSString).lastPathComponent, host: host)
            } ?? project(s.cwd)
            if groups[p.root] == nil { order.append(p.root); groups[p.root] = SessionGroup(project: p, sessions: []) }
            groups[p.root]!.sessions.append(s)
        }
        let rank: (AgentSession) -> Int = { StatusPresentation($0).urgency }
        var result = order.compactMap { groups[$0] }
        for i in result.indices {
            result[i].sessions = stableSorted(result[i].sessions, by: rank)
        }
        return stableSorted(result) { $0.sessions.map(rank).min() ?? StatusPresentation.leastUrgent }
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
