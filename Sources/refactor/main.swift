//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Buck
import CommandLine
import Foundation
import Graph
import Parser
import Rename
import Shell
import Utilities

do {
    let arguments = CommandLine.arguments
    let graph = GraphImpl()
    let parser = try ParserImpl()
    let rename = RenameImpl()
    let shell = ShellImpl()
    let buck = BuckImpl(
        graph: graph,
        parser: parser,
        rename: rename,
        shell: shell
    )
    let tool = CommandLineTool(
        arguments: arguments,
        buck: buck,
        graph: graph,
        parser: parser,
        rename: rename,
        shell: shell
    )

    try tool.run()
} catch {
    Log(error)
}
