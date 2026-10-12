import Foundation

/// Git on another machine, asked through that machine's `RemoteSessionSource`.
public struct RemoteGit: GitReading {
    let source: RemoteSessionSource

    public func run(_ query: GitQuery, in checkout: String) async -> GitOutput? {
        let (op, argument): (String, String) = switch query {
        case .toplevel: ("toplevel", "")
        case .branch: ("branch", "")
        case .head: ("head", "")
        case .reflog(let seconds): ("reflog", "\(seconds)")
        case .before(let seconds): ("before", "\(seconds)")
        case .numstat(let baseline): ("numstat", baseline)
        case .untracked: ("untracked", "")
        case .isAncestor(let baseline): ("ancestor", baseline)
        case .patch(let baseline): ("patch", baseline)
        }
        return await source.query(op, in: checkout, argument: argument)
    }

    public func contents(of path: String, in checkout: String) async -> Data? {
        guard let output = await source.query("file", in: checkout, argument: path), output.status == 0 else { return nil }
        return output.stdout
    }
}
