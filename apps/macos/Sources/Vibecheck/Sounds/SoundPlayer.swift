import AppKit
import CompanionCore

@MainActor
enum SoundPlayer {
    private static let directories: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Sounds"),
        URL(filePath: "/Library/Sounds"),
        URL(filePath: "/System/Library/Sounds"),
    ]

    private static let extensions: Set<String> = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]

    static let available: [String] = {
        let names = directories.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    static func play(_ name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.volume = Float(volume)
        sound.play()
    }

    static func play(_ event: SoundEvent, settings: SoundSettings) {
        guard let name = settings.sound(for: event) else { return }
        play(name, volume: settings.volume)
    }
}
