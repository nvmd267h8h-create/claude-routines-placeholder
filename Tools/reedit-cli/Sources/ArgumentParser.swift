/// The Phase 0 command surface (spec §12.3 subset).
enum ParsedCommand: Equatable {
    case help
    case version
    case inspect(input: String)
    case validate(input: String)
    case roundtrip(input: String, output: String)
    case graph(input: String, json: String)
}

enum ArgumentParseError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingInput(command: String)
    case missingOptionValue(command: String, option: String)
    case unexpectedArgument(String)

    var description: String {
        switch self {
        case .missingCommand:
            return "No command given."
        case .unknownCommand(let name):
            return "Unknown command '\(name)'."
        case .missingInput(let command):
            return "'\(command)' requires an input path (.fcpxml or .fcpxmld)."
        case .missingOptionValue(let command, let option):
            return "'\(command)' requires \(option) <path>."
        case .unexpectedArgument(let argument):
            return "Unexpected argument '\(argument)'."
        }
    }
}

/// Hand-rolled argument parsing (ADR-0002): four subcommands with at most one
/// option each do not justify a dependency.
enum CLIArguments {
    static let usage = """
        reedit — ReEdit AI Phase 0 harness

        USAGE:
          reedit inspect   <input.fcpxml|input.fcpxmld>
          reedit validate  <input>
          reedit roundtrip <input> --output <path>
          reedit graph     <input> --json <path>
          reedit help | reedit --version

        EXIT CODES:
          0 success · 1 validation findings or fidelity failure ·
          2 usage error · 3 load/parse error · 4 internal error
        """

    static func parse(_ arguments: [String]) throws(ArgumentParseError) -> ParsedCommand {
        guard let command = arguments.first else {
            throw ArgumentParseError.missingCommand
        }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "help", "--help", "-h":
            return .help
        case "--version", "version":
            return .version
        case "inspect", "validate":
            guard let input = rest.first else {
                throw ArgumentParseError.missingInput(command: command)
            }
            guard rest.count == 1 else {
                throw ArgumentParseError.unexpectedArgument(rest[1])
            }
            return command == "inspect" ? .inspect(input: input) : .validate(input: input)
        case "roundtrip":
            let (input, value) = try positionalAndOption(
                rest, command: command, option: "--output")
            return .roundtrip(input: input, output: value)
        case "graph":
            let (input, value) = try positionalAndOption(
                rest, command: command, option: "--json")
            return .graph(input: input, json: value)
        default:
            throw ArgumentParseError.unknownCommand(command)
        }
    }

    /// Parses exactly one positional argument plus one required valued option,
    /// in either order.
    private static func positionalAndOption(
        _ arguments: [String], command: String, option: String
    ) throws(ArgumentParseError) -> (input: String, value: String) {
        var input: String?
        var value: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == option {
                guard index + 1 < arguments.count else {
                    throw ArgumentParseError.missingOptionValue(command: command, option: option)
                }
                guard value == nil else {
                    throw ArgumentParseError.unexpectedArgument(argument)
                }
                value = arguments[index + 1]
                index += 2
            } else if argument.hasPrefix("-") {
                throw ArgumentParseError.unexpectedArgument(argument)
            } else if input == nil {
                input = argument
                index += 1
            } else {
                throw ArgumentParseError.unexpectedArgument(argument)
            }
        }
        guard let input else {
            throw ArgumentParseError.missingInput(command: command)
        }
        guard let value else {
            throw ArgumentParseError.missingOptionValue(command: command, option: option)
        }
        return (input, value)
    }
}
