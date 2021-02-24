//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Rename
import TestData
import Utilities
import XCTest

final class RenameTests: XCTestCase {
  private static let testFolder = "RenameTests"

  private var testFolder: Folder!

  override func setUpWithError() throws {
    Logger.logLevel = .verbose
    testFolder = try Self.testFolder.createFolder()
  }

  override func tearDownWithError() throws {
    try testFolder.delete()
  }

  func testRename() throws {
    let ignoreFiles = try [
      TestFile.example1
    ]
    .map { testFile -> File in
      let file = try testFolder.createSubfolderIfNeeded(at: "ignore").createFile(named: testFile.name)
      try file.write(testFile.content)
      return file
    }
    let changeFiles = try [
      TestFile.example2Header,
      TestFile.example2Implementation,
      TestFile.example3,
      TestFile.example4Header,
      TestFile.example4Implementation
    ]
    .map { testFile -> File in
      let file = try testFolder.createSubfolderIfNeeded(at: "change").createFile(named: testFile.name)
      try file.write(testFile.content)
      return file
    }

    let items = [
      RenameInput.Item(
        originalText: "import ios_common_utilities",
        newText: "import ios_common_stuff",
        fileTypes: [".swift"],
        excludingPaths: []
      ),
      RenameInput.Item(
        originalText: "#import \"Example4Header.h\"",
        newText: "#import <ios_common_logging/Example1.h>",
        fileTypes: [".m", ".h"],
        excludingPaths: []
      )
    ]
    let input = RenameInput(items: items, excludingPaths: ["ignore"])

    let rename = RenameImpl()
    try rename.rename(from: input, rootFolderPath: testFolder.path)

    try ignoreFiles.forEach { file in
      let content = try file.readAsString()
      XCTAssertFalse(content.contains("ios_common_stuff"))
    }
    LogVerbose("Checking changed files")
    try changeFiles.forEach { file in
      let content = try file.readAsString()
      XCTAssertFalse(content.contains("import ios_common_utilities"), content)
      XCTAssertFalse(content.contains("#import \"Example4Header.h\""), content)
    }
  }

  static var allTests = [
    ("testRename", testRename)
  ]
}
