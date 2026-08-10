import Foundation
import ReEditCore
import Testing

@testable import ReEditXML

@Suite("Timeline graph builder")
struct GraphBuilderTests {
    private func f01Graph() throws -> TimelineGraph {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        return try TimelineGraphBuilder.build(from: document)
    }

    @Test func headerFields() throws {
        let graph = try f01Graph()
        #expect(graph.projectName == "Smith Wedding Highlights")
        #expect(graph.fcpxmlVersion == "1.11")
        #expect(graph.projectStart == FCPTime(seconds: 3600))
        #expect(graph.duration == FCPTime(seconds: 18))
        // 100/2500s reduces to exactly one 25fps frame.
        #expect(graph.frameDuration == (try FCPTime(fcpxmlString: "1/25s")))
        #expect(graph.unsupported.isEmpty)
    }

    @Test func spineStructureAndAbsoluteTimes() throws {
        let graph = try f01Graph()
        #expect(graph.nodes.count == 1)
        let spine = try #require(graph.nodes.first)
        #expect(spine.kind == .spine)
        #expect(spine.absoluteStart == .zero)
        #expect(spine.capabilities.isReadOnly)
        #expect(spine.children.count == 3)

        let expected: [(absStart: String, duration: String, sourceStart: String, ref: String)] = [
            ("0s", "6s", "10s", "r2"),
            ("6s", "8s", "31s", "r3"),  // start="775/25s" reduces to 31s
            ("14s", "4s", "0s", "r4"),
        ]
        for (index, clip) in spine.children.enumerated() {
            #expect(clip.kind == .assetClip)
            #expect(clip.lane == 0)
            #expect(clip.parentID == spine.stableID)
            #expect(clip.absoluteStart == (try FCPTime(fcpxmlString: expected[index].absStart)))
            #expect(clip.duration == (try FCPTime(fcpxmlString: expected[index].duration)))
            #expect(clip.sourceStart == (try FCPTime(fcpxmlString: expected[index].sourceStart)))
            #expect(clip.resourceRef == expected[index].ref)
        }
    }

    @Test func capabilitiesAreConservative() throws {
        let graph = try f01Graph()
        let spine = try #require(graph.nodes.first)
        for clip in spine.children {
            #expect(clip.capabilities.canDeleteRange)
            #expect(clip.capabilities.canTrimStart)
            #expect(clip.capabilities.canTrimEnd)
            // The referenced assets declare hasAudio="1".
            #expect(clip.capabilities.canEditAudio)
            #expect(!clip.capabilities.canEditTitle)
        }
    }

    @Test func stableIDsAreUniqueAndDeterministic() throws {
        let first = try f01Graph()
        let second = try f01Graph()
        #expect(first == second, "graph construction must be deterministic")

        var seen = Set<String>()
        func walk(_ node: TimelineNode) {
            #expect(node.stableID.count == 32)
            #expect(seen.insert(node.stableID).inserted, "duplicate stableID at \(node.xmlPath)")
            for child in node.children {
                walk(child)
            }
        }
        for node in first.nodes {
            walk(node)
        }
    }

    @Test func xmlPathsFollowConvention() throws {
        let graph = try f01Graph()
        let spine = try #require(graph.nodes.first)
        #expect(
            spine.xmlPath
                == "/fcpxml/library[0]/event[0]/project[0]/sequence[0]/spine[0]")
        #expect(
            spine.children[2].xmlPath
                == "/fcpxml/library[0]/event[0]/project[0]/sequence[0]/spine[0]/asset-clip[2]")
    }

    @Test func matchesCommittedGolden() throws {
        // Structural comparison: the golden decodes to an identical graph value.
        // Byte formatting of JSON is platform-dependent and intentionally not
        // asserted here.
        let graph = try f01Graph()
        let goldenData = try Data(
            contentsOf: FixtureLocator.goldenURL("f01-simple-25fps.graph.golden.json"))
        let golden = try JSONDecoder().decode(TimelineGraph.self, from: goldenData)
        #expect(graph == golden, "graph differs from committed golden")

        // And our own encoding roundtrips losslessly.
        let reencoded = try JSONDecoder().decode(
            TimelineGraph.self, from: StableJSON.encode(graph))
        #expect(reencoded == graph)
    }
}

@Suite("Sidecar manifest")
struct SidecarManifestTests {
    @Test func mapsEveryNodeAndNeverTouchesXML() throws {
        let document = try FCPXMLDocument(
            path: FixtureLocator.fixturePath("valid/f01-simple-25fps.fcpxml"))
        let graph = try TimelineGraphBuilder.build(from: document)
        let manifest = SidecarManifest(
            graph: graph, sourceFingerprint: document.sourceFingerprint)

        // 1 spine + 3 clips.
        #expect(manifest.entries.count == 4)
        #expect(manifest.sourceFingerprint == document.sourceFingerprint)
        #expect(Set(manifest.entries.map(\.stableID)).count == 4)

        #expect(SidecarManifest.sidecarPath(forOutput: "/x/out.fcpxml")
            == "/x/out.fcpxml.reedit-manifest.json")
    }
}
