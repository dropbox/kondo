//
//  Copyright © 2023 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Parser
import Utilities

/// Implementation of `parseModules(from:rootFolderPath:)` lives here.
extension BuckImpl {
    /// Allowlist for file types allowed in the filePaths param.
    private static let parseableFileTypes = [".h", ".m", ".mm", ".swift"]

    public func parseModulesImpl(from input: BuckParseInput, rootFolderPath: String) throws {
        LogInfo("Parsing buck modules")
        LogVerbose(input.description)
        var moduleMap = [String: BuckModule]()
        try input.projectBuildTargets.map { try parseDependencies(fromTarget: $0) }.forEach { map in
            moduleMap.merge(map, uniquingKeysWith: { old, _ in old })
        }

        let root = try Folder(path: rootFolderPath)
        let allFiles = try moduleMap.values.flatMap { module -> [File] in
            let moduleFiles = try files(for: module, root: root)
                .filter { file -> Bool in Self.parseableFileTypes.contains(where: { file.name.hasSuffix($0) }) }
                .filter { file -> Bool in
                    !["DBSDKImportsShared.h", "DBSDKImportsGenerated.h"].contains(where: { file.name.hasSuffix($0) })
                }
            return moduleFiles
        }
        let filePaths = allFiles.map { $0.path(relativeTo: root) }
        let parserInput = ParserListTypesInput(
            filePaths: filePaths,
            overrides: input.overrides,
            jsonOutputPath: input.jsonOutputPath,
            csvOutputPath: input.csvOutputPath
        )

        // Main work is done by parser. Results are written to jsonOutputPath and/or csvOutputPath.
        _ = try parser.listTypes(from: parserInput, rootFolderPath: rootFolderPath)
        LogInfo("Finished parsing types of \(filePaths.count) files")
    }
}
