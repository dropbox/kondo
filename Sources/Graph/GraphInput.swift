//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct GraphInput: Codable, ReflectedStringConvertible, Equatable {
    public struct GraphNode: Codable, ReflectedStringConvertible, Equatable {
        public let id: String
        public let dependentIDs: [String]

        public init(
            id: String,
            dependentIDs: [String]
        ) {
            self.id = id
            self.dependentIDs = dependentIDs
        }
    }

    public let nodes: [GraphNode]

    public init(nodes: [GraphNode]) {
        self.nodes = nodes
    }
}
