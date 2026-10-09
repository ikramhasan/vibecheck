import Foundation
import Testing
@testable import CompanionCore

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ac-projects-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func touch(_ url: URL, _ contents: String = "x") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func session(_ id: String, _ cwd: String, _ status: AgentSession.Status) -> AgentSession {
    AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: id, cwd: cwd, status: status)
}

@Suite struct ProjectResolverTests {
    @Test func subdirectoryResolvesToRepoRoot() throws {
        let root = try tempDir()
        let repo = root.appending(path: "shop-web")
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appending(path: "src/app"), withIntermediateDirectories: true)

        let p = ProjectResolver(home: root.path).project(for: repo.appending(path: "src/app").path)
        #expect(p.root == repo.path)
        #expect(p.name == "shop-web")
    }

    @Test func linkedWorktreeResolvesToMainCheckout() throws {
        let root = try tempDir()
        let main = root.appending(path: "AgentCompanion")
        try FileManager.default.createDirectory(at: main.appending(path: ".git/worktrees/feature"),
                                                withIntermediateDirectories: true)
        let worktree = root.appending(path: "wt/feature")
        try touch(worktree.appending(path: ".git"), "gitdir: \(main.path)/.git/worktrees/feature\n")

        let p = ProjectResolver(home: root.path).project(for: worktree.path)
        #expect(p.root == main.path)
        #expect(p.name == "AgentCompanion")
    }

    @Test func outsideGitUsesTheDirectoryAndStopsAtHome() throws {
        let home = try tempDir()
        try FileManager.default.createDirectory(at: home.appending(path: ".git"), withIntermediateDirectories: true)
        let dir = home.appending(path: "scratch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let p = ProjectResolver(home: home.path).project(for: dir.path)
        #expect(p.root == dir.path)
        #expect(p.name == "scratch")
    }

    @Test func monograms() {
        #expect(ProjectInfo(root: "/a", name: "shop-web").monogram == "SW")
        #expect(ProjectInfo(root: "/a", name: "AgentCompanion").monogram == "AC")
        #expect(ProjectInfo(root: "/a", name: "cli").monogram == "Cl")
        #expect(ProjectInfo(root: "/a", name: "~").monogram == "?")
    }
}

@Suite struct ProjectIconLocatorTests {
    @Test func prefersVectorFavicon() throws {
        let root = try tempDir()
        try touch(root.appending(path: "public/favicon.ico"))
        try touch(root.appending(path: "public/favicon.svg"))
        #expect(ProjectIconLocator.iconURL(forProjectAt: root.path)?.lastPathComponent == "favicon.svg")
    }

    @Test func findsLargestAppIcon() throws {
        let root = try tempDir()
        let set = root.appending(path: "MyApp/Assets.xcassets/AppIcon.appiconset")
        try touch(set.appending(path: "small.png"), "x")
        try touch(set.appending(path: "large.png"), String(repeating: "x", count: 100))
        #expect(ProjectIconLocator.iconURL(forProjectAt: root.path)?.lastPathComponent == "large.png")
    }

    @Test func noIcon() throws {
        let root = try tempDir()
        try touch(root.appending(path: "README.md"))
        #expect(ProjectIconLocator.iconURL(forProjectAt: root.path) == nil)
    }
}

@Suite struct SessionGroupTests {
    @Test func groupsByProjectMostUrgentFirst() {
        let sessions = [
            session("1", "/p/a", .working),
            session("2", "/p/b", .idle),
            session("3", "/p/b", .needsAttention),
            session("4", "/p/c", .working),
        ]
        let groups = SessionGroup.make(sessions) { ProjectInfo(root: $0, name: ($0 as NSString).lastPathComponent) }
        #expect(groups.map(\.project.name) == ["b", "a", "c"])
        #expect(groups[0].sessions.map(\.sessionID) == ["3", "2"])
    }
}

@Suite struct ElapsedFormatTests {
    @Test func formats() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(ElapsedFormat.short(since: now.addingTimeInterval(-20), now: now) == "now")
        #expect(ElapsedFormat.short(since: now.addingTimeInterval(-4 * 60), now: now) == "4m")
        #expect(ElapsedFormat.short(since: now.addingTimeInterval(-125 * 60), now: now) == "2h 5m")
        #expect(ElapsedFormat.short(since: now.addingTimeInterval(-120 * 60), now: now) == "2h")
        #expect(ElapsedFormat.short(since: now.addingTimeInterval(-3 * 86400), now: now) == "3d")
    }
}

@MainActor
@Suite struct StatusSinceTests {
    @Test func keptWhileStatusUnchangedResetOnChange() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let source = ManualSource()
        let store = SessionStore(sources: [source])
        source.emit([AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/", status: .working, updatedAt: t0)])
        source.emit([AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/", status: .working,
                                  activity: "Reading", updatedAt: t0.addingTimeInterval(30))])
        #expect(store.sessions[0].statusSince == t0)
        source.emit([AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/", status: .idle,
                                  updatedAt: t0.addingTimeInterval(90))])
        #expect(store.sessions[0].statusSince == t0.addingTimeInterval(90))
    }
}

@MainActor
private final class ManualSource: SessionSource {
    var onChange: (([AgentSession]) -> Void)?
    func start() {}
    func stop() {}
    func emit(_ s: [AgentSession]) { onChange?(s) }
}
