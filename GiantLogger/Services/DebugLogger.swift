import Foundation

/// Simple file-based debug logger for BLE/GEV diagnostics.
/// Writes timestamped lines to a `.log` file in the app's documents directory
/// so logs can be captured on-device and exported later.
final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dk.hilli.GiantLogger.debuglog")
    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    /// Whether debug logging is active (persisted in UserDefaults)
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "debugLogEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "debugLogEnabled") }
    }

    private init() {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        fileURL = docs.appendingPathComponent("giant-debug.log")
    }

    /// Append a timestamped log line (no-op when disabled).
    func log(_ category: String, _ message: String) {
        guard isEnabled else { return }
        let date = Date()
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: date)
            let line = "[\(timestamp)] [\(category)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    /// URL of the log file for sharing.
    var logFileURL: URL { fileURL }

    /// Size of the current log file in bytes.
    var logFileSize: Int {
        (try? FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )[.size] as? Int) ?? 0
    }

    /// Delete the log file.
    func clearLog() {
        queue.async { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
