//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation

extension Array {
    public func at(_ index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

extension Array where Iterator.Element == String {
    public var combineWithNewline: String {
        combine(with: "\n")
    }

    public func combine(with string: String) -> String {
        reduce(into: "") { content, line in
            content += line
            content += string
        }
    }
}

extension Collection {
    public func element(at index: Self.Index) -> Self.Iterator.Element? {
        guard index >= startIndex, index < endIndex else {
            return nil
        }
        return self[index]
    }
}

extension Encodable {
    public func json() throws -> String {
        let jsonData = try JSONEncoder().encode(self)
        guard let string = String(data: jsonData, encoding: .utf8) else {
            throw SystemError.invalidJson
        }
        return string
    }
}

extension File {
    public func loadContent() throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        let data = fileHandle.readDataToEndOfFile()
        guard let originalContent = String(data: data, encoding: .utf8) else {
            throw SystemError.failedToParse(reason: "Failed to convert the data into a string")
        }
        fileHandle.closeFile()
        return originalContent
    }

    public func store(_ content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw SystemError.failedToParse(reason: "Failed to convert the string into data")
        }
        try data.write(to: url, options: .atomic)
        var fileContent = ""
        repeat {
            // Give the file system time to save the file so it shows up in other shell processes
            Thread.sleep(forTimeInterval: 1)
            fileContent = try readAsString()
        } while content != fileContent
    }
}

extension Process {
    public func runUntilCompletion() throws {
        let pipe = Pipe()
        standardOutput = pipe
        try run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: String.Encoding.utf8) {
            LogVerbose(output)
        }
    }
}

extension Sequence {
    public func asMap<T>(converter: @escaping (Iterator.Element) -> T) -> [T: Iterator.Element] {
        var map: [T: Iterator.Element] = [:]
        for element in self {
            let string = converter(element)
            map[string] = element
        }
        return map
    }
}

extension String {
    public var wrapInQuotes: String {
        "\"" + self + "\""
    }

    public var appendComma: String {
        self + ","
    }

    public func parseJson<T: Decodable>() throws -> T {
        guard let jsonData = data(using: .utf8) else {
            throw SystemError.invalidJson
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

public protocol ReflectedStringConvertible: CustomStringConvertible {}

extension ReflectedStringConvertible {
    public var description: String {
        let mirror = Mirror(reflecting: self)

        var output = "[\(mirror.subjectType)\n"
        for (label, value) in mirror.children {
            guard let label = label else {
                continue
            }
            output += label
            output += "=\(value)\n"
        }
        output += "]"
        return output
    }
}
