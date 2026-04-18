import Foundation

// MARK: - FileLogger

final class FileLogger: @unchecked Sendable {

    static let shared = FileLogger()

    enum Level: String {
        case debug = "DEBUG"
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "com.copysmith.logger", qos: .utility)
    private let logDir: URL
    private let maxFileSize = 1 * 1024 * 1024  // 1 MB
    private let maxFiles    = 5
    private var fileHandle: FileHandle?

    // DateFormatter is not thread-safe; access only from `queue`.
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CopySmith")
        queue.sync { self.setup() }
    }

    // MARK: Public API

    func log(_ level: Level, _ component: String, _ message: String) {
        queue.async { [self] in
            let ts   = formatter.string(from: Date())
            let line = "[\(ts)] [\(level.rawValue)] [\(component)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            rollIfNeeded()
            fileHandle?.write(data)
        }
    }

    // MARK: Private

    private func setup() {
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        openFile()
        let line = String(repeating: "-", count: 72) + "\n"
        fileHandle?.write(line.data(using: .utf8)!)
    }

    private func currentURL() -> URL {
        logDir.appendingPathComponent("copysmith.log")
    }

    private func openFile() {
        let url = currentURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    private func rollIfNeeded() {
        guard let size = try? currentURL().resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= maxFileSize else { return }

        fileHandle?.closeFile()
        fileHandle = nil

        let fm = FileManager.default
        // Drop oldest archive
        try? fm.removeItem(at: logDir.appendingPathComponent("copysmith-\(maxFiles).log"))
        // Shift archives: N-1 → N … 1 → 2
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let src = logDir.appendingPathComponent("copysmith-\(i).log")
            let dst = logDir.appendingPathComponent("copysmith-\(i + 1).log")
            try? fm.moveItem(at: src, to: dst)
        }
        // Current → archive 1
        try? fm.moveItem(at: currentURL(), to: logDir.appendingPathComponent("copysmith-1.log"))

        openFile()
    }
}

// MARK: - Convenience level methods

extension FileLogger {
    func debug(_ component: String, _ message: String) { log(.debug, component, message) }
    func info (_ component: String, _ message: String) { log(.info,  component, message) }
    func warn (_ component: String, _ message: String) { log(.warn,  component, message) }
    func error(_ component: String, _ message: String) { log(.error, component, message) }
}

// MARK: - Module-level shorthand

let log = FileLogger.shared
