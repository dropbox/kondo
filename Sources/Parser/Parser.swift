//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public protocol Parser: AnyObject {
  var printOnly: Bool { get set }
  var cachePath: String? { get set }

  func listTypes(from input: ParserListTypesInput, rootFolderPath: String) throws -> ParserListTypesOutput
}

extension Parser {
  public func listTypes(fromJson json: String, rootFolderPath: String = ".") throws -> ParserListTypesOutput {
    let input: ParserListTypesInput = try json.parseJson()
    return try listTypes(from: input, rootFolderPath: rootFolderPath)
  }

  public func listTypes(from input: ParserListTypesInput) throws -> ParserListTypesOutput {
    try listTypes(from: input, rootFolderPath: ".")
  }
}
