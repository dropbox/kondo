//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct ParsedFile: Codable, ReflectedStringConvertible, Equatable, Hashable {
    // TODO: Include a list of defined functions for each time and a list of required functions on each type
    // In order to properly support Categories and Protocol Extensions that exist in different modules
    // then the original protocol itself.
    public let filePath: String
    public var definedTypeNames: [String]
    public var requiredTypeNames: [String]
    public let error: String?

    public init(
        filePath: String,
        definedTypeNames: [String],
        requiredTypeNames: [String],
        error: String?
    ) {
        self.filePath = filePath
        self.definedTypeNames = definedTypeNames
        self.requiredTypeNames = requiredTypeNames
        self.error = error
    }
}
