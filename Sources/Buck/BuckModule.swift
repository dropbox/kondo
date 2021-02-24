//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Foundation
import Utilities

public struct BuckModule: Codable, ReflectedStringConvertible, Equatable, Hashable {
  public let target: String
  public let name: String
  public let module_name: String?
  public let frameworks: [String]?
  public let srcs: [String]?
  public let headers: [String]?
  public let exported_headers: [String]?
  public let deps: [String]?

  public var buckFilePath: String? {
    guard let path = target.replacingOccurrences(of: "//", with: "").components(separatedBy: ":").first else {
      return nil
    }
    return path + "/BUCK"
  }

  public var hasFiles: Bool {
    if let srcs = srcs, !srcs.isEmpty { return true }
    if let headers = headers, !headers.isEmpty { return true }
    if let exported_headers = exported_headers, !exported_headers.isEmpty { return true }
    return false
  }

  public var isSwiftOnly: Bool {
    if let headers = headers, !headers.isEmpty { return false }
    if let exported_headers = exported_headers, !exported_headers.isEmpty { return false }
    guard let srcs = srcs else { return false }
    return srcs.allSatisfy { $0.hasSuffix(".swift") }
  }

  public init(
    target: String,
    name: String,
    module_name: String?,
    frameworks: [String]?,
    srcs: [String]?,
    headers: [String]?,
    exported_headers: [String]?,
    deps: [String]?
  ) {
    self.target = target
    self.name = name
    self.module_name = module_name
    self.frameworks = frameworks
    self.srcs = srcs
    self.headers = headers
    self.exported_headers = exported_headers
    self.deps = deps
  }

  public init(target: String, json: [String: Any]) {
    self.target = target
    self.name = json["name"] as? String ?? ""
    self.module_name = json["module_name"] as? String
    self.frameworks = json["frameworks"] as? [String]

    func parseFiles(forKey key: String) -> [String]? {
      if let files = json[key] as? [String] {
        return files
      } else if let fileMap = json[key] as? [String: String] {
        return Array(fileMap.values)
      } else if let fileMap = json[key] as? [[Any]] {
        return Array(fileMap.compactMap { $0.first as? String })
      } else if let output = json[key] {
        LogInfo("Failed to parse \(output)")
        return nil
      } else {
        return nil
      }
    }
    self.srcs = parseFiles(forKey: "srcs")
    self.headers = parseFiles(forKey: "headers")
    self.exported_headers = parseFiles(forKey: "exported_headers")

    // In BUCK files you can use shorthand target names if the target
    // is in the same file.
    let buckPath = target.replacingOccurrences(of: ":\(name)", with: "")
    deps = parseFiles(forKey: "deps")?.map { dep -> String in
      guard dep.hasPrefix(":") else { return dep }
      return "\(buckPath)\(dep)"
    }
  }
}
