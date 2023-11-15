//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Buck
import CommandCougar
import Files
import Foundation
import Graph
import Parser
import Rename
import Shell
import Utilities

public enum CommandLineToolError: Error {
    case missingCommand
    case missingData
    case invalidCommand
}

public final class CommandLineTool {
    fileprivate enum Options {
        fileprivate static let verbose = Option(
            flag: .both(short: "v", long: "verbose"),
            overview: "Increase verbosity of informational output."
        )
        fileprivate static let print = Option(
            flag: .both(short: "p", long: "printOnly"),
            overview: "Does not change or create anything, just prints out would be done."
        )
    }

    fileprivate enum Parameters {
        fileprivate static let buildifierPath = "buildifierPath"
        fileprivate static let buckPath = "buckPath"
        fileprivate static let shellPath = "shellPath"
        fileprivate static let cachePath = "cachePath"
        fileprivate static let jsonFile = "jsonFile"
        fileprivate static let jsonText = "jsonText"

        fileprivate static let defaultParams = [
            Parameter.optional(Parameters.buildifierPath),
            Parameter.optional(Parameters.buckPath),
            Parameter.optional(Parameters.jsonText),
            Parameter.optional(Parameters.jsonFile),
            Parameter.optional(Parameters.shellPath),
            Parameter.optional(Parameters.cachePath),
        ]
    }

    fileprivate enum UserCommand: String {
        case extract
    }

    private let arguments: [String]
    private let buck: Buck
    private let graph: Graph
    private let parser: Parser
    private let rename: Rename
    private let shell: Shell

    public init(
        arguments: [String],
        buck: Buck,
        graph: Graph,
        parser: Parser,
        rename: Rename,
        shell: Shell
    ) {
        self.arguments = arguments
        self.buck = buck
        self.parser = parser
        self.rename = rename
        self.shell = shell
        self.graph = graph
    }

    public func run() throws {
        let swiftCommand = Command(
            name: "refactor",
            overview: "A tool to help create and manage modules",
            callback: refactor,
            options: [
                Options.verbose,
                Options.print,
            ],
            subCommands: [
                Command(
                    name: "cleanup",
                    overview: "Cleanup a BUCK module's visibility, name, module_name, exported headers and visibility.",
                    callback: cleanup,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
                Command(
                    name: "create",
                    overview: "Extract files out of the monolith into a new module",
                    callback: create,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
                Command(
                    name: "move",
                    overview: "Move a BUCK file from one location to another and update all the module_name's",
                    callback: move,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
                Command(
                    name: "parse",
                    overview: "Parses the type information for the list of files provided",
                    callback: parse,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
                Command(
                    name: "parseBuck",
                    overview: "Parses the type information for the list of BUCK targets provided",
                    callback: parseBuck,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
                Command(
                    name: "stats",
                    overview: "Output stats for a list of BUCK modules.",
                    callback: stats,
                    options: [],
                    parameters: Parameters.defaultParams
                ),
            ]
        )
        let evaluation = try swiftCommand.evaluate(arguments: arguments)
        try evaluation.performCallbacks()
    }

    // MARK: - Private

    private func refactor(evaluation: CommandEvaluation) throws {
        if evaluation.hasOption(Options.verbose) {
            Logger.logLevel = .verbose
        }
        let printOnly = evaluation.hasOption(Options.print)
        buck.printOnly = printOnly
        parser.printOnly = printOnly
        rename.printOnly = printOnly
    }

    private func cleanup(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        try buck.cleanupModule(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func create(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        try buck.createModule(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func move(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        try buck.moveModule(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func parse(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        _ = try parser.listTypes(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func parseBuck(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        try buck.parseModules(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func stats(with evaluation: CommandEvaluation) throws {
        applyShellParameters(with: evaluation)
        let rootFolderPath = evaluation.parameter(forPrefix: Parameters.shellPath) ?? "."
        let json = try inputJson(from: evaluation)
        try buck.moduleStats(fromJson: json, rootFolderPath: rootFolderPath)
    }

    private func applyShellParameters(with evaluation: CommandEvaluation) {
        if let buildifierPath = evaluation.parameter(forPrefix: Parameters.buildifierPath) {
            shell.buildifierPath = buildifierPath
        }
        if let buckPath = evaluation.parameter(forPrefix: Parameters.buckPath) {
            shell.buckPath = buckPath
        }
        if let shellPath = evaluation.parameter(forPrefix: Parameters.shellPath) {
            shell.shellPath = shellPath
        }
        if let cachePath = evaluation.parameter(forPrefix: Parameters.cachePath) {
            parser.cachePath = cachePath
        }
    }

    private func inputJson(from evaluation: CommandEvaluation) throws -> String {
        var json = evaluation.parameter(forPrefix: Parameters.jsonText)

        if json == nil, let jsonFile = evaluation.parameter(forPrefix: Parameters.jsonFile) {
            let sourceFile = try File(path: jsonFile)
            json = try sourceFile.readAsString()
        }

        guard let commandJson = json else {
            throw CommandLineToolError.missingData
        }
        return commandJson
    }
}

extension CommandEvaluation {
    public func hasOption(_ option: Option) -> Bool {
        options.contains { $0.flag == option.flag }
    }

    public func parameter(forPrefix prefix: String) -> String? {
        parameters.compactMap { parameter -> String? in
            guard parameter.hasPrefix(prefix) else { return nil }
            return String(parameter.dropFirst(prefix.count + 1))
        }
        .first
    }
}
