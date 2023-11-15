//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct RawBuckModule: Codable, ReflectedStringConvertible, Equatable {
    private static let nameRegex = #"(?s)(?<=[[:blank:]]name = ")[^,]*(?=",)"#
    private static let moduleNameRegex = #"(?s)(?<=[[:blank:]]module_name = ")[^,]*(?=",)"#
    private static let sourcesRegex = #"(?s)(?<=[[:blank:]]srcs = \[)[^]]*(?=])"#
    private static let headersRegex = #"(?s)(?<=[[:blank:]]headers = \[)[^]]*(?=])"#
    private static let exportedHeadersRegex = #"(?s)(?<=[[:blank:]]exported_headers = \[)[^]]*(?=])"#
    private static let depsRegex = #"(?s)(?<=[[:blank:]]deps = \[)[^]]*(?=])"#
    private static let exportedDepsRegex = #"(?s)(?<=[[:blank:]]exported_deps = \[)[^]]*(?=])"#

    private var textRange: NSRange {
        NSRange(text.startIndex ..< text.endIndex, in: text)
    }

    public var isValid: Bool {
        !name.isEmpty
    }

    public var name: String {
        get { text(forRegex: Self.nameRegex) }
        set { updateValue(forRegex: Self.nameRegex, newValue: newValue) }
    }

    public var moduleName: String {
        get { text(forRegex: Self.moduleNameRegex) }
        set { updateValue(forRegex: Self.moduleNameRegex, newValue: newValue) }
    }

    public var sources: [String] {
        get { array(forRegex: Self.sourcesRegex) }
        set { updateValue(forRegex: Self.sourcesRegex, newValue: newValue) }
    }

    public var headers: [String] {
        get { array(forRegex: Self.headersRegex) }
        set { updateValue(forRegex: Self.headersRegex, newValue: newValue) }
    }

    public var exported_headers: [String] {
        get { array(forRegex: Self.exportedHeadersRegex) }
        set { updateValue(forRegex: Self.exportedHeadersRegex, newValue: newValue) }
    }

    public var deps: [String] {
        get { array(forRegex: Self.depsRegex) }
        set { updateValue(forRegex: Self.depsRegex, newValue: newValue) }
    }

    public var exported_deps: [String] {
        get { array(forRegex: Self.exportedDepsRegex) }
        set { updateValue(forRegex: Self.exportedDepsRegex, newValue: newValue) }
    }

    public private(set) var text: String

    public init(text: String) {
        self.text = text
    }

    // MARK: - Private

    private func range(forRegex regex: String) -> Range<String.Index>? {
        text.range(of: regex, options: .regularExpression)
    }

    private mutating func updateValue(forRegex regex: String, newValue: String) {
        guard let range = range(forRegex: regex) else { return }
        text = text.replacingCharacters(in: range, with: newValue)
    }

    private func text(forRegex regex: String) -> String {
        guard let range = range(forRegex: regex) else { return "" }
        return String(text[range])
    }

    private mutating func updateValue(forRegex regex: String, newValue: [String]) {
        guard let range = range(forRegex: regex) else { return }
        let combinedArray = newValue.map { "\"\($0)\"," }.combineWithNewline
        text = text.replacingCharacters(in: range, with: combinedArray)
    }

    private func array(forRegex regex: String) -> [String] {
        let rawLines = text(forRegex: regex).components(separatedBy: .newlines)
        let lines = rawLines.map {
            $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\","))
        }.filter { !$0.isEmpty }
        return lines
    }
}
