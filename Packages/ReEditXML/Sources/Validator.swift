import Foundation
import ReEditCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

public enum FindingSeverity: String, Codable, Sendable {
    case error
    case warning
}

/// One validation finding, ordered deterministically by xmlPath in reports.
public struct ValidationFinding: Codable, Sendable, Equatable {
    public let severity: FindingSeverity
    public let xmlPath: String
    public let message: String
}

public struct ValidationReport: Codable, Sendable {
    public let findings: [ValidationFinding]

    public var hasErrors: Bool {
        findings.contains { $0.severity == .error }
    }

    /// Deterministic human rendering used by the CLI.
    public var renderedText: String {
        if findings.isEmpty {
            return "No findings. The document passes Phase 0 validation.\n"
        }
        var lines: [String] = []
        for finding in findings {
            lines.append("\(finding.severity.rawValue.uppercased()): \(finding.xmlPath): \(finding.message)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Phase 0 structural validation (spec §6.6 subset): references resolve, times
/// parse, durations are non-negative, boundaries align to the frame grid, and
/// prolog anomalies are surfaced.
public enum Validator {
    /// FCPXML versions with Phase 0 test coverage. Anything else opens
    /// read-only per spec §9.4 and is flagged as a warning here.
    static let knownVersions: Set<String> = [
        "1.5", "1.6", "1.7", "1.8", "1.9", "1.10", "1.11", "1.12", "1.13",
    ]

    static let timeAttributeNames: Set<String> = [
        "offset", "start", "duration", "tcStart", "frameDuration",
    ]

    public static func validate(_ document: FCPXMLDocument) -> ValidationReport {
        var findings: [ValidationFinding] = []
        let root = document.root
        let resources = ResourceIndex(root: root)

        if !knownVersions.contains(document.version) {
            findings.append(
                ValidationFinding(
                    severity: .warning, xmlPath: "/fcpxml",
                    message:
                        "FCPXML version '\(document.version)' has no Phase 0 test coverage; treat as read-only until fixtures pass."))
        }
        if document.prolog.xmlDeclaration == nil {
            findings.append(
                ValidationFinding(
                    severity: .warning, xmlPath: "/fcpxml",
                    message: "Source has no XML declaration; Final Cut Pro exports always include one."))
        }
        if document.prolog.doctype == nil {
            findings.append(
                ValidationFinding(
                    severity: .warning, xmlPath: "/fcpxml",
                    message: "Source has no <!DOCTYPE fcpxml> declaration."))
        }

        // Every time-valued attribute must parse exactly; durations must not be
        // negative.
        for element in DOM.descendants(of: root) {
            for attribute in element.attributes ?? [] {
                guard let name = attribute.name, timeAttributeNames.contains(name),
                    let value = attribute.stringValue
                else { continue }
                do {
                    let time = try FCPTime(fcpxmlString: value)
                    if name == "duration" || name == "frameDuration", time.isNegative {
                        findings.append(
                            ValidationFinding(
                                severity: .error, xmlPath: XMLPath.path(of: element),
                                message: "\(name)=\"\(value)\" is negative."))
                    }
                } catch {
                    findings.append(
                        ValidationFinding(
                            severity: .error, xmlPath: XMLPath.path(of: element),
                            message:
                                "\(name)=\"\(value)\" is not a valid FCPXML time: \(error.description)"))
                }
            }
        }

        // Every ref/format attribute must resolve into <resources>; this covers
        // timeline references and resource-to-resource references alike.
        // Exception: <text-style ref> resolves against text-style-def ids local
        // to its title, not against resources.
        let known = resources.identifiers
        for element in DOM.descendants(of: root) {
            if element.name == "text-style" { continue }
            for attributeName in ["ref", "format"] {
                guard let ref = DOM.attribute(attributeName, of: element) else { continue }
                if !known.contains(ref) {
                    findings.append(
                        ValidationFinding(
                            severity: .error, xmlPath: XMLPath.path(of: element),
                            message:
                                "\(attributeName)=\"\(ref)\" does not resolve to any resource id."))
                }
            }
        }

        // Frame-grid alignment for spine-level clip boundaries (warnings; audio
        // legitimately uses subframe times, spec §6.6).
        if let graph = try? TimelineGraphBuilder.build(from: document) {
            let grid = graph.frameDuration
            if grid.numerator > 0 {
                for spine in graph.nodes {
                    for node in spine.children where node.lane == 0 {
                        if !node.absoluteStart.isAligned(toGrid: grid) {
                            findings.append(
                                ValidationFinding(
                                    severity: .warning, xmlPath: node.xmlPath,
                                    message:
                                        "Clip start \(node.absoluteStart.fcpxmlString) is not aligned to the \(grid.fcpxmlString) frame grid."))
                        }
                        if !node.duration.isAligned(toGrid: grid) {
                            findings.append(
                                ValidationFinding(
                                    severity: .warning, xmlPath: node.xmlPath,
                                    message:
                                        "Clip duration \(node.duration.fcpxmlString) is not aligned to the \(grid.fcpxmlString) frame grid."))
                        }
                    }
                }
            }

            // Declared sequence duration vs computed spine extent.
            if let extent = computedExtent(of: graph), !graph.duration.isZero,
                extent != graph.duration
            {
                findings.append(
                    ValidationFinding(
                        severity: .warning, xmlPath: "/fcpxml",
                        message:
                            "Sequence duration \(graph.duration.fcpxmlString) does not match computed spine extent \(extent.fcpxmlString)."))
            }
        }

        return ValidationReport(findings: findings.sorted { $0.xmlPath < $1.xmlPath })
    }

    /// Latest end time of any primary-storyline node.
    private static func computedExtent(of graph: TimelineGraph) -> FCPTime? {
        var latest: FCPTime?
        for spine in graph.nodes {
            for node in spine.children where node.lane == 0 && node.kind != .transition {
                guard let end = try? node.absoluteStart.adding(node.duration) else {
                    return nil
                }
                if let current = latest {
                    if current < end {
                        latest = end
                    }
                } else {
                    latest = end
                }
            }
        }
        return latest
    }
}
