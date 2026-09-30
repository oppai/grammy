import os

/// View with: log stream --predicate 'subsystem == "ninja.oppai.grammy"'
/// Never log message text itself — only lengths and structural info.
enum Log {
    static let monitor = Logger(subsystem: "ninja.oppai.grammy", category: "monitor")
    static let check = Logger(subsystem: "ninja.oppai.grammy", category: "check")
}
