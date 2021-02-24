//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckCreateInput: Codable, ReflectedStringConvertible, Equatable {
  public struct Module: Codable, Equatable, ReflectedStringConvertible {
    public let destination: String
    public let files: [String]
    public let targetName: String?
    public let moduleName: String?
    public let visibility: [String]?
    public let testTarget: Bool

    public init(
      destination: String,
      files: [String],
      targetName: String? = nil,
      moduleName: String? = nil,
      visibility: [String]? = nil,
      testTarget: Bool = false
    ) {
      self.destination = destination
      self.files = files
      self.targetName = targetName
      self.moduleName = moduleName
      self.visibility = visibility
      self.testTarget = testTarget
    }
  }

  public let modules: [Module]
  public let projectBuildTargets: [String]
  public let ignoreFolders: [String]?

  public init(
    modules: [Module],
    projectBuildTargets: [String],
    ignoreFolders: [String]? = nil
  ) {
    self.modules = modules
    self.projectBuildTargets = projectBuildTargets
    self.ignoreFolders = ignoreFolders
  }
}
