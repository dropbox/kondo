//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public protocol Shell: AnyObject {
    var buildifierPath: String { get set }
    var buckPath: String { get set }
    var shellPath: String { get set }

    func runBuildifier(on file: File) throws

    func headers(inUmbrellaHeader umbrellaHeader: String) throws -> [String]

    func build(targets: [String], noCache: Bool) throws -> Bool

    func buckFile(forTarget target: String) throws -> String

    func queryBuckDependencies(forTarget target: String, depth: Int?) throws -> String
}
