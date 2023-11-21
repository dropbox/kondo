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
    internal static let invertedAlphanumerics = CharacterSet.alphanumerics.inverted

    private static let headerPathCharacterSet = CharacterSet(charactersIn: "./")
    private static let moduleImportPrefixes = [
        "#import <",
        "import ",
        "@_implementationOnly import ",
        "@testable import ",
    ]

    public var printOnly = false
    private let graph: Graph
    internal let parser: Parser
    internal let shell: Shell
    internal let rename: Rename

    public init(graph: Graph, parser: Parser, rename: Rename, shell: Shell) {
        self.shell = shell
        self.rename = rename
        self.parser = parser
        self.graph = graph
    }

    public func parseModules(from input: BuckParseInput, rootFolderPath: String) throws {
        try parseModulesImpl(from: input, rootFolderPath: rootFolderPath)
    }

    public func cleanupModule(from input: CleanupInput, rootFolderPath: String) throws {
        try cleanupModuleImpl(from: input, rootFolderPath: rootFolderPath)
    }

    public func createModule(from input: BuckCreateInput, rootFolderPath: String) throws {
        try createModuleImpl(from: input, rootFolderPath: rootFolderPath)
    }

    public func moveModule(from input: BuckMoveInput, rootFolderPath: String) throws {
        try moveModuleImpl(from: input, rootFolderPath: rootFolderPath)
    }

    public func moduleStats(from input: BuckStatsInput, rootFolderPath: String) throws {
        try moduleStatsImpl(from: input, rootFolderPath: rootFolderPath)
    }

    // MARK: - Shared by function impls

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
