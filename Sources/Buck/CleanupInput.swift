//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

/// Configuration for the `cleanup` command, usually parsed from a json file.
public struct CleanupInput: Codable, ReflectedStringConvertible, Equatable {
    /// Configuration specific to refactoring imports in code files.
    public struct CleanupImportsConfig: Codable, ReflectedStringConvertible, Equatable {
        /**
         If true, replace umbrella imports in C-ish language files with the individual ones.

         For example, the umbrella import:
         ```
         #import <AnimalsModule/AnimalsModule.h
         ```
         will be replaced by:
         ```
         #import <FooModule/Cat.h>
         #import <FooModule/Dog.h>
         #import <FooModule/Fish.h>
         ```

         The intention is to reduce compile times by only importing symbols that you need, instead of using umbrella headers.
         This requires the additonal step of deleting unused imports after expansion.
         */
        public let expandImports: Bool

        /**
         If true, remove unused imports from code files. This works on both C/Obj-C/C++ and Swift files.
         An import is considered unused if it can be removed while still being to able compile the module and all downstream modules.
         - Standard imports like Foundation and UIKit are never removed.
         - Imports of related categories (such as "Foo+Extensions.h" imported from your "Foo.h") are never removed

         For example, a swift file:
         ```
         import Foundation
         import Foo
         import Bar

         class Baz: Foo {}
         ```
         will be replaced by:
         ```
         import Foundation
         import Foo

         class Baz: Foo {}
         ```
         */
        public let reduceImports: Bool

        /**
         An allowlist of files to be processed by  `expandImports` or `reduceImports`. If empty, no files will be processed.
         Note that these should be just the extension, without the dot- i.e. "h", NOT ".h"
         */
        public let fileTypes: [String]

        /// A denylist of folders to be processed by  `expandImports`.
        public let ignoreFolders: [String]?

        /**
          If `false`, you are expected to pass in parser results via`parserResultsPath` to generate `estimatedImports`.
          `estimatedImports` speeds up the time to run `reduceImports` by skipping over imports that are known to be required.
         */
        public let ignoreEstimatedImports: Bool

        /// Folder of results previously generated via the `refactor parser` command.
        public let parserResultsPath: String?

        public init(
            expandImports: Bool = false,
            reduceImports: Bool = false,
            fileTypes: [String] = [],
            ignoreFolders: [String]? = nil,
            ignoreEstimatedImports: Bool = false,
            parserResultsPath: String? = nil
        ) {
            self.expandImports = expandImports
            self.reduceImports = reduceImports
            self.fileTypes = fileTypes
            self.ignoreFolders = ignoreFolders
            self.ignoreEstimatedImports = ignoreEstimatedImports
            self.parserResultsPath = parserResultsPath
        }
    }

    /// Configuration specific to refactoring deps in buck files.
    public struct CleanupBuckConfig: Codable, ReflectedStringConvertible, Equatable {
        public let reduceBuckDependencies: Bool

        /**
          If `true`, generate an `estimatedDependencies` list from scanning the code files of the modules being processed.
          `estimatedDependencies` speeds up the time to run `reduceBuckDependencies` by skipping over deps that are known to be required.
         */
        public let ignoreEstimatedDependencies: Bool

        public init(reduceBuckDependencies: Bool = false, ignoreEstimatedDependencies: Bool = false) {
            self.reduceBuckDependencies = reduceBuckDependencies
            self.ignoreEstimatedDependencies = ignoreEstimatedDependencies
        }
    }

    /// Root nodes of module trees to be processed by expandImports, reduceImports, reduceDeps
    public let projectBuildTargets: [String]
    /// Manual list of modules to be processed by expandImports, reduceImports, reduceDeps
    /// Must be in `projectBuildTargets`. Unclear why this exists.
    public let modules: [String]?

    /// The subconfig for expanding and reducing imports, as specified above.
    public let cleanupImportsConfig: CleanupImportsConfig

    /// The subconfig for reducing buck dependencies, as specified above.
    public let cleanupBuckConfig: CleanupBuckConfig

    public init(
        projectBuildTargets: [String],
        modules: [String]? = nil,
        cleanupImportsConfig: CleanupImportsConfig = CleanupImportsConfig(),
        cleanupBuckConfig: CleanupBuckConfig = CleanupBuckConfig()
    ) {
        self.projectBuildTargets = projectBuildTargets
        self.modules = modules
        self.cleanupImportsConfig = cleanupImportsConfig
        self.cleanupBuckConfig = cleanupBuckConfig
    }
}
