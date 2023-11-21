//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Parser
import Utilities

/// Configuration for the `buckParse` command, usually parsed from a json file.
/// This is layered on top of the `parse` command. The main difference is that `buckParse` input takes a
/// list of `projectBuildTargets`, which are mapped to filepaths and then passed to `parse`.
public struct BuckParseInput: Codable, ReflectedStringConvertible, Equatable {
    /// The parser will parse all modules in projectBuildTargets and all deps.
    public let projectBuildTargets: [String]

    /// Override parsing results on a per-file basis.
    public let overrides: [ParsedFile]?

    /// Filepath for writing full parser output. This file is consumed by `refactor cleanup` to speed up processing.
    public let jsonOutputPath: String?

    /// Filepath for writing a subset of the output, which is more human-readable. A table in the form |File Path|Type Count|Types|
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
