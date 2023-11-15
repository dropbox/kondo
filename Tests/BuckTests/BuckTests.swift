//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Buck
import Files
import Foundation
import Graph
import Parser
import Rename
import Shell
import TestData
import Utilities
import XCTest

final class BuckTests: XCTestCase {
    private static let testFolder = "BuckTests"

    private var testFolder: Folder!

    override func setUpWithError() throws {
        Logger.logLevel = .verbose
        testFolder = try Self.testFolder.createFolder()
        try testFolder.createFile(at: ".buckconfig")
    }

    override func tearDownWithError() throws {
        try testFolder.delete()
    }

    func testCreateModule() throws {
        try [
            TestFile.example3,
            TestFile.example4Header,
            TestFile.example4Implementation,
        ]
        .forEach { testFile -> Void in
            let file = try testFolder.createSubfolder(at: testFile.path).createFile(named: testFile.name)
            try file.write(testFile.content)
        }
        let filesToMove = try [
            TestFile.example1,
            TestFile.example2Header,
            TestFile.example2Implementation,
        ]
        .map { testFile -> File in
            let file = try testFolder.createSubfolder(at: testFile.path).createFile(named: testFile.name)
            try file.write(testFile.content)
            return file
        }
        let filesToMoveNames = filesToMove.map { $0.path(relativeTo: testFolder) }

        let destination = "ios/common/files"

        let graph = GraphFake()
        let parser = ParserFake()
        let shell = ShellFake()
        let rename = RenameFake()
        let buck = BuckImpl(graph: graph, parser: parser, rename: rename, shell: shell)
        let projectBuildTargets = ["//ios/app:App"]
        let input = BuckCreateInput(
            modules: [BuckCreateInput.Module(destination: destination, files: filesToMoveNames)],
            projectBuildTargets: projectBuildTargets
        )
        let json = try input.json()
        LogVerbose(json)
        try buck.createModule(fromJson: json, rootFolderPath: testFolder.path)

        let buckFile = try testFolder.file(at: "\(destination)/BUCK")
        let buckString = try buckFile.readAsString()

        // Make sure the buck file output is correct
        let output =
            """
            load('//tools/buck/rules:buck_rule_macros.bzl', 'dbx_apple_library')

            dbx_apple_library(
            name = 'files',
            module_name = 'ios_common_files',
            modular = True,
            coverage_exception_percent = 0.0,
            exported_headers = [
            "Example2.h",
            ],
            srcs = [
            "Example1.swift",
            "Example2.m",
            ],
            frameworks = [
            "Foundation",
            "UIKit",
            ],
            deps = [
            "//ios/common/logging:logging",
            "//ios/common/utilities:utilities",
            ],
            )


            """
        XCTAssertEqual(buckString, output)

        // Confirm the files were moved to the correct location
        let newFolder = try testFolder.subfolder(at: destination)
        filesToMove.forEach {
            XCTAssertTrue(newFolder.containsFile(at: $0.name))
        }

        // Ensure other files are not moved or changed.
        try [
            TestFile.example3,
            TestFile.example4Header,
            TestFile.example4Implementation,
        ]
        .forEach { testFile -> Void in
            let file = try testFolder.subfolder(at: testFile.path).file(at: testFile.name)
            let content = try file.readAsString()
            XCTAssertEqual(testFile.content, content)
        }

        // Check the rename input
        guard let renameInputs = rename.input else {
            XCTFail("Failed to generate the input for renaming")
            return
        }
        XCTAssertEqual(1, renameInputs.items.count)
        let items = renameInputs.items.sorted { $0.newText < $1.newText }
        let example1Item = RenameInput.Item(
            originalText: "#import \"Example2.h\"",
            newText: "#import <ios_common_files/Example2.h>",
            fileTypes: [".h", ".m", ".mm"],
            excludingPaths: ["ios/common/files"]
        )
        XCTAssertEqual(example1Item, items[0])
    }

    static var allTests = [
        ("testCreateModule", testCreateModule),
    ]
}
