/// Deterministic edit-capability flags for a timeline node (spec §6.7).
///
/// A future edit command may only cross nodes that explicitly advertise the
/// required capability. Unknown or unproven constructs stay `.readOnly`, which
/// converts missing implementation into a visible limitation instead of silent
/// damage.
public struct NodeCapabilities: Codable, Hashable, Sendable {
    public let canDeleteRange: Bool
    public let canTrimStart: Bool
    public let canTrimEnd: Bool
    public let canEditAudio: Bool
    public let canEditTitle: Bool

    public init(
        canDeleteRange: Bool,
        canTrimStart: Bool,
        canTrimEnd: Bool,
        canEditAudio: Bool,
        canEditTitle: Bool
    ) {
        self.canDeleteRange = canDeleteRange
        self.canTrimStart = canTrimStart
        self.canTrimEnd = canTrimEnd
        self.canEditAudio = canEditAudio
        self.canEditTitle = canEditTitle
    }

    /// The default posture for every node kind that has not proved otherwise.
    public static let readOnly = NodeCapabilities(
        canDeleteRange: false,
        canTrimStart: false,
        canTrimEnd: false,
        canEditAudio: false,
        canEditTitle: false
    )

    public var isReadOnly: Bool {
        !canDeleteRange && !canTrimStart && !canTrimEnd && !canEditAudio && !canEditTitle
    }
}
