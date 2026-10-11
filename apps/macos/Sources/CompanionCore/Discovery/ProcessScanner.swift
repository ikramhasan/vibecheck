import Darwin
import Foundation

public struct ProcessSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var arguments: [String]
    public var environment: [String: String]
    public var cwd: String?
    public var tty: String?
    public var startedAt: Date

    public init(pid: Int32, name: String, arguments: [String] = [], environment: [String: String] = [:],
                cwd: String? = nil, tty: String? = nil, startedAt: Date = .distantPast) {
        self.pid = pid
        self.name = name
        self.arguments = arguments
        self.environment = environment
        self.cwd = cwd
        self.tty = tty
        self.startedAt = startedAt
    }

    public var origin: AgentSession.Origin? {
        let bundleId = environment["__CFBundleIdentifier"]
        let termProgram = environment["TERM_PROGRAM"]
        guard bundleId != nil || termProgram != nil else { return nil }
        return .init(bundleId: bundleId, termProgram: termProgram)
    }
}

public enum ProcessScanner {
    public static func processes(named names: Set<String>) -> [ProcessSnapshot] {
        let uid = getuid()
        return allPIDs().compactMap { pid in
            guard let info = bsdInfo(pid), info.pbi_uid == uid else { return nil }
            let name = cString(info.pbi_comm)
            guard names.contains(name) else { return nil }
            return snapshot(pid: pid, info: info, name: name)
        }
    }

    public static func snapshot(pid: Int32) -> ProcessSnapshot? {
        guard let info = bsdInfo(pid) else { return nil }
        return snapshot(pid: pid, info: info, name: cString(info.pbi_comm))
    }

    public static func openFiles(pid: Int32) -> [String] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard filled > 0 else { return [] }
        return fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride).compactMap { fd in
            guard fd.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            var info = vnode_fdinfowithpath()
            let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, infoSize) == infoSize else { return nil }
            return cString(info.pvip.vip_path)
        }
    }

    public static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        bsdInfo(pid).map { Int32($0.pbi_ppid) }
    }

    private static func snapshot(pid: Int32, info: proc_bsdinfo, name: String) -> ProcessSnapshot {
        let (arguments, environment) = argumentsAndEnvironment(pid)
        return ProcessSnapshot(pid: pid, name: name, arguments: arguments, environment: environment,
                               cwd: cwd(pid), tty: tty(info.e_tdev),
                               startedAt: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)))
    }

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(filled, 0)))).filter { $0 > 0 }
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = cString(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    private static func tty(_ device: UInt32) -> String? {
        guard device != UInt32.max, device != 0, let name = devname(dev_t(bitPattern: device), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func argumentsAndEnvironment(_ pid: Int32) -> ([String], [String: String]) {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ([], [:]) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return ([], [:]) }
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var strings = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: false)[...]
        _ = strings.popFirst()
        while strings.first?.isEmpty == true { _ = strings.popFirst() }
        let arguments = strings.prefix(argc).map { String(decoding: $0, as: UTF8.self) }
        var environment: [String: String] = [:]
        for raw in strings.dropFirst(argc) where !raw.isEmpty {
            let entry = String(decoding: raw, as: UTF8.self)
            guard let eq = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return (arguments, environment)
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
