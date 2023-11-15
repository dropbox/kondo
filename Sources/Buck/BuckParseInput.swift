//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Parser
import Utilities

public struct BuckParseInput: Codable, ReflectedStringConvertible, Equatable {
    public let projectBuildTargets: [String]
    public let overrides: [ParsedFile]?
    public let jsonOutputPath: String?
    public let csvOutputPath: String?

    public init(
        projectBuildTargets: [String],
        overrides: [ParsedFile]? = nil,
        jsonOutputPath: String? = nil,
        csvOutputPath: String? = nil
    ) {
        self.projectBuildTargets = projectBuildTargets
        self.overrides = overrides
        self.jsonOutputPath = jsonOutputPath
        self.csvOutputPath = csvOutputPath
    }
}
