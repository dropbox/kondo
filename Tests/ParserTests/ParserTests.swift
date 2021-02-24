//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Parser
import TestData
import Utilities
import XCTest

final class ParserTests: XCTestCase {
  private static let testFolder = "ParserTests"

  private var testFolder: Folder!

  override func setUpWithError() throws {
    Logger.logLevel = .verbose
    testFolder = try Self.testFolder.createFolder()
  }

  override func tearDownWithError() throws {
    try testFolder.delete()
  }

  func testParse() throws {
    let files = try [
      TestFile.example1,
      TestFile.example2Header,
      TestFile.example2Implementation,
      TestFile.example3,
      TestFile.example4Header,
      TestFile.example4Implementation
    ]
    .map { testFile -> File in
      let file = try testFolder.createSubfolderIfNeeded(at: testFile.path).createFile(named: testFile.name)
      try file.write(testFile.content)
      return file
    }

    let filePaths = files.map { $0.path(relativeTo: testFolder) }

    let input = ParserListTypesInput(filePaths: filePaths, overrides: nil, jsonOutputPath: nil, csvOutputPath: nil)

    let parser = try ParserImpl()
    let output = try parser.listTypes(from: input, rootFolderPath: testFolder.path)

    let expectedFiles = [
      ParsedFile(
        filePath: "ios/app/Example1.swift",
        definedTypeNames: ["Example1", "Example1.Model", "Example1Enum"],
        requiredTypeNames: ["Example2Enum"],
        error: nil
      ),
      ParsedFile(
        filePath: "ios/app/Example2.h",
        definedTypeNames: ["Example2", "Example2Enum"],
        requiredTypeNames: ["Example3"],
        error: nil
      ),
      ParsedFile(
        filePath: "ios/app/Example2.m",
        definedTypeNames: [],
        requiredTypeNames: ["Example2", "Example4"],
        error: nil
      ),
      ParsedFile(
        filePath: "ios/app/Example3.swift",
        definedTypeNames: ["DBExample3", "Example3", "Example3Delegate"],
        requiredTypeNames: ["Example4"],
        error: nil
      ),
      ParsedFile(
        filePath: "ios/app/Example4.h",
        definedTypeNames: ["Example4", "Example4Delegate"],
        requiredTypeNames: [],
        error: nil
      ),
      ParsedFile(
        filePath: "ios/app/Example4.m",
        definedTypeNames: [],
        requiredTypeNames: ["Example2", "Example4"],
        error: nil
      )
    ]
    XCTAssertEqual(output.files.count, expectedFiles.count)
    output.files.enumerated()
      .forEach { number, file in
        let expectedFile = expectedFiles[number]
        XCTAssertEqual(file, expectedFile)
      }
  }

  static var allTests = [
    ("testParse", testParse)
  ]
}
