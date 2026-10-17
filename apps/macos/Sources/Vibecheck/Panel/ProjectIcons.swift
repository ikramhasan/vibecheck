import AppKit
import CompanionCore
import SwiftUI

/// Project favicons/app icons, found once per repo and cached. Lookup runs off the
/// main thread; views re-render when an icon lands.
@MainActor
@Observable
final class ProjectIcons {
    static let shared = ProjectIcons()

    private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored let resolver = ProjectResolver()

    func project(for cwd: String) -> ProjectInfo { resolver.project(for: cwd) }

    func groups(_ sessions: [AgentSession]) -> [SessionGroup] {
        SessionGroup.make(sessions, project: resolver.project(for:))
    }

    /// The icon for a project root, or nil while loading / when there is none.
    func icon(for root: String) -> NSImage? {
        if !requested.contains(root) {
            requested.insert(root)
            Task.detached(priority: .utility) {
                let image = ProjectIconLocator.iconURLs(forProjectAt: root).lazy
                    .compactMap(NSImage.init(contentsOf:)).first(where: \.isValid)
                guard let image else { return }
                await MainActor.run { ProjectIcons.shared.icons[root] = image }
            }
        }
        return icons[root]
    }
}

/// Rounded project icon with a monogram fallback.
struct ProjectBadge: View {
    let project: ProjectInfo
    var size: CGFloat = 18
    @State private var icons = ProjectIcons.shared

    var body: some View {
        let radius = size * 0.28
        Group {
            if let image = icons.icon(for: project.root) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(project.monogram)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
