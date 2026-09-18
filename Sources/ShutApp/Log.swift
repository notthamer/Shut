import os

/// One logger per subsystem area. Nothing logged here ever includes pixels.
enum Log {
    static let app = Logger(subsystem: "app.shut", category: "app")
    static let lid = Logger(subsystem: "app.shut", category: "lid")
    static let overlay = Logger(subsystem: "app.shut", category: "overlay")
    static let capture = Logger(subsystem: "app.shut", category: "capture")
    static let unlock = Logger(subsystem: "app.shut", category: "unlock")
    static let awake = Logger(subsystem: "app.shut", category: "awake")
}
