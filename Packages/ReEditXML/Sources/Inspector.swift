import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// What `reedit inspect` reports (spec §10.3): version, project identity,
/// frame duration, start, total duration and node counts.
public struct InspectionReport: Codable, Sendable, Equatable {
    public let fcpxmlVersion: String
    public let projectName: String
    /// Number of `<project>` elements found; Phase 0 inspects the first.
    public let projectCount: Int
    /// The sequence's format frameDuration attribute, verbatim.
    public let frameDurationSource: String
    /// The same value as exact time (reduced).
    public let frameDuration: FCPTime
    /// The sequence `tcStart` (0s when absent).
    public let projectStart: FCPTime
    /// The sequence `duration`.
    public let duration: FCPTime
    /// Count of every element in the document, by element name.
    public let nodeCounts: [String: Int]

    /// Frames per second for display only (floating point never feeds edit
    /// logic, spec §5.3): "25", "29.97". The loader rejects non-positive frame
    /// durations, but this stays total for defence in depth — never trap on
    /// display formatting.
    public var framesPerSecondDisplay: String {
        guard frameDuration.numerator > 0 else { return "invalid" }
        let fps = Double(frameDuration.denominator) / Double(frameDuration.numerator)
        let rounded = (fps * 100).rounded() / 100
        if rounded == rounded.rounded(), rounded <= Double(Int32.max) {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.2f", rounded)
    }

    /// Deterministic human rendering, used verbatim by the CLI and goldens.
    public var renderedText: String {
        var lines: [String] = []
        lines.append("FCPXML version: \(fcpxmlVersion)")
        lines.append("Project: \(projectName)")
        if projectCount > 1 {
            lines.append("Projects in document: \(projectCount) (inspecting the first)")
        }
        lines.append("Frame duration: \(frameDurationSource) (\(framesPerSecondDisplay) fps)")
        lines.append("Project start: \(projectStart.fcpxmlString)")
        lines.append("Duration: \(duration.fcpxmlString)")
        lines.append("Node counts:")
        for (name, count) in nodeCounts.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(name): \(count)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Extracts an `InspectionReport` from a loaded document.
public enum Inspector {
    public static func inspect(_ document: FCPXMLDocument) throws(FCPXMLLoadError) -> InspectionReport {
        let root = document.root

        let projects = DOM.descendants(of: root).filter { $0.name == "project" }
        guard let project = projects.first else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: "/fcpxml", element: "fcpxml", attribute: "project",
                guidance: "The document contains no <project>. Export a project, not a bare event.")
        }
        let projectName = DOM.attribute("name", of: project) ?? "(unnamed)"

        guard let sequence = DOM.firstDescendant(named: "sequence", of: project) else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: XMLPath.path(of: project), element: "project", attribute: "sequence",
                guidance: "The project has no <sequence>; the export may be incomplete.")
        }

        let frameInfo = try SequenceTiming.frameDuration(for: sequence, in: root)
        let projectStart = try SequenceTiming.time(
            attribute: "tcStart", of: sequence, default: .zero)
        let duration = try SequenceTiming.time(
            attribute: "duration", of: sequence, default: .zero)

        var counts: [String: Int] = [root.name ?? "?": 1]
        for element in DOM.descendants(of: root) {
            counts[element.name ?? "?", default: 0] += 1
        }

        return InspectionReport(
            fcpxmlVersion: document.version,
            projectName: projectName,
            projectCount: projects.count,
            frameDurationSource: frameInfo.source,
            frameDuration: frameInfo.value,
            projectStart: projectStart,
            duration: duration,
            nodeCounts: counts)
    }
}

/// Shared sequence-timing extraction for inspector, validator and graph builder.
enum SequenceTiming {
    /// Parses a time attribute, with a default when absent.
    static func time(
        attribute name: String, of element: XMLElement, default defaultValue: FCPTime
    ) throws(FCPXMLLoadError) -> FCPTime {
        guard let raw = DOM.attribute(name, of: element) else {
            return defaultValue
        }
        do {
            return try FCPTime(fcpxmlString: raw)
        } catch {
            throw FCPXMLLoadError.invalidTimeValue(
                xmlPath: XMLPath.path(of: element), attribute: name, value: raw,
                underlying: error.description,
                guidance: "Times must be FCPXML rational notation such as '3600s' or '1001/30000s'.")
        }
    }

    /// Resolves the sequence's format resource and returns its frameDuration.
    static func frameDuration(
        for sequence: XMLElement, in root: XMLElement
    ) throws(FCPXMLLoadError) -> (source: String, value: FCPTime) {
        guard let formatRef = DOM.attribute("format", of: sequence) else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: XMLPath.path(of: sequence), element: "sequence", attribute: "format",
                guidance: "Sequences must reference a <format> resource.")
        }
        guard let resources = DOM.firstDescendant(named: "resources", of: root),
            let format = DOM.childElements(of: resources).first(where: {
                $0.name == "format" && DOM.attribute("id", of: $0) == formatRef
            })
        else {
            throw FCPXMLLoadError.danglingResourceReference(
                xmlPath: XMLPath.path(of: sequence), ref: formatRef,
                guidance: "The sequence's format id has no matching <format> in <resources>.")
        }
        guard let raw = DOM.attribute("frameDuration", of: format) else {
            throw FCPXMLLoadError.missingRequiredAttribute(
                xmlPath: XMLPath.path(of: format), element: "format", attribute: "frameDuration",
                guidance: "Progressive timelines need an explicit frame duration (spec §3.2).")
        }
        let value: FCPTime
        do {
            value = try FCPTime(fcpxmlString: raw)
        } catch {
            throw FCPXMLLoadError.invalidTimeValue(
                xmlPath: XMLPath.path(of: format), attribute: "frameDuration", value: raw,
                underlying: error.description,
                guidance: "Frame durations must be positive rational times such as '100/2500s'.")
        }
        guard value.numerator > 0 else {
            throw FCPXMLLoadError.invalidTimeValue(
                xmlPath: XMLPath.path(of: format), attribute: "frameDuration", value: raw,
                underlying: FCPTimeError.invalidFrameGrid(grid: raw).description,
                guidance: "Frame durations must be positive rational times such as '100/2500s'.")
        }
        return (raw, value)
    }
}
