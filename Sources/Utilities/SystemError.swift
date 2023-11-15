//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation

public enum SystemError: Error {
    case failedToParse(reason: String)
    case invalidJson
    case missingFile
    case unsupported

    public var localizedDescription: String {
        switch self {
        case let .failedToParse(reason): return "Failed to parse due to \(reason)"
        case .invalidJson: return "invalidJson"
        case .missingFile: return "missingFile"
        case .unsupported: return "unsupported"
        }
    }
}
