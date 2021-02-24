//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation

extension String {
  public func createFolder() throws -> Folder {
    let tempFolder = try Folder(path: FileManager.default.temporaryDirectory.path)
    let testFolder = try tempFolder.createSubfolder(named: self)
    do {
      try testFolder.files.forEach { try $0.delete() }
      try testFolder.subfolders.forEach { try $0.delete() }
    } catch {}
    return testFolder
  }
}
