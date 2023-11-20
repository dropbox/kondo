//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

/// Configuration for the `stats` command, usually parsed from a json file.
public struct BuckStatsInput: Codable, ReflectedStringConvertible, Equatable {
    /// The list of modules to analyze.
    public let projectBuildTargets: [String]
    /// If set, only the projectBuildTargets deps that match this allowlist will be analyzed. You probably don't want this.
    public let modules: [String]?

    public init(
        projectBuildTargets: [String],
        modules: [String]? = nil
    ) {
        self.projectBuildTargets = projectBuildTargets
        self.modules = modules
    }
}
