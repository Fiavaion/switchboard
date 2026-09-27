import os

extension Logger {
    private static let subsystem = "com.fiavaion.switchboard"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
