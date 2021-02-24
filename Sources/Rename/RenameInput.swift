//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct RenameInput: Codable, ReflectedStringConvertible, Equatable {
  public struct Item: Codable, ReflectedStringConvertible, Equatable {
    public let originalText: String
    public let newText: String
    public let fileTypes: [String]
    public let excludingPaths: [String]

    public init(
      originalText: String,
      newText: String,
      fileTypes: [String],
      excludingPaths: [String]
    ) {
      self.originalText = originalText
      self.newText = newText
      self.fileTypes = fileTypes
      self.excludingPaths = excludingPaths
    }
  }

  public let items: [Item]
  public let excludingPaths: [String]

  public init(items: [Item], excludingPaths: [String]) {
    self.items = items
    self.excludingPaths = excludingPaths
  }
}
