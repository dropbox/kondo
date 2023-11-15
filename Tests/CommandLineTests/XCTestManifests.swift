//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        [
            testCase(CommandLineTests.allTests),
        ]
    }
#endif
