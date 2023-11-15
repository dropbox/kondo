//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import ShellOut
import Utilities

public final class ShellImpl: Shell {
    public var buildifierPath = "/usr/local/bin/buildifier"
    public var buckPath = "/usr/local/bin/buck"
    public var shellPath = "."

    public init() {}

    public func runBuildifier(on file: File) throws {
        let output = try shellOut(to: buildifierPath, arguments: [file.path])
        LogVerbose(output)
    }

    public func build(targets: [String], noCache: Bool) throws -> Bool {
        let pwd = try shellOut(to: "/bin/pwd", arguments: [], at: shellPath)
        LogVerbose(pwd)
        var arguments = ["build"]
        if noCache {
            arguments.append("--no-cache")
        }
        arguments += targets
        LogInfo("buck \(arguments.combine(with: " "))")
        let result = try shellOut(
            to: buckPath,
            arguments: arguments,
            at: shellPath
        )
        LogVerbose("Build result for \(targets) is \(result)")
        return result.isEmpty
    }

    public func headers(inUmbrellaHeader umbrellaHeader: String) throws -> [String] {
        let command = "find buck-out/ -iname '\(umbrellaHeader)' -print0 | xargs -0 cat"
        let output = try shellOut(to: command, arguments: [], at: shellPath)
        LogVerbose(output)
        let uniqueHeaders = Set(output.components(separatedBy: .newlines).filter { !$0.isEmpty }).sorted()
        return uniqueHeaders
    }

    public func buckFile(forTarget target: String) throws -> String {
        let pwd = try shellOut(to: "/bin/pwd", arguments: [], at: shellPath)
        LogVerbose(pwd)
        let path = try shellOut(
            to: buckPath,
            arguments: [
                "query",
                "buildfile('\(target)')",
            ],
            at: shellPath
        )
        LogVerbose("Buck file for \(target) is \(path)")
        return path
    }

    public func queryBuckDependencies(forTarget target: String, depth: Int?) throws -> String {
        let pwd = try shellOut(to: "/bin/pwd", arguments: [], at: shellPath)
        LogVerbose(pwd)
        let depsArg: String
        if let depth = depth {
            depsArg = "\"deps('\(target)', \(depth)\""
        } else {
            depsArg = "\"deps('\(target)')\""
        }

        let json = try shellOut(
            to: buckPath,
            arguments: [
                "query",
                depsArg,
                "--output-format",
                "json",
                "--output-attributes",
                "'frameworks'",
                "'module_name'",
                "'name'",
                "'headers'",
                "'exported_headers'",
                "'srcs'",
                "'deps'",
            ],
            at: shellPath
        )
        LogVerbose("Queried \(target):\n\(json)")
        return json
    }
}
