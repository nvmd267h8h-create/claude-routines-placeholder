import Testing

@testable import reedit_cli

@Suite("CLI argument parsing")
struct ArgumentParserTests {
    @Test func simpleCommands() throws {
        #expect(try CLIArguments.parse(["help"]) == .help)
        #expect(try CLIArguments.parse(["--help"]) == .help)
        #expect(try CLIArguments.parse(["--version"]) == .version)
        #expect(try CLIArguments.parse(["inspect", "a.fcpxml"]) == .inspect(input: "a.fcpxml"))
        #expect(try CLIArguments.parse(["validate", "b.fcpxmld"]) == .validate(input: "b.fcpxmld"))
    }

    @Test func optionsInEitherOrder() throws {
        #expect(
            try CLIArguments.parse(["roundtrip", "in.fcpxml", "--output", "out.fcpxml"])
                == .roundtrip(input: "in.fcpxml", output: "out.fcpxml"))
        #expect(
            try CLIArguments.parse(["roundtrip", "--output", "out.fcpxml", "in.fcpxml"])
                == .roundtrip(input: "in.fcpxml", output: "out.fcpxml"))
        #expect(
            try CLIArguments.parse(["graph", "in.fcpxml", "--json", "g.json"])
                == .graph(input: "in.fcpxml", json: "g.json"))
    }

    @Test func usageErrors() {
        #expect(throws: ArgumentParseError.missingCommand) {
            _ = try CLIArguments.parse([])
        }
        #expect(throws: ArgumentParseError.unknownCommand("apply")) {
            _ = try CLIArguments.parse(["apply", "x"])
        }
        #expect(throws: ArgumentParseError.missingInput(command: "inspect")) {
            _ = try CLIArguments.parse(["inspect"])
        }
        #expect(throws: ArgumentParseError.missingOptionValue(command: "roundtrip", option: "--output")) {
            _ = try CLIArguments.parse(["roundtrip", "in.fcpxml"])
        }
        #expect(throws: ArgumentParseError.missingOptionValue(command: "roundtrip", option: "--output")) {
            _ = try CLIArguments.parse(["roundtrip", "in.fcpxml", "--output"])
        }
        #expect(throws: ArgumentParseError.unexpectedArgument("extra")) {
            _ = try CLIArguments.parse(["inspect", "a.fcpxml", "extra"])
        }
        #expect(throws: ArgumentParseError.unexpectedArgument("--verbose")) {
            _ = try CLIArguments.parse(["graph", "in.fcpxml", "--verbose", "--json", "g.json"])
        }
    }
}
