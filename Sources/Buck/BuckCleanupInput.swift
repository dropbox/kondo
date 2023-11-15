//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckCleanupInput: Codable, ReflectedStringConvertible, Equatable {
    public struct CleanupImportsConfig: Codable, ReflectedStringConvertible, Equatable {
        public let expandImports: Bool
        public let reduceImports: Bool
        public let fileTypes: [String]
        public let ignoreEstimatedImports: Bool

        public init(
            expandImports: Bool = false,
            reduceImports: Bool = false,
            fileTypes: [String] = [],
            ignoreEstimatedImports: Bool = false
        ) {
            self.expandImports = expandImports
            self.reduceImports = reduceImports
            self.fileTypes = fileTypes
            self.ignoreEstimatedImports = ignoreEstimatedImports
        }
    }

    public struct CleanupBuckConfig: Codable, ReflectedStringConvertible, Equatable {
        public let reduceBuckDependencies: Bool
        public let ignoreEstimatedDependencies: Bool

        public init(reduceBuckDependencies: Bool = false, ignoreEstimatedDependencies: Bool = false) {
            self.reduceBuckDependencies = reduceBuckDependencies
            self.ignoreEstimatedDependencies = ignoreEstimatedDependencies
        }
    }

    public let projectBuildTargets: [String]
    public let parserResultsPath: String?
    public let modules: [String]?
    public let ignoreModules: [String]?
    public let ignoreFolders: [String]?
    public let cleanupImportsConfig: CleanupImportsConfig
    public let cleanupBuckConfig: CleanupBuckConfig

    public init(
        projectBuildTargets: [String],
        parserResultsPath: String? = nil,
        modules: [String]? = nil,
        ignoreModules: [String]? = nil,
        ignoreFolders: [String]? = nil,
        cleanupImportsConfig: CleanupImportsConfig = CleanupImportsConfig(),
        cleanupBuckConfig: CleanupBuckConfig = CleanupBuckConfig()
    ) {
        self.projectBuildTargets = projectBuildTargets
        self.parserResultsPath = parserResultsPath
        self.modules = modules
        self.ignoreModules = ignoreModules
        self.ignoreFolders = ignoreFolders
        self.cleanupImportsConfig = cleanupImportsConfig
        self.cleanupBuckConfig = cleanupBuckConfig
    }
}
