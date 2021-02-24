//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Graph
import TestData
import Utilities
import XCTest

final class GraphTests: XCTestCase {
  private static let testFolder = "GraphTests"

  private var testFolder: Folder!

  override func setUpWithError() throws {
    Logger.logLevel = .verbose
    testFolder = try Self.testFolder.createFolder()
  }

  override func tearDownWithError() throws {
    try testFolder.delete()
  }

  func testGraphTypes() throws {
    let input = GraphInput(nodes: [
      GraphInput.GraphNode(
        id: "my/path/filename1.txt",
        dependentIDs: ["my/path/filename2.txt", "my/path/filename3.txt"]
      )
    ])
    let graph = GraphImpl()
    try graph.graph(from: input, rootFolderPath: testFolder.path)

    // TODO: Finish test
  }

  static var allTests = [
    ("testGraphTypes", testGraphTypes)
  ]
}
