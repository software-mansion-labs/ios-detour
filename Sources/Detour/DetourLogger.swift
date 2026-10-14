import Foundation
import os.log
#if canImport(os)
import os
#endif

enum DetourLogger {
    private static let subsystem = "com.swmansion.detour"

    private enum Level {
        case debug
        case warn
        case error
    }

    static func debug(_ tag: String, _ message: String) {
        log(tag: tag, level: .debug, message: message)
    }

    static func warn(_ tag: String, _ message: String) {
        log(tag: tag, level: .warn, message: message)
    }

    static func error(_ tag: String, _ message: String, error: Error? = nil) {
        let formattedMessage: String
        if let error {
            formattedMessage = "\(message) \(error.localizedDescription)"
        } else {
            formattedMessage = message
        }

        log(tag: tag, level: .error, message: formattedMessage)
    }

    private static func log(tag: String, level: Level, message: String) {
        let logger = Logger(subsystem: subsystem, category: tag)
        switch level {
        case .debug:
            logger.log(level: .debug, "\(message, privacy: .public)")
        case .warn:
            logger.log(level: .default, "\(message, privacy: .public)")
        case .error:
            logger.log(level: .error, "\(message, privacy: .public)")
        }
    }
}
