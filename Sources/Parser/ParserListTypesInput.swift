//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

/// Convenience type for bundling together the parameters passed to `parser.listTypes(...)`
public struct ParserListTypesInput: Codable, ReflectedStringConvertible, Equatable {
    /// List of filepaths to parse.
    public let filePaths: [String]

    /// Override parsing results on a per-file basis.
    public let overrides: [ParsedFile]?

    /// Filepath for writing full parser output. This file is consumed by `refactor cleanup` to speed up processing.
    public let jsonOutputPath: String?

    /// Filepath for writing a subset of the output, which is more human-readable. A table in the form |File Path|Type Count|Types|
    public let csvOutputPath: String?

    public init(filePaths: [String], overrides: [ParsedFile]?, jsonOutputPath: String?, csvOutputPath: String?) {
        self.filePaths = filePaths
        self.overrides = overrides
        self.jsonOutputPath = jsonOutputPath
        self.csvOutputPath = csvOutputPath
    }
}
