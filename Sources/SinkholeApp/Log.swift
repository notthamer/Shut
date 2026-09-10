import os

/// One logger per subsystem area. Nothing logged here ever includes pixels.
enum Log {
    static let app = Logger(subsystem: "com.sinkhole.app", category: "app")
    static let lid = Logger(subsystem: "com.sinkhole.app", category: "lid")
    static let overlay = Logger(subsystem: "com.sinkhole.app", category: "overlay")
    static let capture = Logger(subsystem: "com.sinkhole.app", category: "capture")
    static let unlock = Logger(subsystem: "com.sinkhole.app", category: "unlock")
}
