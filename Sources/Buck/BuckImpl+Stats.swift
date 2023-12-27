//
//  Copyright © 2023 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Parser
import Utilities

/// Implementation of `moduleStats(from:rootFolderPath:)` lives here.
extension BuckImpl {
    /// Allowlist for file types to be processed.
    private static let statsFileTypes = [".h", ".hpp", ".c", ".cc", ".cpp", ".swift", ".m", ".mm"]

    public func moduleStatsImpl(from input: BuckStatsInput, rootFolderPath: String) throws {
        LogVerbose("Module stats")
        LogVerbose(input.description)

        let root = try Folder(path: rootFolderPath)
        /// Map each item in `projectBuildTargets` to a set of its deps. Deps are filtered to `input.modules` allowlist if it exists.
        var targetModuleMap = [String: Set<String>]()
        /// Lines-of-code count for each item that made it into `targetModuleMap`.
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

            // These stats are for comparing for than one projectBuildTarget.
            if input.projectBuildTargets.count > 1 {
                /// Mash together a set of all the deps for all the other items in `projectBuildTargets`.
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
        }
        print(output)
    }

    /// Print file count and lines of code count for the given `BuckModule`, return LOC count
    private func stats(for module: BuckModule, root: Folder) throws -> Int {
        guard let moduleFolder = module.folder(root: root) else {
            return 0
        }
        let moduleFiles = module.files(in: moduleFolder)

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
        LogInfo("\(module.target) has \(uniqueFiles.count) files, \(linesOfCode) lines of code")
        return linesOfCode
    }
}
