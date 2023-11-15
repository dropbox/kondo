//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation

public enum Logger {
    public static var logLevel: LogLevel = .info
}

public enum LogLevel: Int, CustomStringConvertible, Comparable {
    case debug = 1
    case verbose = 2
    case info = 3
    case warn = 4
    case error = 5

    public var shouldLog: Bool {
        self >= Logger.logLevel
    }

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .verbose: return "VERBOSE"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@inline(__always)
public func LogDebug(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: nil, file: file, function: function, line: line, level: .debug, error: nil)
}

@inline(__always)
public func LogVerbose(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: nil, file: file, function: function, line: line, level: .verbose, error: nil)
}

@inline(__always)
public func LogInfo(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: nil, file: file, function: function, line: line, level: .info, error: nil)
}

@inline(__always)
public func LogWarn(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: nil, file: file, function: function, line: line, level: .warn, error: nil)
}

@inline(__always)
public func LogError(
    _ message: @autoclosure () -> String,
    info: [String: Any]? = nil,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: info, file: file, function: function, line: line, level: .error, error: nil)
}

@inline(__always)
public func Log(
    _ error: Error,
    _ message: @autoclosure () -> String,
    info: [String: Any]? = nil,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(message(), info: info, file: file, function: function, line: line, level: .error, error: error)
}

@inline(__always)
public func Log(
    _ error: Error,
    info: [String: Any]? = nil,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) {
    Log(error.localizedDescription, info: info, file: file, function: function, line: line, level: .error, error: error)
}

@inline(__always)
public func Log(
    _ message: @autoclosure () -> String,
    info _: [String: Any]?,
    file: CustomStringConvertible,
    function _: CustomStringConvertible,
    line: UInt,
    level: LogLevel,
    error: Error?
) {
    guard level.shouldLog else { return }
    let debugMessage = message()
    guard !debugMessage.isEmpty else { return }
    let debugFileString = file.description.components(separatedBy: "/").last
    let debugFileName = debugFileString ?? file.description
    let debugErrorMessage: String
    if let error = error {
        debugErrorMessage = "\(error)\n"
    } else {
        debugErrorMessage = ""
    }
    let debugLogMessage =
        "REFACTOR: \(level.description) - \(debugFileName)@\(line): \(debugMessage) \(debugErrorMessage)"

    printOnMainThread(debugLogMessage)
}

private func printOnMainThread(_ message: String) {
    guard Thread.isMainThread else {
        DispatchQueue.main.async {
            printOnMainThread(message)
        }
        return
    }
    print(message)
}
