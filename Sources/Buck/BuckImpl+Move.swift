//
//  Copyright © 2023 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Rename
import Utilities

/// Implementation of `moveModule(from:rootFolderPath:)` lives here.
extension BuckImpl {
    public func moveModuleImpl(from input: BuckMoveInput, rootFolderPath: String) throws {
        LogVerbose("Moving module \(input.description)")
        let root = try Folder(path: rootFolderPath)
        let excludingPaths = input.ignoreFolders ?? []
        var renameItems = [RenameInput.Item]()

        try input.paths.forEach { path in
            let sourcePath = path.source.trimmingCharacters(in: Self.invertedAlphanumerics)
            let source = try root.subfolder(at: sourcePath)
            let destinationPath = path.destination.trimmingCharacters(in: Self.invertedAlphanumerics)
            let destination = try root.createSubfolderIfNeeded(at: destinationPath)

            let sourceNameFromPath = sourcePath.replacingOccurrences(of: "/", with: "_").lowercased()
            let destinationNameFromPath = destinationPath.replacingOccurrences(of: "/", with: "_").lowercased()

            if printOnly {
                print("mv \(sourcePath) to \(destinationPath)")
            } else {
                try source.moveContents(to: destination, includeHidden: true)
            }

            renameItems.append(
                RenameInput.Item(
                    originalText: sourceNameFromPath,
                    newText: destinationNameFromPath,
                    fileTypes: [".h", ".m", ".mm", ".swift", "BUCK"],
                    excludingPaths: []
                )
            )
            renameItems.append(
                RenameInput.Item(
                    originalText: sourcePath,
                    newText: destinationPath,
                    fileTypes: [".bzl", "BUCK", ".bmbf.yaml"],
                    excludingPaths: []
                )
            )
        }
        let renameInput = RenameInput(items: renameItems, excludingPaths: excludingPaths)
        try rename.rename(from: renameInput, rootFolderPath: root.path)
    }
}
