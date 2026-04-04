import Foundation
import SLATESharedTypes

public struct FCPXMLWriter: ExportWriter {
    public let format: ExportFormat = .fcpxml

    public init() {}

    public func dryRun(context: ExportContext) throws {
        _ = try Self.serializedData(for: context)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let data = try Self.serializedData(for: context)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let preparation = try ExportPreparation(context: context)
        let filename = ExportPreparation.sanitizedFilename(
            prefix: "\(preparation.projectName)_\(preparation.assembly.name)-v\(preparation.assembly.version)",
            format: format
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        return ExportArtifact(format: format, filePath: url.path, byteCount: data.count)
    }

    static func serializedData(for context: ExportContext) throws -> Data {
        let preparation = try ExportPreparation(context: context)

        let formatElement = XMLElement(
            name: "format",
            attributes: [
                "frameDuration": preparation.primaryRate.frameDurationString,
                "height": "\(preparation.dimensions.height)",
                "id": "fmt1",
                "name": preparation.primaryRate.ntsc ? "\(preparation.primaryRate.fps)p" : "\(preparation.primaryRate.timebase)p",
                "width": "\(preparation.dimensions.width)"
            ]
        )

        let effectElements = [
            XMLElement(name: "effect", attributes: ["id": "role-boom", "name": "dialogue.boom", "uid": "dialogue.boom"]),
            XMLElement(name: "effect", attributes: ["id": "role-lav", "name": "dialogue.lav", "uid": "dialogue.lav"]),
            XMLElement(name: "effect", attributes: ["id": "role-mix", "name": "dialogue.mix", "uid": "dialogue.mix"])
        ]

        let assetElements = preparation.clips.map { preparedClip in
            XMLElement(
                name: "asset",
                attributes: [
                    "duration": preparedClip.rate.secondsString(fromFrames: preparedClip.sourceDurationFrames),
                    "format": "fmt1",
                    "hasAudio": preparedClip.clip.audioTracks.isEmpty ? "0" : "1",
                    "hasVideo": "1",
                    "id": "asset-\(preparedClip.index + 1)",
                    "name": preparedClip.filename,
                    "src": preparedClip.assetURLString,
                    "start": preparedClip.rate.secondsString(fromFrames: preparedClip.sourceStartFrame)
                ]
            )
        }

        let spineChildren: [XMLNode] = preparation.clips.map { preparedClip in
            var children: [XMLNode] = []

            if let reviewKeyword = preparedClip.reviewKeyword {
                children.append(
                    XMLElement(
                        name: "keyword",
                        attributes: [
                            "duration": preparedClip.rate.secondsString(fromFrames: preparedClip.durationFrames),
                            "start": "0s",
                            "value": reviewKeyword
                        ]
                    )
                )
            }

            for roleName in preparedClip.audioRoleNames {
                children.append(
                    XMLElement(
                        name: "metadata",
                        children: [
                            XMLElement.textNode(name: "md", value: roleName)
                        ]
                    )
                )
            }

            children.append(
                XMLElement.textNode(
                    name: "note",
                    value: "Audio Roles: \(preparedClip.audioRoleNames.joined(separator: ", "))"
                )
            )

            return XMLElement(
                name: "asset-clip",
                attributes: [
                    "duration": preparedClip.rate.secondsString(fromFrames: preparedClip.durationFrames),
                    "name": preparedClip.filename,
                    "offset": preparation.primaryRate.secondsString(fromFrames: preparedClip.timelineStartFrame),
                    "ref": "asset-\(preparedClip.index + 1)",
                    "start": preparedClip.rate.secondsString(fromFrames: preparedClip.sourceInFrame)
                ],
                children: children
            )
        }

        let sequenceMarkers: [XMLNode] = preparation.timelineMarkers.map { marker in
            XMLElement(
                name: "marker",
                attributes: [
                    "duration": preparation.primaryRate.secondsString(fromFrames: marker.durationFrames),
                    "start": preparation.primaryRate.secondsString(fromFrames: marker.timelineStartFrame),
                    "value": marker.name
                ],
                children: [
                    XMLElement.textNode(name: "note", value: marker.body)
                ]
            )
        }

        let root = XMLElement(
            name: "fcpxml",
            attributes: ["version": "1.11"],
            children: [
                XMLElement(name: "resources", children: [formatElement] + effectElements + assetElements),
                XMLElement(
                    name: "library",
                    children: [
                        XMLElement(
                            name: "event",
                            attributes: ["name": preparation.projectName],
                            children: [
                                XMLElement(
                                    name: "project",
                                    attributes: ["name": preparation.assembly.name],
                                    children: [
                                        XMLElement(
                                            name: "sequence",
                                            attributes: [
                                                "duration": preparation.primaryRate.secondsString(fromFrames: preparation.totalFrames),
                                                "format": "fmt1",
                                                "tcFormat": preparation.primaryRate.fcpxmlTimecodeFormat,
                                                "tcStart": "0s"
                                            ],
                                            children: sequenceMarkers + [
                                                XMLElement(name: "spine", children: spineChildren)
                                            ]
                                        )
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        return try XMLSerialization.data(from: root)
    }
}
