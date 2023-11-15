//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct ParserListTypesOutput: Codable, ReflectedStringConvertible, Equatable {
    public let files: [ParsedFile]

    public init(files: [ParsedFile]) {
        self.files = files
    }
}
