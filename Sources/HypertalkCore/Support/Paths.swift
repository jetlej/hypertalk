import Foundation

/// Where hypertalk keeps files on disk. User-authored config lives in
/// ~/.config/hypertalk; everything else lives under ~/Library. Never /tmp or
/// ~/Documents. Directories are owner-only (0700).
package enum Paths {
    /// `$XDG_CONFIG_HOME/hypertalk`, default `~/.config/hypertalk` — the files a user
    /// edits and may keep in dotfiles: settings and the dictionary.
    static var config: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("hypertalk", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/hypertalk", isDirectory: true)
    }

    /// `~/Library/Application Support/hypertalk` — model weights and tokenizers.
    /// Not Caches: the system purges that under disk pressure, which would
    /// mean a surprise multi-GB download.
    static var appSupport: URL { library("Application Support/hypertalk") }

    /// `~/Library/Logs/hypertalk` — the app's stdout/stderr.
    static var logs: URL { library("Logs/hypertalk") }

    /// `~/Library/Caches/hypertalk` — debug output such as `--dump-wav`.
    package static var caches: URL { library("Caches/hypertalk") }

    /// `settings.json` in `config`: preferences, read and written by `SettingsStore`.
    static var settingsFile: URL { config.appendingPathComponent("settings.json") }

    /// `dictionary` in `config`: the user's words and what each replaces, a
    /// plain-text table. No extension, so it reads as a name, not a format.
    static var dictionaryFile: URL { config.appendingPathComponent("dictionary") }

    /// `dictionary.json` in `config`: the old format, converted once at
    /// startup by `DictionaryMigration`.
    static var legacyDictionaryFile: URL { config.appendingPathComponent("dictionary.json") }

    /// The app's stdout.
    static var daemonOutLog: URL { logs.appendingPathComponent("hypertalk.out.log") }

    /// The app's stderr.
    static var daemonErrLog: URL { logs.appendingPathComponent("hypertalk.err.log") }

    /// Where `--dump-wav` writes the most recent capture.
    package static var dumpWav: URL { caches.appendingPathComponent("last-capture.wav") }

    /// `~/Library/LaunchAgents/<label>.plist`.
    static func launchAgentPlist(label: String) -> URL {
        library("LaunchAgents").appendingPathComponent("\(label).plist")
    }

    /// The LaunchAgent that started pre-app versions at login. The app
    /// removes it; `SMAppService` replaced it.
    static var legacyLaunchAgentPlist: URL { launchAgentPlist(label: legacyLaunchAgentLabel) }

    /// The old LaunchAgent's label.
    static let legacyLaunchAgentLabel = "com.digimata.parrot"

    /// Where the `hypertalk` command lives on `PATH`: a symlink to the executable
    /// inside Hypertalk.app, or a plain binary from a pre-app install.
    static let commandLineLink = URL(fileURLWithPath: "/usr/local/bin/hypertalk")

    /// Held with `flock` by the running dictation loop, so the app and a
    /// foreground `hypertalk` never both listen to the hotkey. In Application
    /// Support, not Caches, because `hypertalk install --uninstall` removes Caches.
    static var instanceLock: URL { appSupport.appendingPathComponent("hypertalk.lock") }

    /// `~/Documents`. The model cache must not resolve under it.
    static var documents: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    /// Pre-0.0.6 files that held transcripts and audio in world-readable /tmp.
    static let legacyTmpFiles = ["/tmp/parrot.out.log", "/tmp/parrot.err.log", "/tmp/parrot-last.wav"]

    /// Pre-0.0.6 model cache: swift-transformers' default download base,
    /// shared with other apps. The launchd daemon can't read ~/Documents, so
    /// only foreground commands may touch it.
    static var legacyModels: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/huggingface", isDirectory: true)
    }

    /// Creates `dir` if needed and restricts it to the owner. Refuses a path
    /// that exists but isn't a real directory (e.g. a symlink).
    @discardableResult
    package static func prepareDirectory(_ dir: URL) throws -> URL {
        let fm = FileManager.default
        if let type = fileType(dir.path) {
            guard type == .typeDirectory else { throw PathError.notADirectory(dir.path) }
        } else {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Creates `file` empty at 0600 if missing, or tightens an existing one.
    /// Refuses a symlink or anything else that isn't a regular file.
    @discardableResult
    package static func preparePrivateFile(_ file: URL) throws -> URL {
        let fm = FileManager.default
        if let type = fileType(file.path) {
            guard type == .typeRegular else { throw PathError.notARegularFile(file.path) }
        } else {
            // O_EXCL | O_NOFOLLOW: never write through a link planted after the check.
            let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw PathError.notARegularFile(file.path) }
            close(fd)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    /// The type of the item at `path` without following symlinks, or nil if
    /// nothing is there.
    static func fileType(_ path: String) -> FileAttributeType? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.type] as? FileAttributeType
    }

    private static func library(_ sub: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(sub, isDirectory: true)
    }
}

enum PathError: Error, CustomStringConvertible {
    case notADirectory(String)
    case notARegularFile(String)

    var description: String {
        switch self {
        case .notADirectory(let p): return "\(p) exists but is not a directory"
        case .notARegularFile(let p): return "\(p) is a symlink or not a regular file"
        }
    }
}
