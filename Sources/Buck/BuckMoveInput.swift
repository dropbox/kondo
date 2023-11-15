//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckMoveInput: Codable, ReflectedStringConvertible, Equatable {
    public struct Path: Codable, Equatable, ReflectedStringConvertible {
        public let source: String
        public let destination: String

        public init(source: String, destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    public let paths: [Path]
    public let ignoreFolders: [String]?

    public init(
        paths: [Path],
        ignoreFolders: [String]? = nil
    ) {
        self.paths = paths
        self.ignoreFolders = ignoreFolders
    }
}
