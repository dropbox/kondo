//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct ParserListTypesInput: Codable, ReflectedStringConvertible, Equatable {
  public let filePaths: [String]
  public let overrides: [ParsedFile]?
  public let jsonOutputPath: String?
  public let csvOutputPath: String?

  public init(filePaths: [String], overrides: [ParsedFile]?, jsonOutputPath: String?, csvOutputPath: String?) {
    self.filePaths = filePaths
    self.overrides = overrides
    self.jsonOutputPath = jsonOutputPath
    self.csvOutputPath = csvOutputPath
  }
}
