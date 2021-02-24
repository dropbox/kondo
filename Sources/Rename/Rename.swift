//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public protocol Rename: AnyObject {
  var printOnly: Bool { get set }

  func rename(from input: RenameInput, rootFolderPath: String) throws
}

extension Rename {
  public func rename(fromJson json: String, rootFolderPath: String = ".") throws {
    let input: RenameInput = try json.parseJson()
    try rename(from: input, rootFolderPath: rootFolderPath)
  }

  public func rename(fromJsonFile jsonFile: String, rootFolderPath: String = ".") throws {
    let sourceFile = try File(path: jsonFile)
    let json = try sourceFile.readAsString()
    try rename(fromJson: json, rootFolderPath: rootFolderPath)
  }

  public func rename(from input: RenameInput) throws {
    try rename(from: input, rootFolderPath: ".")
  }
}
