//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Buck
import CommandLine
import Files
import Foundation
import Parser
import Rename
import Shell
import TestData
import Utilities
import XCTest

final class CommandLineTests: XCTestCase {
  func testCreate() throws {
    let input = BuckCreateInput(
      modules: [BuckCreateInput.Module(destination: "ios/common", files: ["Test.swift"])],
      projectBuildTargets: ["//target"]
    )
    let json = try input.json()
    let buckPath = "/usr/bin/buck"
    let buildifierPath = "/weird/path/buildifier"
    let shellPath = "/Users/fake"
    let arguments = [
      "refactor", "--printOnly", "-v", "create", "jsonText=\(json)", "buckPath=\(buckPath)",
      "buildifierPath=\(buildifierPath)", "shellPath=\(shellPath)"
    ]
    let buck = BuckFake()
    let graph = GraphFake()
    let parser = ParserFake()
    let rename = RenameFake()
    let shell = ShellFake()
    let tool = CommandLineTool(
      arguments: arguments,
      buck: buck,
      graph: graph,
      parser: parser,
      rename: rename,
      shell: shell
    )
    try tool.run()
    XCTAssertEqual(Logger.logLevel, LogLevel.verbose)
    XCTAssertTrue(buck.printOnly)
    XCTAssertTrue(parser.printOnly)
    XCTAssertTrue(rename.printOnly)
    XCTAssertEqual(buck.createModuleInput, input)
    XCTAssertEqual(shell.buckPath, buckPath)
    XCTAssertEqual(shell.buildifierPath, buildifierPath)
    XCTAssertEqual(shell.shellPath, shellPath)
  }

  func testMove() throws {
    let input = BuckMoveInput(paths: [BuckMoveInput.Path(source: "dbx/common", destination: "ios/common")])
    let json = try input.json()
    let buckPath = "/usr/bin/buck"
    let buildifierPath = "/weird/path/buildifier"
    let shellPath = "/Users/fake"
    let arguments = [
      "refactor", "--printOnly", "-v", "move", "jsonText=\(json)", "buckPath=\(buckPath)",
      "buildifierPath=\(buildifierPath)", "shellPath=\(shellPath)"
    ]
    let buck = BuckFake()
    let graph = GraphFake()
    let parser = ParserFake()
    let rename = RenameFake()
    let shell = ShellFake()
    let tool = CommandLineTool(
      arguments: arguments,
      buck: buck,
      graph: graph,
      parser: parser,
      rename: rename,
      shell: shell
    )
    try tool.run()
    XCTAssertEqual(Logger.logLevel, LogLevel.verbose)
    XCTAssertTrue(buck.printOnly)
    XCTAssertTrue(parser.printOnly)
    XCTAssertTrue(rename.printOnly)
    XCTAssertEqual(buck.moveModuleInput, input)
    XCTAssertEqual(shell.buckPath, buckPath)
    XCTAssertEqual(shell.buildifierPath, buildifierPath)
    XCTAssertEqual(shell.shellPath, shellPath)
  }

  static var allTests = [
    ("testCreate", testCreate),
    ("testMove", testMove)
  ]
}
