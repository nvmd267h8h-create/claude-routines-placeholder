/// Typed loading and safety errors (spec §6.2): every case carries the failing
/// location and human recovery guidance.
public enum FCPXMLLoadError: Error, Sendable, CustomStringConvertible {
    case fileNotFound(path: String, guidance: String)
    case notAnFCPXMLInput(path: String, guidance: String)
    case bundleMissingDocument(bundlePath: String, guidance: String)
    case unreadable(path: String, underlying: String, guidance: String)
    case malformedXML(path: String, underlying: String, guidance: String)
    case missingRootElement(path: String, found: String?, guidance: String)
    case missingVersionAttribute(xmlPath: String, guidance: String)
    case missingRequiredAttribute(
        xmlPath: String, element: String, attribute: String, guidance: String)
    case invalidTimeValue(
        xmlPath: String, attribute: String, value: String, underlying: String,
        guidance: String)
    case danglingResourceReference(xmlPath: String, ref: String, guidance: String)
    case outputWouldOverwriteSource(input: String, output: String, guidance: String)

    public var description: String {
        switch self {
        case .fileNotFound(let path, let guidance):
            return "No file at '\(path)'. \(guidance)"
        case .notAnFCPXMLInput(let path, let guidance):
            return "'\(path)' is not an FCPXML input. \(guidance)"
        case .bundleMissingDocument(let bundlePath, let guidance):
            return "Bundle '\(bundlePath)' contains no FCPXML document. \(guidance)"
        case .unreadable(let path, let underlying, let guidance):
            return "Cannot read '\(path)': \(underlying). \(guidance)"
        case .malformedXML(let path, let underlying, let guidance):
            return "'\(path)' is not well-formed XML: \(underlying). \(guidance)"
        case .missingRootElement(let path, let found, let guidance):
            let seen = found.map { "found '<\($0)>'" } ?? "found no root element"
            return "'\(path)' is not an FCPXML document: expected root '<fcpxml>', \(seen). \(guidance)"
        case .missingVersionAttribute(let xmlPath, let guidance):
            return "Element at \(xmlPath) has no 'version' attribute. \(guidance)"
        case .missingRequiredAttribute(let xmlPath, let element, let attribute, let guidance):
            return "<\(element)> at \(xmlPath) is missing required attribute '\(attribute)'. \(guidance)"
        case .invalidTimeValue(let xmlPath, let attribute, let value, let underlying, let guidance):
            return "Attribute '\(attribute)=\"\(value)\"' at \(xmlPath) is not a valid time: \(underlying). \(guidance)"
        case .danglingResourceReference(let xmlPath, let ref, let guidance):
            return "Node at \(xmlPath) references resource '\(ref)' which does not exist. \(guidance)"
        case .outputWouldOverwriteSource(let input, let output, let guidance):
            return "Refusing to write output '\(output)' over source input '\(input)'. \(guidance)"
        }
    }
}
