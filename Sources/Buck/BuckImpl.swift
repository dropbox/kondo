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
  private static let categoryFileNameCharacterSet = CharacterSet(charactersIn: "+_")
  private static let headerPathCharacterSet = CharacterSet(charactersIn: "./")
  private static let invertedAlphanumerics = CharacterSet.alphanumerics.inverted
  private static let headerFiles = [".h"]
  private static let sourceFiles = [".swift", ".m", ".mm"]
  private static let parseableFileTypes = [".h", ".m", ".mm", ".swift"]
  private static let importReducerFileTypes = [".h", ".m", ".mm", ".swift"]
  private static let statsFileTypes = [".h", ".hpp", ".c", ".cc", ".cpp", ".swift", ".m", ".mm"]
  private static let importReducerPrefixes = ["#import", "import", "@_implementationOnly import", "@testable import"]
  private static let moduleImportPrefixes = [
    "#import <",
    "import ",
    "@_implementationOnly import ",
    "@testable import "
  ]
  private static let ignoreImports = [
    "import Foundation",
    "import UIKit",
    "#import <Foundation/Foundation.h>",
    "#import <UIKit/UIKit.h>"
  ]

  public var printOnly = false
  private let graph: Graph
  private let parser: Parser
  private let shell: Shell
  private let rename: Rename

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

  public func cleanupModule(from input: BuckCleanupInput, rootFolderPath: String) throws {
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
    LogVerbose("Module stats")
    LogVerbose(input.description)

    let root = try Folder(path: rootFolderPath)
    var targetModuleMap = [String: Set<String>]()
    var moduleLinesOfCodeMap = [String: Int]()

    for projectTarget in input.projectBuildTargets {
      var targetModules = Set<String>()
      let libraries = try parseDependencies(fromTarget: projectTarget)
      try libraries.values.forEach { library in
        if let validModules = input.modules {
          guard validModules.contains(library.target) else {
            return
          }
        }
        targetModules.insert(library.target)
        guard moduleLinesOfCodeMap[library.target] == nil else {
          return
        }

        let linesOfCode = try stats(for: library, root: root)
        moduleLinesOfCodeMap[library.target] = linesOfCode
      }
      targetModuleMap[projectTarget] = targetModules
    }
    var output = ""
    for projectTarget in input.projectBuildTargets {
      output += "\n\n\(projectTarget)\n"
      guard let modules = targetModuleMap[projectTarget] else {
        LogError("Missing modules for \(projectTarget)")
        continue
      }

      output += "Total modules \(modules.count)\n"

      let totalLinesOfCode = modules.reduce(0) { $0 + (moduleLinesOfCodeMap[$1] ?? 0) }
      output += "Total lines of code \(totalLinesOfCode)\n"

      let otherModules = targetModuleMap.reduce(Set<String>()) { set, pair -> Set<String> in
        guard pair.key != projectTarget else {
          return set
        }
        return set.union(pair.value)
      }

      let sharedModules = modules.intersection(otherModules)
      output += "Shared modules \(sharedModules.count)\n"

      let sharedModuleCode = sharedModules.reduce(0) { $0 + (moduleLinesOfCodeMap[$1] ?? 0) }
      let sharedModuleCodePercent = Int(100.0 * Double(sharedModuleCode) / Double(totalLinesOfCode))
      output += "Shared modules lines of code \(sharedModuleCode) (\(sharedModuleCodePercent)%)\n"

      let uniqueModules = modules.subtracting(otherModules)
      output += "Unique modules \(uniqueModules.count)\n"

      let uniqueModulesCode = uniqueModules.reduce(0) { $0 + (moduleLinesOfCodeMap[$1] ?? 0) }
      let uniqueModulesCodePercent = 100 - sharedModuleCodePercent
      output += "Unique modules lines of code \(uniqueModulesCode) (\(uniqueModulesCodePercent)%)\n"
    }
    print(output)
  }

  // MARK: - Private

  private func loadBuckModules(projectBuildTargets: [String], inputModules: [String]?) throws -> [BuckModule] {
    var moduleMap = [String: BuckModule]()
    try projectBuildTargets.map { try parseDependencies(fromTarget: $0) }.forEach { map in
      moduleMap.merge(map, uniquingKeysWith: { old, _ in old })
    }
    moduleMap = moduleMap.filter { $0.value.hasFiles }
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

  private func buildEstimatedImports(
    with modules: [BuckModule],
    files: [ParsedFile],
    rootFolderPath: String
  ) throws -> [String: [String]] {
    LogInfo("Building estimated imports with \(modules.count) modules and \(files.count) files")
    let root = try Folder(path: rootFolderPath)
    var fileModuleMap = [String: BuckModule]()
    var fileMap = [String: File]()
    try modules.forEach { module in
      let moduleFiles = try self.files(for: module, root: root)
      moduleFiles.forEach { file in
        fileModuleMap[file.path(relativeTo: root)] = module
        fileMap[file.path(relativeTo: root)] = file
      }
    }
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
            "import \(moduleName)"
          ]
        } else {
          typeArray = [
            "#import \"\(file.name)\""
          ]
        }
        result[typeName] = typeArray
      }
    }
    let estimatedImports = files.reduce(into: [String: [String]]()) { result, file in
      result[file.filePath] = file.requiredTypeNames.flatMap { typeImportMap[$0] ?? [] }
    }
    return estimatedImports
  }

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

  private func reduceBuckDependencies(
    for modules: [BuckModule],
    rootFolderPath: String,
    input: BuckCleanupInput,
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

  private func reduceBuckDependencies(
    of module: BuckModule,
    root: Folder,
    input: BuckCleanupInput,
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

  private func reduceImports(
    for modules: [BuckModule],
    rootFolderPath: String,
    input: BuckCleanupInput,
    estimatedImports: [String: [String]]
  ) throws {
    LogInfo("Reducing imports for \(modules.count) modules")
    let root = try Folder(path: rootFolderPath)
    try modules.forEach { try reduceImports(of: $0, root: root, input: input, estimatedImports: estimatedImports) }
  }

  private func reduceImports(
    of module: BuckModule,
    root: Folder,
    input: BuckCleanupInput,
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
        "#import \"\(fileName)_"
      ]
      ignoreHeaderFileSuffixes = [
        "/\(fileName).h>"
      ]
    } else {
      ignoreHeaderFilePrefixes = []
      ignoreHeaderFileSuffixes = []
    }
    let ignoreImports = estimatedImports[file.path(relativeTo: root)] ?? []
    var index = 0
    var changed = false
    repeat {
      guard let line = content.at(index) else {
        break
      }
      guard Self.importReducerPrefixes.contains(where: { line.hasPrefix($0) }) else {
        index += 1
        continue
      }
      guard !Self.ignoreImports.contains(where: { line.hasPrefix($0) }) else {
        index += 1
        continue
      }
      // Skip the header files paired with this file
      guard !ignoreHeaderFilePrefixes.contains(where: { line.hasPrefix($0) }) else {
        index += 1
        continue
      }
      guard !ignoreHeaderFileSuffixes.contains(where: { line.hasSuffix($0) }) else {
        index += 1
        continue
      }
      guard !ignoreImports.contains(where: { line == $0 }) else {
        index += 1
        continue
      }

      content.remove(at: index)
      try file.store(content.combineWithNewline)

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

  // Orders the modules so that a module appears prior to any of its dependencies.
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

  private func build(targets: [String], noCache: Bool) -> Bool {
    do {
      return try shell.build(targets: targets, noCache: noCache)
    } catch {
      LogVerbose("Build error \(error)")
      return false
    }
  }

  private func files(for module: BuckModule, root: Folder) throws -> [File] {
    guard let moduleFolder = folder(for: module, root: root) else {
      LogInfo("Failed to reduce imports for \(module.name), invalid folder")
      return []
    }
    let moduleFiles = files(for: module, in: moduleFolder)
      .sorted { $0.path < $1.path }
    return moduleFiles
  }

  private func folder(for module: BuckModule, root: Folder) -> Folder? {
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

  private func files(for module: BuckModule, in moduleFolder: Folder) -> [File] {
    var files = [String: File]()
    module.srcs?.compactMap { try? moduleFolder.file(at: $0) }
      .forEach { files[$0.path] = $0 }
    module.headers?.compactMap { try? moduleFolder.file(at: $0) }
      .forEach { files[$0.path] = $0 }
    module.exported_headers?.compactMap { try? moduleFolder.file(at: $0) }
      .forEach { files[$0.path] = $0 }
    return Array(files.values)
  }

  private func stats(for module: BuckModule, root: Folder) throws -> Int {
    guard let moduleFolder = folder(for: module, root: root) else {
      return 0
    }
    let moduleFiles = files(for: module, in: moduleFolder)

    let uniqueFiles = moduleFiles
      .filter { file -> Bool in Self.statsFileTypes.contains(where: { file.name.hasSuffix($0) }) }
    let linesOfCode = uniqueFiles.reduce(0) { total, file -> Int in
      let content = try? file.readAsString()
      let lines = content?
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .count ?? 0
      if lines > 5_000 {
        LogInfo("Huge file \(file.path) with \(lines)")
      }
      return total + lines
    }
    LogInfo("\(module.target) has \(uniqueFiles.count) files \(linesOfCode)")
    return linesOfCode
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

  private func loadModuleImports(from files: [File]) throws -> [String] {
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

  private func parseDependencies(fromTarget target: String, depth: Int? = nil) throws -> [String: BuckModule] {
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
