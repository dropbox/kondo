//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckStatsInput: Codable, ReflectedStringConvertible, Equatable {
    public let projectBuildTargets: [String]
    public let modules: [String]?
    public let ignoreModules: [String]?

    public init(
        projectBuildTargets: [String],
        modules: [String]? = nil,
        ignoreModules: [String]? = nil
    ) {
        self.projectBuildTargets = projectBuildTargets
        self.modules = modules
        self.ignoreModules = ignoreModules
    }
}
