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

public class BuckFake: Buck {
    public var printOnly: Bool = false

    public var cleanupModuleInput: BuckCleanupInput?
    public var createModuleInput: BuckCreateInput?
    public var moveModuleInput: BuckMoveInput?
    public var moduleStatsInput: BuckStatsInput?
    public var parseModulesInput: BuckParseInput?

    public init() {}

    public func cleanupModule(from input: BuckCleanupInput, rootFolderPath _: String) throws {
        cleanupModuleInput = input
    }

    public func createModule(from input: BuckCreateInput, rootFolderPath _: String) throws {
        createModuleInput = input
    }

    public func moveModule(from input: BuckMoveInput, rootFolderPath _: String) throws {
        moveModuleInput = input
    }

    public func moduleStats(from input: BuckStatsInput, rootFolderPath _: String) throws {
        moduleStatsInput = input
    }

    public func parseModules(from input: BuckParseInput, rootFolderPath _: String) throws {
        parseModulesInput = input
    }
}

public class GraphFake: Graph {
    public var printOnly = false

    public init() {}
    public func graph(from _: GraphInput, rootFolderPath _: String) throws {}
}

public class ParserFake: Parser {
    public var cachePath: String?

    public var printOnly = false

    public init() {}

    public func listTypes(from _: ParserListTypesInput, rootFolderPath _: String) throws -> ParserListTypesOutput {
        ParserListTypesOutput(files: [])
    }
}

public class RenameFake: Rename {
    public var printOnly = false
    public var input: RenameInput?

    public init() {}

    public func rename(from input: RenameInput, rootFolderPath _: String) throws {
        self.input = input
    }
}

public class ShellFake: Shell {
    public var shellPath: String = ""
    public var buildifierPath: String = ""
    public var buckPath: String = ""
    public var parseAppleLibrariesOutput =
        """
        {
          "//ios/app:app" : {
            "frameworks" : [
              "$SDKROOT/System/Library/Frameworks/CFNetwork.framework",
              "$SDKROOT/System/Library/Frameworks/Contacts.framework",
              "$SDKROOT/System/Library/Frameworks/CoreGraphics.framework",
              "$SDKROOT/System/Library/Frameworks/Foundation.framework",
              "$SDKROOT/System/Library/Frameworks/ImageIO.framework",
              "$SDKROOT/System/Library/Frameworks/UIKit.framework"
            ],
            "name" : "app"
          },
          "//ios/common/logging:logging" : {
            "frameworks" : [
              "$SDKROOT/System/Library/Frameworks/Foundation.framework"
            ],
            "module_name" : "ios_common_logging",
            "name" : "logging"
          },
          "//ios/common/utilities:utilities" : {
            "frameworks" : [
              "$SDKROOT/System/Library/Frameworks/Foundation.framework",
              "$SDKROOT/System/Library/Frameworks/UIKit.framework"
            ],
            "module_name" : "ios_common_utilities",
            "name" : "utilities"
          },
        }
        """

    public init() {}

    public func runBuildifier(on _: File) throws {}

    public func queryBuckDependencies(forTarget _: String, depth _: Int?) throws -> String {
        parseAppleLibrariesOutput
    }

    public func buckFile(forTarget _: String) throws -> String {
        fatalError("unsupported")
    }

    public func headers(inUmbrellaHeader _: String) throws -> [String] {
        fatalError("unsupported")
    }

    public func build(targets _: [String], noCache _: Bool) throws -> Bool {
        fatalError("unsupported")
    }
}
