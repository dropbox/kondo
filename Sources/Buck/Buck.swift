//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public protocol Buck: AnyObject {
    var printOnly: Bool { get set }

    func cleanupModule(from input: CleanupInput, rootFolderPath: String) throws

    func createModule(from input: BuckCreateInput, rootFolderPath: String) throws

    func moveModule(from input: BuckMoveInput, rootFolderPath: String) throws

    func moduleStats(from input: BuckStatsInput, rootFolderPath: String) throws

    func parseModules(from input: BuckParseInput, rootFolderPath: String) throws
}

extension Buck {
    public func cleanupModule(fromJson json: String, rootFolderPath: String = ".") throws {
        let input: CleanupInput = try json.parseJson()
        try cleanupModule(from: input, rootFolderPath: rootFolderPath)
    }

    public func cleanupModule(from input: CleanupInput) throws {
        try cleanupModule(from: input, rootFolderPath: ".")
    }

    public func createModule(fromJson json: String, rootFolderPath: String = ".") throws {
        let input: BuckCreateInput = try json.parseJson()
        try createModule(from: input, rootFolderPath: rootFolderPath)
    }

    public func createModule(from input: BuckCreateInput) throws {
        try createModule(from: input, rootFolderPath: ".")
    }

    public func moveModule(fromJson json: String, rootFolderPath: String = ".") throws {
        let input: BuckMoveInput = try json.parseJson()
        try moveModule(from: input, rootFolderPath: rootFolderPath)
    }

    public func moveModule(from input: BuckMoveInput) throws {
        try moveModule(from: input, rootFolderPath: ".")
    }

    public func moduleStats(fromJson json: String, rootFolderPath: String = ".") throws {
        let input: BuckStatsInput = try json.parseJson()
        try moduleStats(from: input, rootFolderPath: rootFolderPath)
    }

    public func moduleStats(from input: BuckStatsInput) throws {
        try moduleStats(from: input, rootFolderPath: ".")
    }

    public func parseModules(fromJson json: String, rootFolderPath: String = ".") throws {
        let input: BuckParseInput = try json.parseJson()
        try parseModules(from: input, rootFolderPath: rootFolderPath)
    }

    public func parseModules(from input: BuckParseInput) throws {
        try parseModules(from: input, rootFolderPath: ".")
    }
}
