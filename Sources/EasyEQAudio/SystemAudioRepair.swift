import Foundation
import os

private let repairLog = Logger(subsystem: "app.easyeq.EasyEQ", category: "repair")

/// Restarts the system audio service (`coreaudiod`) after the user approves macOS's own administrator dialog.
/// EasyEQ never sees the password: `osascript` shows the standard authorization prompt and runs the command.
public enum SystemAudioRepair {
    public enum Outcome: Equatable, Sendable {
        case restarted
        /// The user dismissed the authorization dialog. Not an error.
        case cancelled
        case failed(String)
    }

    /// The only script ever run. A constant: nothing the user typed or the system reported is interpolated.
    static let script = #"do shell script "/usr/bin/killall coreaudiod" with administrator privileges"#
    static let osascriptPath = "/usr/bin/osascript"

    /// Maps an `osascript` result to an outcome. A canceled dialog exits non-zero with
    /// "User canceled. (-128)" on stderr.
    static func classify(exitCode: Int32, standardError: String) -> Outcome {
        if exitCode == 0 { return .restarted }
        if standardError.contains("(-128)") || standardError.localizedCaseInsensitiveContains("user canceled")
            || standardError.localizedCaseInsensitiveContains("user cancelled") {
            return .cancelled
        }
        return .failed(standardError.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs the repair and waits for it, including for as long as the authorization dialog is open: never call it
    /// on the main thread; use `perform()`.
    static func runBlocking() -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            repairLog.error("Could not launch osascript: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outcome = classify(exitCode: process.terminationStatus, standardError: String(decoding: data, as: UTF8.self))
        switch outcome {
        case .restarted: repairLog.info("coreaudiod restarted")
        case .cancelled: repairLog.info("Repair canceled by the user")
        case .failed(let message): repairLog.error("Repair failed (exit \(process.terminationStatus)): \(message, privacy: .public)")
        }
        return outcome
    }

    /// Runs the repair off the main thread (on a global dispatch queue, so a dialog left open for minutes does not
    /// tie up a Swift concurrency thread) and returns when it is over.
    public static func perform() async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking())
            }
        }
    }
}
