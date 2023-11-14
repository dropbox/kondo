//
//  File.swift
//
//
//  Created by zjaquish on 11/16/23.
//

import Files
import Foundation
import Parser
import Rename
import Utilities

/// Implementation of `cleanupModule(from:rootFolderPath:)` lives here.
extension BuckImpl {
    /// Allowlist for files to be processed by `reduceImports`.
    private static let importReducerFileTypes = [".h", ".m", ".mm", ".swift"]

    /// Used to determine if a line is an import.
    private static let importReducerPrefixes = ["#import", "import", "@_implementationOnly import", "@testable import"]

    /// Used to determine if an import string is for a related file, like "Foo+Private.h" for "Foo.h"
    private static let categoryFileNameCharacterSet = CharacterSet(charactersIn: "+_")

    /// Denylist for imports to be removed by `reduceImports`.
    private static let ignoreImports = [
        "import Foundation",
        "import UIKit",
        "#import <Foundation/Foundation.h>",
        "#import <UIKit/UIKit.h>",
    ]

    /// The actual implementation.
    internal func cleanupModuleImpl(from input: CleanupInput, rootFolderPath: String) throws {
        LogVerbose("Cleanup module")
        LogVerbose(input.description)

        let buckModules = try loadBuckModules(
            projectBuildTargets: input.projectBuildTargets,
            inputModules: input.modules
        )

        if input.cleanupImportsConfig.expandImports {
            try expandImports(
                for: buckModules,
                excludingPaths: input.ignoreFolders ?? [],
                rootFolderPath: rootFolderPath
            )
        }
        if input.cleanupImportsConfig.reduceImports {
            let parsedFiles = try loadParsedFiles(parserResultsPath: input.parserResultsPath)
            let estimatedImports = input.cleanupImportsConfig.ignoreEstimatedImports
                ? [:]
                : try buildEstimatedImports(with: buckModules, files: parsedFiles, rootFolderPath: rootFolderPath)
            try reduceImports(
                for: buckModules,
                rootFolderPath: rootFolderPath,
                input: input,
                estimatedImports: estimatedImports
            )
        }
        if input.cleanupBuckConfig.reduceBuckDependencies {
            let estimatedDependencies = input.cleanupBuckConfig.ignoreEstimatedDependencies
                ? [:]
                : try buildEstimatedDependencies(with: buckModules, rootFolderPath: rootFolderPath)
            try reduceBuckDependencies(
                for: buckModules,
                rootFolderPath: rootFolderPath,
                input: input,
                estimatedDependencies: estimatedDependencies
            )
        }

        LogInfo("Processing modules:\n\(buckModules.map(\.target).combineWithNewline)")
        LogInfo("Completed cleaning modules.")
    }

    // MARK: Expand Imports

    /// Given a list of `BuckModule`s, replace umbrella headers with individual imports.
    private func expandImports(for modules: [BuckModule], excludingPaths: [String], rootFolderPath: String) throws {
        LogInfo("Expanding imports for \(modules.count) modules")
        let renameItems = try modules.compactMap { module -> RenameInput.Item? in
            guard let moduleName = module.module_name else {
                return nil
            }
            let headers = try shell.headers(inUmbrellaHeader: "\(moduleName).h")
            guard !headers.isEmpty else {
                return nil
            }
            return RenameInput.Item(
                originalText: "#import <\(moduleName)/\(moduleName).h>",
                newText: headers.combineWithNewline.trimmingCharacters(in: .whitespacesAndNewlines),
                fileTypes: [".h", ".m", ".mm"],
                excludingPaths: []
            )
        }
        guard !renameItems.isEmpty else {
            LogInfo("Nothing to rename")
            return
        }
        LogInfo("Created \(renameItems.count) rename items.")
        let renameInput = RenameInput(items: renameItems, excludingPaths: excludingPaths)
        try rename.rename(from: renameInput, rootFolderPath: rootFolderPath)
    }

    // MARK: Reduce Imports

    /// Given a list of `BuckModule`s, attempt to reduce imports on each.
    private func reduceImports(
        for modules: [BuckModule],
        rootFolderPath: String,
        input: CleanupInput,
        estimatedImports: [String: [String]]
    ) throws {
        LogInfo("Reducing imports for \(modules.count) modules")
        let root = try Folder(path: rootFolderPath)
        try modules.forEach { try reduceImports(of: $0, root: root, input: input, estimatedImports: estimatedImports) }
    }

    /// Given a `BuckModule`, iterate through its source files and attempt to reduce imports on each file.
    private func reduceImports(
        of module: BuckModule,
        root: Folder,
        input: CleanupInput,
        estimatedImports: [String: [String]]
    ) throws {
        func order(for file: File) -> Int {
            guard let type = file.extension else { return 0 }
            switch type {
            case "h": return 1
            case "swift": return 2
            default: return 3
            }
        }
        let moduleFiles = try files(for: module, root: root)
            .filter { file -> Bool in Self.importReducerFileTypes.contains(where: { file.name.hasSuffix($0) }) }
            .sorted { $0.path < $1.path }
            .sorted { order(for: $0) < order(for: $1) }

        guard !moduleFiles.isEmpty else { return }

        // Confirm the module is buildable before we try to reduce imports
        guard build(targets: [module.target], noCache: false) else {
            LogError("Failed to build \(module.target), skipping import reduction.")
            return
        }

        try moduleFiles.forEach { file in
            guard
                let fileExtension = file.extension,
                input.cleanupImportsConfig.fileTypes.contains(fileExtension)
            else {
                LogInfo("Skipped \(file.path) since the extension is not in the cleanupImportsConfig.fileTypes allowlist")
                return
            }
            let targets: [String]
            if Self.headerFiles.contains(where: { file.name.hasSuffix($0) }) {
                // changing a header file's imports breaks downstream dependencies
                // so we need to try rebuilding the world.
                targets = input.projectBuildTargets
            } else {
                targets = [module.target]
            }
            try autoreleasepool {
                try reduceImports(
                    of: file,
                    root: root,
                    projectBuildTargets: targets,
                    estimatedImports: estimatedImports
                )
            }
        }

        LogInfo("Reduced imports for \(moduleFiles.count) files in \(module.target)")
    }

    /// Given a single `File`, attempt to reduce imports by removing one import at a time and then checking to see
    /// if all downstream dependencies (precalculated and passed in as `projectBuildTargets`) can stil lbuild.
    private func reduceImports(
        of file: File,
        root: Folder,
        projectBuildTargets: [String],
        estimatedImports: [String: [String]]
    ) throws {
        LogInfo("Reducing imports for \(file.path)")
        let originalContent = try file.readAsString()
        var content = originalContent.components(separatedBy: .newlines)
        guard !content.isEmpty else { return }
        let ignoreHeaderFilePrefixes: [String]
        let ignoreHeaderFileSuffixes: [String]
        if let fileName = file.nameExcludingExtension.components(separatedBy: Self.categoryFileNameCharacterSet).first {
            ignoreHeaderFilePrefixes = [
                "#import \"\(fileName).",
                "#import \"\(fileName)+",
                "#import \"\(fileName)_",
            ]
            ignoreHeaderFileSuffixes = [
                "/\(fileName).h>",
            ]
        } else {
            ignoreHeaderFilePrefixes = []
            ignoreHeaderFileSuffixes = []
        }
        let ignoreImports = estimatedImports[file.path(relativeTo: root)] ?? []
        var index = 0
        var changed = false
        repeat {
            // Read one line at a time
            guard let line = content.at(index) else {
                break
            }
            // Skip this line if it doesn't look like an import line
            guard Self.importReducerPrefixes.contains(where: { line.hasPrefix($0) }) else {
                index += 1
                continue
            }
            // Skip this line if the import is in our global ignore list (ex: "import Foundation")
            guard !Self.ignoreImports.contains(where: { line.hasPrefix($0) }) else {
                index += 1
                continue
            }
            // Skip this line if the import is for paired files (ex: "import Foo+Private.h")
            guard !ignoreHeaderFilePrefixes.contains(where: { line.hasPrefix($0) }) else {
                index += 1
                continue
            }
            // Skip this line if we are in Foo.m and importing Foo.h
            guard !ignoreHeaderFileSuffixes.contains(where: { line.hasSuffix($0) }) else {
                index += 1
                continue
            }
            // Skip this line if our precalculated analysis (estimatedImports) says that we need this import
            guard !ignoreImports.contains(where: { line == $0 }) else {
                index += 1
                continue
            }

            // remove the import line
            content.remove(at: index)
            try file.store(content.combineWithNewline)

            // attempt to build all projectBuildTargets, and save the line removal if successful
            guard build(targets: projectBuildTargets, noCache: false) else {
                content.insert(line, at: index)
                try file.store(content.combineWithNewline)
                index += 1
                continue
            }
            changed = true
            LogInfo("Successfully removed \(line) from \(file.path)")
        } while
            index < content.count

        guard changed else {
            try file.store(originalContent)
            return
        }
        LogInfo("Reduced imports for \(file.path)")
    }

    /// Use the results of the `parser` command to increase the efficiency of `reduceImports`.
    ///
    /// Returns a mapping of filepath --> to an array of imports that cannot be removed.
    /// example key-value:
    /// ```
    /// "app/zoo/ZooImpl.swift" : ["#import Giraffe.h", ...]
    /// ```
    private func buildEstimatedImports(
        with modules: [BuckModule],
        files: [ParsedFile],
        rootFolderPath: String
    ) throws -> [String: [String]] {
        LogInfo("Building estimated imports with \(modules.count) modules and \(files.count) files")
        let root = try Folder(path: rootFolderPath)

        ///  "utilities/fun_module/FunImpl.swift" --> BuckModule(...)
        var fileModuleMap = [String: BuckModule]()
        ///  "utilities/fun_module/FunImpl.swift" --> File(...)
        var fileMap = [String: File]()

        // Calculate fileModuleMap and fileMap.
        try modules.forEach { module in
            let moduleFiles = try self.files(for: module, root: root)
            moduleFiles.forEach { file in
                fileModuleMap[file.path(relativeTo: root)] = module
                fileMap[file.path(relativeTo: root)] = file
            }
        }

        // For all defined types, calculate all possible import strings that would be used to import that type.
        // For example, if "FooImpl" is defined in "FooImpl.h", then:
        // typeImportMap["FooImpl"] == ["#import FooImpl.h", "#import <FooModule/FooImpl.h>", ...]
        let typeImportMap = files.reduce(into: [String: [String]]()) { result, parsedFile in
            guard let module = fileModuleMap[parsedFile.filePath] else {
                LogError("Missing module for \(parsedFile.filePath)")
                return
            }
            var moduleName = module.module_name
            if moduleName == nil, module.isSwiftOnly {
                moduleName = module.name
            }
            guard let file = fileMap[parsedFile.filePath] else {
                LogError("Missing file for \(parsedFile.filePath)")
                return
            }
            parsedFile.definedTypeNames.forEach { typeName in
                guard result[typeName] == nil else {
                    LogError("Found duplicate entry for \(typeName) in \(parsedFile.filePath)")
                    return
                }
                let typeArray: [String]
                if let moduleName = moduleName {
                    typeArray = [
                        "#import \"\(file.name)\"",
                        "#import <\(moduleName)/\(file.name)>",
                        "import \(moduleName).\(file.name)",
                        "import \(moduleName)",
                    ]
                } else {
                    typeArray = [
                        "#import \"\(file.name)\"",
                    ]
                }
                result[typeName] = typeArray
            }
        }
        print("typeImportMap=\(typeImportMap))")

        // Using typeImportMap, map each filePath to the list of all import strings that cannot be removed
        let estimatedImports = files.reduce(into: [String: [String]]()) { result, file in
            result[file.filePath] = file.requiredTypeNames.flatMap { typeImportMap[$0] ?? [] }
        }
        return estimatedImports
    }

    private func loadParsedFiles(parserResultsPath: String?) throws -> [ParsedFile] {
        guard let parserResultsPath = parserResultsPath else {
            LogWarn("Run the parser first and pass in the json results file to speed up import reduction")
            return []
        }
        let sourceFile = try File(path: parserResultsPath)
        let json = try sourceFile.readAsString()
        let parserOutput: ParserListTypesOutput = try json.parseJson()
        return parserOutput.files
    }

    // MARK: Reduce Buck Dependencies

    /// Given a list of `BuckModule`s, attempt to reduce buck dependencies on each.
    private func reduceBuckDependencies(
        for modules: [BuckModule],
        rootFolderPath: String,
        input: CleanupInput,
        estimatedDependencies: [String: [String]]
    ) throws {
        LogInfo("Reducing dependencies for \(modules.count) modules")

        // Confirm the world is buildable before we try to reduce imports
        guard build(targets: input.projectBuildTargets, noCache: false) else {
            LogError("Failed to build projects, skipping dependency reduction.")
            return
        }
        let validDependencyRemovals = Set(modules.map(\.target))

        let root = try Folder(path: rootFolderPath)
        try modules.forEach { module in
            try autoreleasepool {
                try reduceBuckDependencies(
                    of: module,
                    root: root,
                    input: input,
                    estimatedDependencies: estimatedDependencies,
                    validDependencyRemovals: validDependencyRemovals
                )
            }
        }
    }

    /// Given a `BuckModule`, attempt to reduce buck dependencies (deps and export_deps).
    private func reduceBuckDependencies(
        of module: BuckModule,
        root: Folder,
        input: CleanupInput,
        estimatedDependencies: [String: [String]],
        validDependencyRemovals: Set<String>
    ) throws {
        LogInfo("Reducing dependencies for \(module.target)")
        guard let buckFilePath = module.buckFilePath else {
            LogError("Missing BUCK file for \(module.target), skipping dependency reduction.")
            return
        }
        let file = try root.file(at: buckFilePath)
        let originalContent = try file.readAsString()

        guard !originalContent.isEmpty else { return }

        var buckFile = BuckFile(
            path: buckFilePath.replacingOccurrences(of: "/BUCK", with: ""),
            fileContent: originalContent
        )

        guard var buckModule = buckFile.buckModules[module.target] else {
            LogError("Missing buck module for \(module.target), skipping dependency reduction.")
            return
        }
        guard let targetBasePath = module.target.components(separatedBy: ":").first else {
            LogError("Invalid target \(module.target)")
            return
        }

        let ignoreDependencies = estimatedDependencies[module.target] ?? []

        func saveBuckFile() throws {
            buckFile.buckModules[module.target] = buckModule
            try file.store(buckFile.text)
            try shell.runBuildifier(on: file)
            Thread.sleep(forTimeInterval: 5)
        }
        /// Determine if dep should be considered for removal.
        func shouldProcess(dependency: String) -> Bool {
            var dependency = dependency
            // If the CPP code is available during linking buck builds fine unlike the obj-c/swift code
            guard dependency != ":cpp" else {
                return false
            }
            // Normalize shortcut dependencies
            if dependency.hasPrefix(":") {
                dependency = targetBasePath + dependency
            }
            guard !ignoreDependencies.contains(dependency) else {
                return false
            }
            // Prevent removal of non source based modules (e.g. asset dependencies)
            guard validDependencyRemovals.contains(dependency) else {
                return false
            }
            return true
        }
        /// Iterate over the given list of deps or exported_deps, attempt to remove each.
        func processDeps(depsPath: WritableKeyPath<RawBuckModule, [String]>) throws -> Bool {
            var changed = false
            var index = 0
            repeat {
                guard !buckModule[keyPath: depsPath].isEmpty else { break }
                let dependency = buckModule[keyPath: depsPath][index]

                guard shouldProcess(dependency: dependency) else {
                    index += 1
                    continue
                }
                buckModule[keyPath: depsPath].remove(at: index)
                try saveBuckFile()

                // Check if the module and downstream targets still build after removal
                guard build(targets: input.projectBuildTargets, noCache: true) else {
                    buckModule[keyPath: depsPath].insert(dependency, at: index)
                    try saveBuckFile()
                    index += 1
                    continue
                }
                changed = true
                LogInfo("Successfully removed \(dependency) from \(module.target)")
            } while index < buckModule[keyPath: depsPath].count
            return changed
        }

        let changedExportedDeps = try processDeps(depsPath: \RawBuckModule.exported_deps)
        let changedDeps = try processDeps(depsPath: \RawBuckModule.deps)

        guard changedDeps || changedExportedDeps else {
            try file.store(originalContent)
            return
        }
        LogInfo("Reduced dependencies for \(module.target)")
    }

    /// Use the results of the `parser` command to increase the efficiency of `reduceBuckDependencies`.
    ///
    /// Returns a mapping of buck target name --> array of buck target name deps that should not be be removed.
    /// Estimated dependencies are calculated by scanning the code files for import lines. This implies that unused import lines
    /// will reduce the effectiveness of `reduceBuckDependencies`, so you should run `reduceImports` first.
    ///
    /// example key-value:
    /// ```
    /// "//app/utilities/zoo:impl" : ["//app/utilities/zoo:interface", ...]
    /// ```
    private func buildEstimatedDependencies(
        with modules: [BuckModule],
        rootFolderPath: String
    ) throws -> [String: [String]] {
        LogInfo("Building estimated dependencies with \(modules.count) modules files")
        let root = try Folder(path: rootFolderPath)
        let moduleNameMap = modules.asMap { $0.module_name ?? "" }

        let estimatedDependencies = try modules.reduce(into: [String: [String]]()) { result, module in
            let moduleFiles = try self.files(for: module, root: root)
            let allModuleNames = try loadModuleImports(from: moduleFiles)
            let targets = Set(allModuleNames).compactMap { moduleNameMap[$0]?.target }
            result[module.target] = targets
        }
        return estimatedDependencies
    }

    // MARK: Common

    // TODO(zjaquish): Determine purpose of projectBuildTargets vs inputModules
    private func loadBuckModules(projectBuildTargets: [String], inputModules: [String]?) throws -> [BuckModule] {
        var moduleMap = [String: BuckModule]()
        try projectBuildTargets.map { try parseDependencies(fromTarget: $0) }.forEach { map in
            moduleMap.merge(map, uniquingKeysWith: { old, _ in old })
        }
        moduleMap = moduleMap.filter(\.value.hasFiles)
            .filter { !$0.key.hasPrefix("//dbx/external") }
            .filter { !$0.key.hasPrefix("//shared/passwords/Pods") }
        var modules: [String]
        if let moduleList = inputModules, !moduleList.isEmpty {
            modules = moduleList
        } else {
            modules = orderModules(from: moduleMap)
            // Build target deps are not properly represented
            modules = modules.filter { !projectBuildTargets.contains($0) }
            modules.append(contentsOf: projectBuildTargets)
        }
        let buckModules = modules.compactMap { moduleMap[$0] }
        return buckModules
    }

    /// Orders the modules so that a module appears prior to any of its dependencies.
    private func orderModules(from moduleMap: [String: BuckModule]) -> [String] {
        var unprocessedModules = Set(moduleMap.keys)
        var orderedModules = [String]()
        while orderedModules.count != moduleMap.count {
            for (key, module) in moduleMap where unprocessedModules.contains(key) {
                guard unprocessedModules.intersection(module.deps ?? []).count == 0 else {
                    continue
                }
                orderedModules.append(key)
                unprocessedModules.remove(key)
            }
        }
        return orderedModules
    }
}
