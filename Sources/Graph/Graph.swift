//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public protocol Graph: AnyObject {
  var printOnly: Bool { get set }

  func graph(from input: GraphInput, rootFolderPath: String) throws
}

extension Graph {
  public func graph(fromJson json: String, rootFolderPath: String = ".") throws {
    let input: GraphInput = try json.parseJson()
    return try graph(from: input, rootFolderPath: rootFolderPath)
  }

  public func graph(from input: GraphInput) throws {
    try graph(from: input, rootFolderPath: ".")
  }
}
