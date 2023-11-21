//
//  Copyright © 2023 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Rename
import Utilities

/// Implementation of `createModule(from:rootFolderPath:)` lives here.
extension BuckImpl {
    private static let sourceFiles = [".swift", ".m", ".mm"]

    internal func createModuleImpl(from input: BuckCreateInput, rootFolderPath: String) throws {
        LogVerbose("Creating module")
        LogVerbose(input.description)

        var renameImportItems = [RenameInput.Item]()
        let root = try Folder(path: rootFolderPath)
        var appleLibraryMap = [String: BuckModule]()
        try input.projectBuildTargets.map { try parseDependencies(fromTarget: $0) }.forEach { map in
            appleLibraryMap.merge(map, uniquingKeysWith: { old, _ in old })
        }

        let modules = try input.modules.map { module -> String in
            let destinationPath = module.destination.trimmingCharacters(in: Self.invertedAlphanumerics)
            let destination = try root.createSubfolderIfNeeded(at: destinationPath)
            let files = try module.files.map { try root.file(at: $0) }

            let targetName = module.targetName ?? destination.url.lastPathComponent

            let moduleName: String
            if let name = module.moduleName {
                moduleName = name
            } else {
                let nameFromPath = destinationPath.replacingOccurrences(of: "/", with: "_").lowercased()
                if nameFromPath.hasSuffix(targetName) {
                    moduleName = nameFromPath
                } else {
                    moduleName = "\(nameFromPath)_\(targetName)"
                }
            }

            let items = renameObjcImportList(for: files, moduleName: moduleName, excludingPaths: [destinationPath])
            renameImportItems.append(contentsOf: items)

            try createBuckFile(
                from: module,
                targetName: targetName,
                moduleName: moduleName,
                at: destination,
                files: files,
                libraries: Array(appleLibraryMap.values)
            )
            try move(files: files, to: destination)
            return "//\(destinationPath):\(targetName)"
        }

        let excludingPaths = input.ignoreFolders ?? []
        let renameInput = RenameInput(items: renameImportItems, excludingPaths: excludingPaths)
        try rename.rename(from: renameInput, rootFolderPath: rootFolderPath)
        LogInfo("Extracted modules:\n\(modules.combineWithNewline)")
    }

    private func createBuckFile(
        from module: BuckCreateInput.Module,
        targetName: String,
        moduleName: String,
        at destination: Folder,
        files: [File],
        libraries: [BuckModule]
    ) throws {
        let visibility = module.visibility ?? []

        let imports = try loadModuleImports(from: files)
        let frameworks = parseFrameworks(from: libraries, imports: imports)
        let dependencies = parseDependencies(from: libraries, imports: imports)

        let output = createBuckFileContent(
            targetName: targetName,
            moduleName: moduleName,
            fileNames: files.map(\.name).sorted(),
            visibility: visibility.sorted(),
            frameworks: frameworks.sorted(),
            dependencies: dependencies.sorted(),
            testTarget: module.testTarget
        )

        if printOnly {
            print("Buck File\n\(output)")
        } else {
            LogInfo("Creating buck file at \(destination)")
            LogVerbose(output)
            let buckFile = try destination.createFile(at: "BUCK")
            try buckFile.store(output)
            try shell.runBuildifier(on: buckFile)
        }
    }

    private func parseDependencies(from libraries: [BuckModule], imports: [String]) -> [String] {
        var moduleMap = [String: String]()
        libraries.forEach { library in
            guard let moduleName = library.module_name else {
                return
            }
            moduleMap[moduleName] = library.target
        }
        let dependencies = imports.compactMap { moduleMap[$0] }
        return dependencies
    }

    private func parseFrameworks(from libraries: [BuckModule], imports: [String]) -> [String] {
        let allFrameworks = Set(libraries.flatMap { $0.frameworks ?? [] })
        let cleanedFrameworks = allFrameworks.map {
            $0.replacingOccurrences(of: "$SDKROOT/System/Library/Frameworks/", with: "")
                .replacingOccurrences(of: ".framework", with: "")
        }
        let reducedFrameworks = Set(cleanedFrameworks)
        let neededFrameworks = reducedFrameworks.intersection(imports)
        let sortedFrameworks = neededFrameworks.sorted()
        LogVerbose("Frameworks:\n\(sortedFrameworks)")
        return sortedFrameworks
    }

    private func createBuckFileContent(
        targetName: String,
        moduleName: String,
        fileNames: [String],
        visibility: [String],
        frameworks: [String],
        dependencies: [String],
        testTarget: Bool
    ) -> String {
        let headers = fileNames.filter { fileName in Self.headerFiles.contains { fileName.hasSuffix($0) } }
        let sources = fileNames.filter { fileName in Self.sourceFiles.contains { fileName.hasSuffix($0) } }

        // TODO: Make this a template file that can be passed as part of the input json
        var content = ""
        if testTarget {
            content.append("load('//tools/buck/rules:buck_rule_macros.bzl', 'dbx_apple_test_library')\n\n")
            content.append("dbx_apple_test_library(\n")
            content.append("name = '\(targetName)',\n")
            if !headers.isEmpty {
                content.append("headers = [\n")
                content.append(headers.map(\.wrapInQuotes.appendComma).combineWithNewline)
                content.append("],\n")
            }
        } else {
            content.append("load('//tools/buck/rules:buck_rule_macros.bzl', 'dbx_apple_library')\n\n")
            content.append("dbx_apple_library(\n")
            content.append("name = '\(targetName)',\n")
            content.append("module_name = '\(moduleName)',\n")
            content.append("modular = True,\n")
            content.append("coverage_exception_percent = 0.0,\n")
            if !headers.isEmpty {
                content.append("exported_headers = [\n")
                content.append(headers.map(\.wrapInQuotes.appendComma).combineWithNewline)
                content.append("],\n")
            }
        }
        if !sources.isEmpty {
            content.append("srcs = [\n")
            content.append(sources.map(\.wrapInQuotes.appendComma).combineWithNewline)
            content.append("],\n")
        }
        if !frameworks.isEmpty {
            content.append("frameworks = [\n")
            content.append(frameworks.map(\.wrapInQuotes.appendComma).combineWithNewline)
            content.append("],\n")
        }
        if !dependencies.isEmpty {
            content.append("deps = [\n")
            content.append(dependencies.map(\.wrapInQuotes.appendComma).combineWithNewline)
            content.append("],\n")
        }
        if !visibility.isEmpty {
            content.append("visibility = [\n")
            content.append(visibility.map(\.wrapInQuotes.appendComma).combineWithNewline)
            content.append("],\n")
        }
        content.append(")\n\n")
        return content
    }

    private func renameObjcImportList(
        for files: [File],
        moduleName: String,
        excludingPaths: [String]
    ) -> [RenameInput.Item] {
        files.compactMap { file -> String? in
            let fileName = file.name
            guard Self.headerFiles.contains(where: { fileName.hasSuffix($0) }) else {
                LogVerbose("Ignoring imports for \(file.name)")
                return nil
            }
            return fileName
        }
        .map { fileName -> RenameInput.Item in
            RenameInput.Item(
                originalText: "#import \"\(fileName)\"",
                newText: "#import <\(moduleName)/\(fileName)>",
                fileTypes: [".h", ".m", ".mm"],
                excludingPaths: excludingPaths
            )
        }
    }

    private func move(files: [File], to destination: Folder) throws {
        if printOnly {
            files.forEach { print("mv \($0) to \(destination)") }
        } else {
            LogInfo("Moving files")
            try files.forEach { try $0.move(to: destination) }
        }
    }
}
