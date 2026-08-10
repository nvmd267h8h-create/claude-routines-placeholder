import Foundation
import ReEditCore
import ReEditXML

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try CLIArguments.parse(arguments)
    exit(Commands.run(command, fileSystem: LiveFileSystem()))
} catch {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    FileHandle.standardError.write(Data((CLIArguments.usage + "\n").utf8))
    exit(ExitCode.usage)
}
