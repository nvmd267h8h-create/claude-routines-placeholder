import Foundation
import ReEditCore
import Testing

@testable import ReEditXML

/// Hand-computed absolute-time and capability expectations for the fixture set
/// (spec §10.2 themes F02, F03, F05, F08).
@Suite("Graph math across fixtures")
struct GraphFixtureTests {
    private func graph(_ fixture: String) throws -> TimelineGraph {
        let document = try FCPXMLDocument(path: FixtureLocator.fixturePath(fixture))
        return try TimelineGraphBuilder.build(from: document)
    }

    @Test func f02ConnectedClipTimes() throws {
        let graph = try graph("valid/f02-connected-broll-music.fcpxml")
        let spine = try #require(graph.nodes.first)
        #expect(spine.children.count == 2)
        #expect(graph.unsupported.isEmpty)

        let dialogue1 = spine.children[0]
        #expect(dialogue1.absoluteStart == .zero)
        #expect(dialogue1.sourceStart == FCPTime(seconds: 5))
        #expect(dialogue1.children.count == 2)
        #expect(dialogue1.role == "dialogue")

        // Connected clip offsets are expressed in the parent's local (media)
        // timeline: absStart = parentAbs + (offset − parent.start).
        let broll = dialogue1.children[0]
        #expect(broll.kind == .assetClip)
        #expect(broll.lane == 1)
        #expect(broll.absoluteStart == FCPTime(seconds: 2), "7s − 5s parent start")
        #expect(broll.duration == FCPTime(seconds: 4))
        #expect(broll.sourceStart == FCPTime(seconds: 100))
        // The b-roll asset declares no audio.
        #expect(!broll.capabilities.canEditAudio)
        #expect(broll.capabilities.canDeleteRange)

        let music = dialogue1.children[1]
        #expect(music.lane == -1)
        #expect(music.absoluteStart == .zero, "5s − 5s parent start")
        #expect(music.duration == FCPTime(seconds: 18), "music spans both spine clips")
        #expect(music.sourceStart == nil)
        #expect(music.role == "music.music-1")
        #expect(music.capabilities.canEditAudio)

        let dialogue2 = spine.children[1]
        #expect(dialogue2.absoluteStart == FCPTime(seconds: 12))
    }

    @Test func f03TitleTimesAndCapabilities() throws {
        let graph = try graph("valid/f03-titles.fcpxml")
        let spine = try #require(graph.nodes.first)
        #expect(spine.children.count == 2)
        #expect(graph.unsupported.isEmpty)

        let opening = spine.children[0]
        #expect(opening.kind == .title)
        #expect(opening.absoluteStart == .zero)
        #expect(opening.duration == FCPTime(seconds: 5))
        #expect(opening.sourceStart == FCPTime(seconds: 3600))
        #expect(opening.capabilities.canEditTitle)
        #expect(opening.capabilities.canDeleteRange)
        #expect(!opening.capabilities.canEditAudio)
        // text/text-style-def/param are content, not timeline children.
        #expect(opening.children.isEmpty)

        let clip = spine.children[1]
        #expect(clip.children.count == 1, "marker is not a timeline child")
        let lowerThird = clip.children[0]
        #expect(lowerThird.kind == .title)
        #expect(lowerThird.lane == 2)
        #expect(lowerThird.absoluteStart == FCPTime(seconds: 6), "5s + (41s − 40s)")
        #expect(lowerThird.duration == FCPTime(seconds: 2))
    }

    @Test func f05TransitionsAndGapsAreClassified() throws {
        let graph = try graph("valid/f05-gaps-transitions.fcpxml")
        let spine = try #require(graph.nodes.first)
        #expect(spine.children.count == 5)
        #expect(graph.unsupported.isEmpty)

        let kinds = spine.children.map(\.kind)
        #expect(kinds == [.assetClip, .transition, .assetClip, .gap, .assetClip])

        let transition = spine.children[1]
        #expect(transition.capabilities.isReadOnly, "transitions are protected constructs")
        #expect(transition.absoluteStart == FCPTime(seconds: 3))
        #expect(transition.duration == FCPTime(seconds: 2))

        let gap = spine.children[3]
        #expect(gap.capabilities.canDeleteRange)
        #expect(gap.capabilities.canTrimStart)
        #expect(!gap.capabilities.canEditAudio)
        #expect(gap.absoluteStart == FCPTime(seconds: 8))

        let clipB = spine.children[2]
        #expect(clipB.absoluteStart == FCPTime(seconds: 4))
    }

    @Test func f08UnknownConstructsAreReadOnlyAndReported() throws {
        let graph = try graph("valid/f08-unknown-nodes.fcpxml")
        let spine = try #require(graph.nodes.first)
        #expect(spine.children.count == 4)

        // Unsupported reporting, in document order (spec §6.7, §10.3).
        #expect(graph.unsupported.map(\.elementName)
            == ["future-thing", "ref-clip", "sync-clip", "conform-rate"])
        for construct in graph.unsupported {
            #expect(!construct.reason.isEmpty)
            #expect(construct.xmlPath.hasPrefix("/fcpxml/"))
        }

        // An unknown child demotes its parent to read-only.
        let receptionEntry = spine.children[0]
        #expect(receptionEntry.kind == .assetClip)
        #expect(receptionEntry.capabilities.isReadOnly)
        #expect(receptionEntry.children.count == 1)
        #expect(receptionEntry.children[0].kind == .unknown(elementName: "future-thing"))
        #expect(receptionEntry.children[0].capabilities.isReadOnly)

        // Recognised-but-unproven containers are read-only, not traversed.
        let refClip = spine.children[1]
        #expect(refClip.kind == .refClip)
        #expect(refClip.capabilities.isReadOnly)
        #expect(refClip.children.isEmpty)
        #expect(refClip.absoluteStart == FCPTime(seconds: 4))

        let syncClip = spine.children[2]
        #expect(syncClip.kind == .syncClip)
        #expect(syncClip.capabilities.isReadOnly)
        #expect(syncClip.children.isEmpty, "sync-clip internals are not traversed")

        // A timing-affecting child (conform-rate) demotes its parent.
        let conformed = spine.children[3]
        #expect(conformed.kind == .assetClip)
        #expect(conformed.capabilities.isReadOnly)
        #expect(conformed.absoluteStart == FCPTime(seconds: 12))
    }

    @Test(arguments: [
        "valid/f01-simple-25fps.fcpxml",
        "valid/f02-connected-broll-music.fcpxml",
        "valid/f03-titles.fcpxml",
        "valid/f04-audio-roles.fcpxml",
        "valid/f05-gaps-transitions.fcpxml",
        "valid/f08-unknown-nodes.fcpxml",
    ])
    func allValidFixturesValidateClean(fixture: String) throws {
        let document = try FCPXMLDocument(path: FixtureLocator.fixturePath(fixture))
        let report = Validator.validate(document)
        #expect(report.findings.isEmpty, "unexpected findings for \(fixture): \(report.renderedText)")
    }

    @Test func f04SubframeAudioDuration() throws {
        let graph = try graph("valid/f04-audio-roles.fcpxml")
        let spine = try #require(graph.nodes.first)
        let speech = spine.children[0]
        #expect(speech.capabilities.canEditAudio, "audioRole plus adjust-volume present")
        let music = try #require(speech.children.first)
        #expect(music.lane == -1)
        #expect(music.duration == (try FCPTime(fcpxmlString: "132301/44100s")))
        #expect(!music.duration.isAligned(toGrid: graph.frameDuration))
        #expect(music.absoluteStart == FCPTime(seconds: 2))
    }

    @Test func f06BundleLoadsAndBuilds() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f06-bundle.fcpxmld"))
        #expect(document.version == "1.13")
        #expect(document.input.kind == .bundle(innerDocumentName: "Info.fcpxml"))
        let graph = try TimelineGraphBuilder.build(from: document)
        #expect(graph.projectName == "Novak Bundle Smoke")
        #expect(graph.duration == FCPTime(seconds: 6))
    }
}
