//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import Utilities

public final class RenameImpl: Rename {
  private var processedFiles = Set<String>()

  private let queue = DispatchQueue(
    label: "com.dropbox.RenameImpl",
    qos: .background,
    attributes: .concurrent,
    autoreleaseFrequency: .workItem
  )

  public var printOnly = false

  public init() {}

  public func rename(from input: RenameInput, rootFolderPath: String) throws {
    LogInfo("Starting renames")
    LogVerbose(input.description)
    let rootFolder = try Folder(path: rootFolderPath)
    let dispatchGroup = DispatchGroup()
    try process(rootFolder, input: input, rootFolder: rootFolder, dispatchGroup: dispatchGroup)
    LogInfo("Waiting for files to finish processing")
    dispatchGroup.wait()
    LogInfo("Renames finished processing")
  }

  // MARK: - Private

  private func process(
    _ folder: Folder,
    input: RenameInput,
    rootFolder: Folder,
    dispatchGroup: DispatchGroup
  ) throws {
    //    LogVerbose("Rename processing folder \(folder.path)")
    let relativePath = folder.path(relativeTo: rootFolder)
    if !relativePath.isEmpty {
      let excludeFolder = input.excludingPaths.contains { relativePath.hasPrefix($0) }
      guard !excludeFolder else {
        LogVerbose("Skipping rename in folder \(folder.path)")
        return
      }
    }

    try folder.subfolders.forEach { subfolder in
      let type = try FileManager.default.attributesOfItem(atPath: subfolder.path)[.type] as! FileAttributeType
      guard type != .typeSymbolicLink else {
        LogWarn("Skipping symbolic link at \(subfolder.path)")
        return
      }
      try process(subfolder, input: input, rootFolder: rootFolder, dispatchGroup: dispatchGroup)
    }
    guard folder.files.count() > 0 else { return }

    try process(folder.files, input: input, rootFolder: rootFolder, dispatchGroup: dispatchGroup)
  }

  private func process(
    _ files: Files.Folder.ChildSequence<File>,
    input: RenameInput,
    rootFolder: Folder,
    dispatchGroup: DispatchGroup
  ) throws {
    files.forEach { file in
      guard !self.processedFiles.contains(file.path) else { return }
      self.processedFiles.insert(file.path)
      dispatchGroup.enter()
      queue.async { () -> Void in
        defer {
          dispatchGroup.leave()
        }
        do {
          var items = input.items
          items = items.filter { $0.fileTypes.contains { file.name.hasSuffix($0) } }
          guard !items.isEmpty else { return }

          let originalContent = try file.loadContent()
          var content = originalContent
          items.forEach { item in
            let relativePath = file.path(relativeTo: rootFolder)
            let excludeItem = input.excludingPaths.contains { relativePath.hasPrefix($0) }
            guard !excludeItem else {
              return
            }
            content = content.replacingOccurrences(of: item.originalText, with: item.newText)
          }
          guard originalContent != content else {
            LogVerbose("Nothing changed in \(file.path)")
            return
          }
          LogInfo("Updating \(file.path)")
          if self.printOnly {
            print("Update \(file.path) to:\n\(content)")
          } else {
            try file.store(content)
          }
        } catch {
          Log(error)
        }
      }
    }
  }
}
