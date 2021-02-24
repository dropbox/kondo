//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public final class GraphImpl: Graph {
  private let queue = DispatchQueue(
    label: "com.dropbox.GraphImpl",
    qos: .userInteractive,
    attributes: .concurrent,
    autoreleaseFrequency: .workItem
  )

  public var printOnly = false

  public init() {}

  public func graph(from input: GraphInput, rootFolderPath: String) throws {
    LogInfo("Starting graph")
    LogVerbose(input.description)
    let rootFolder = try Folder(path: rootFolderPath)
    LogInfo("Graph finished processing \(rootFolder)")
  }

  // MARK: - Private
}
