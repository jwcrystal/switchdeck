import Foundation

/// Runs a command line tool and returns its output.
///
/// Switches that only need `defaults`, `killall` or `open` go through here so the
/// command line is visible in one place and easy to test by eye.
public enum Shell {
    public struct Result {
        public let status: Int32
        public let output: String
        public let error: String
    }

    @discardableResult
    public static func run(_ path: String, _ arguments: [String] = []) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }
}
