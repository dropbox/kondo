//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckFile: Codable, ReflectedStringConvertible, Equatable {
  private static let libraryRegex = try! NSRegularExpression(
    pattern: #"(?s)(dbx_apple_library\(\n)[^)]*(\n\))"#,
    options: []
  )
  private static let importRegex = try! NSRegularExpression(
    pattern: #"(?s)(load\()[^)]*(\))"#,
    options: []
  )

  public let path: String
  public let imports: [String]
  public let unknownModules: String
  public var buckModules: [String: RawBuckModule]

  public var text: String {
    var output = imports.combineWithNewline
    output += "\n"
    output += buckModules.values.map(\.text).combineWithNewline
    output += "\n"
    output += unknownModules
    return output
  }

  public init(
    path: String,
    imports: [String],
    unknownModules: String,
    buckModules: [String: RawBuckModule]
  ) {
    self.path = path
    self.imports = imports
    self.unknownModules = unknownModules
    self.buckModules = buckModules
  }

  public init(path: String, fileContent: String) {
    self.path = path

    var content = fileContent
    var contentRange = NSRange(content.startIndex..<content.endIndex, in: content)

    var imports = [String]()
    Self.importRegex.enumerateMatches(in: content, options: [], range: contentRange) { match, _, _ in
      guard let match = match else { return }
      guard let range = Range(match.range, in: content) else {
        return
      }
      let text = String(content[range])
      imports.append(text)
    }
    self.imports = imports

    content = Self.importRegex.stringByReplacingMatches(
      in: content,
      options: [],
      range: contentRange,
      withTemplate: ""
    )
    contentRange = NSRange(content.startIndex..<content.endIndex, in: content)

    var buckModules = [RawBuckModule]()
    Self.libraryRegex.enumerateMatches(in: content, options: [], range: contentRange) { match, _, _ in
      guard let match = match else { return }
      guard let range = Range(match.range, in: content) else {
        return
      }
      let text = String(content[range])
      let module = RawBuckModule(text: text)
      guard module.isValid else {
        LogError("Failed to parse buck module from \(text)")
        return
      }
      buckModules.append(module)
    }
    self.buckModules = buckModules.asMap { "//\(path):\($0.name)" }

    content = Self.libraryRegex.stringByReplacingMatches(
      in: content,
      options: [],
      range: contentRange,
      withTemplate: ""
    )
    self.unknownModules = content
  }

  // MARK: - Private
}
