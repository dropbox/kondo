//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
  [
    testCase(GraphTests.allTests)
  ]
}
#endif
