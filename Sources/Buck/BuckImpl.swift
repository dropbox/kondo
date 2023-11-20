//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Graph
import Parser
import Rename
import Shell
import Utilities

public final class BuckImpl: Buck {
    internal static let headerFiles = [".h"]

    private static let headerPathCharacterSet = CharacterSet(charactersIn: "./")
    private static let invertedAlphanumerics = CharacterSet.alphanumerics.inverted
    private static let sourceFiles = [".swift", ".m", ".mm"]
    private static let parseableFileTypes = [".h", ".m", ".mm", ".swift"]
    private static let moduleImportPrefixes = [
        "#import <",
        "import ",
        "@_implementationOnly import ",
        "@testable import ",
    ]

    public var printOnly = false
    private let graph: Graph
    private let parser: Parser
    internal let shell: Shell
    internal let rename: Rename

    public init(graph: Graph, parser: Parser, rename: Rename, shell: Shell) {
        self.shell = shell
        self.rename = rename
        self.parser = parser
        self.graph = graph
    }

    public func parseModules(from input: BuckParseInput, rootFolderPath: String) throws {
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
        _ = try parser.listTypes(from: parserInput, rootFolderPath: rootFolderPath)
        LogInfo("Finished parsing types of \(filePaths.count) files")
    }

    public func cleanupModule(from input: CleanupInput, rootFolderPath: String) throws {
        try cleanupModuleImpl(from: input, rootFolderPath: rootFolderPath)
    }

    public func createModule(from input: BuckCreateInput, rootFolderPath: String) throws {
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

    public func moveModule(from input: BuckMoveInput, rootFolderPath: String) throws {
        LogVerbose("Moving module \(input.description)")
        let root = try Folder(path: rootFolderPath)
        let excludingPaths = input.ignoreFolders ?? []
        var renameItems = [RenameInput.Item]()
        try input.paths.forEach { path in
            let sourcePath = path.source.trimmingCharacters(in: Self.invertedAlphanumerics)
            let source = try root.subfolder(at: sourcePath)
            let destinationPath = path.destination.trimmingCharacters(in: Self.invertedAlphanumerics)
            let destination = try root.createSubfolderIfNeeded(at: destinationPath)

            let sourceNameFromPath = sourcePath.replacingOccurrences(of: "/", with: "_").lowercased()
            let destinationNameFromPath = destinationPath.replacingOccurrences(of: "/", with: "_").lowercased()

            if printOnly {
                print("mv \(sourcePath) to \(destinationPath)")
            } else {
                try source.moveContents(to: destination, includeHidden: true)
            }

            renameItems.append(
                RenameInput.Item(
                    originalText: sourceNameFromPath,
                    newText: destinationNameFromPath,
                    fileTypes: [".h", ".m", ".mm", ".swift", "BUCK"],
                    excludingPaths: []
                )
            )
            renameItems.append(
                RenameInput.Item(
                    originalText: sourcePath,
                    newText: destinationPath,
                    fileTypes: [".bzl", "BUCK", ".bmbf.yaml"],
                    excludingPaths: []
                )
            )
        }
        let renameInput = RenameInput(items: renameItems, excludingPaths: excludingPaths)
        try rename.rename(from: renameInput, rootFolderPath: root.path)
    }

    public func moduleStats(from input: BuckStatsInput, rootFolderPath: String) throws {
        try moduleStatsImpl(from: input, rootFolderPath: rootFolderPath)
    }

    // MARK: - Private

    internal func build(targets: [String], noCache: Bool) -> Bool {
        do {
            return try shell.build(targets: targets, noCache: noCache)
        } catch {
            LogVerbose("Build error \(error)")
            return false
        }
    }

    internal func files(for module: BuckModule, root: Folder) throws -> [File] {
        guard let moduleFolder = folder(for: module, root: root) else {
            LogInfo("Failed to reduce imports for \(module.name), invalid folder")
            return []
        }
        let moduleFiles = files(for: module, in: moduleFolder)
            .sorted { $0.path < $1.path }
        return moduleFiles
    }

    internal func folder(for module: BuckModule, root: Folder) -> Folder? {
        var targetPath = module.target
        guard targetPath.hasPrefix("//") else {
            LogError("Invalid prefix \(module)")
            return nil
        }
        targetPath = String(targetPath.dropFirst(2))
        guard targetPath.hasSuffix(module.name) else {
            LogError("Invalid suffix \(module)")
            return nil
        }
        targetPath = String(targetPath.dropLast(module.name.count))

        guard targetPath.hasSuffix(":") else {
            LogError("Invalid suffix : \(module)")
            return nil
        }
        targetPath = String(targetPath.dropLast(1))
        guard let folder = try? root.createSubfolderIfNeeded(at: targetPath) else {
            LogError("Invalid folder \(module)")
            return nil
        }
        return folder
    }

    internal func files(for module: BuckModule, in moduleFolder: Folder) -> [File] {
        var files = [String: File]()
        module.srcs?.compactMap { try? moduleFolder.file(at: $0) }
            .forEach { files[$0.path] = $0 }
        module.headers?.compactMap { try? moduleFolder.file(at: $0) }
            .forEach { files[$0.path] = $0 }
        module.exported_headers?.compactMap { try? moduleFolder.file(at: $0) }
            .forEach { files[$0.path] = $0 }
        return Array(files.values)
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

    internal func loadModuleImports(from files: [File]) throws -> [String] {
        guard !files.isEmpty else { return [] }
        var modules = Set<String>()

        try files.forEach { file in
            let importLines = try file.readAsString()
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let moduleNames = importLines.compactMap { line -> String? in
                guard Self.moduleImportPrefixes.contains(where: { line.hasPrefix($0) }) else {
                    return nil
                }
                let lineWithoutPrefix = Self.moduleImportPrefixes.reduce(line) { newLine, prefix -> String in
                    newLine.replacingOccurrences(of: prefix, with: "")
                }
                return lineWithoutPrefix
                    .components(separatedBy: Self.headerPathCharacterSet)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
            }
            modules.formUnion(moduleNames)
        }
        LogVerbose("Modules\n\(modules)")
        return Array(modules)
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

    internal func parseDependencies(fromTarget target: String, depth: Int? = nil) throws -> [String: BuckModule] {
        let json = try shell.queryBuckDependencies(forTarget: target, depth: depth)
        guard let data = json.data(using: .utf8) else {
            LogError("Failed to convert \(json) into data")
            return [:]
        }
        let module = try JSONSerialization.jsonObject(with: data, options: [])
        guard let moduleDictionaries = module as? [String: [String: Any]] else {
            throw SystemError.failedToParse(reason: "Invalid json \(module)")
        }
        let buckModules = moduleDictionaries.map { BuckModule(target: $0.key, json: $0.value) }
        return buckModules.asMap { $0.target }
    }
}
