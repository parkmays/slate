import Foundation

enum XMEMLVariant {
    case premiere
    case resolve
}

enum XMEMLDocumentBuilder {
    static func serializedData(context: ExportContext, variant: XMEMLVariant) throws -> Data {
        let preparation = try ExportPreparation(context: context)
        let root = XMLElement(
            name: "xmeml",
            attributes: ["version": "5"],
            children: [
                XMLElement(
                    name: "project",
                    children: [
                        XMLElement.textNode(name: "name", value: preparation.projectName),
                        XMLElement(
                            name: "children",
                            children: binElements(preparation: preparation, variant: variant) + [
                                sequenceElement(preparation: preparation, variant: variant)
                            ]
                        )
                    ]
                )
            ]
        )

        return try XMLSerialization.data(from: root)
    }

    private static func binElements(preparation: ExportPreparation, variant: XMEMLVariant) -> [XMLNode] {
        let grouped = Dictionary(grouping: preparation.clips, by: \.binName)
        return grouped.keys.sorted().map { binName in
            let clips = grouped[binName, default: []].sorted { $0.timelineStartFrame < $1.timelineStartFrame }
            return XMLElement(
                name: "bin",
                children: [
                    XMLElement.textNode(name: "name", value: binName),
                    XMLElement(
                        name: "children",
                        children: clips.map { masterClipElement(for: $0, variant: variant) }
                    )
                ]
            )
        }
    }

    private static func masterClipElement(for preparedClip: PreparedClip, variant: XMEMLVariant) -> XMLElement {
        var children: [XMLNode] = [
            XMLElement.textNode(name: "name", value: preparedClip.filename),
            XMLElement.textNode(name: "pathurl", value: preparedClip.assetURLString),
            XMLElement(
                name: "rate",
                children: [
                    XMLElement.textNode(name: "timebase", value: "\(preparedClip.rate.timebase)"),
                    XMLElement.textNode(name: "ntsc", value: preparedClip.rate.ntsc ? "TRUE" : "FALSE")
                ]
            ),
            XMLElement.textNode(name: "duration", value: "\(preparedClip.sourceDurationFrames)")
        ]

        if let reviewKeyword = preparedClip.reviewKeyword {
            children.append(
                XMLElement(
                    name: "labels",
                    children: [
                        XMLElement.textNode(name: "label2", value: reviewKeyword)
                    ]
                )
            )
        }

        switch variant {
        case .premiere:
            children.append(
                XMLElement(
                    name: "slateMetadata",
                    children: [
                        XMLElement.textNode(name: "essentialSoundRole", value: "Dialogue")
                    ]
                )
            )
        case .resolve:
            if let color = preparedClip.resolveColor {
                children.append(XMLElement.textNode(name: "colorlabel", value: color))
            }
        }

        return XMLElement(name: "clip", attributes: ["id": "masterclip-\(preparedClip.index + 1)"], children: children)
    }

    private static func sequenceElement(preparation: ExportPreparation, variant: XMEMLVariant) -> XMLElement {
        let audioTrackNames = ["A1 Boom", "A2 Boom-R", "A3 Lav 1", "A4 Lav 2"]
        let videoTrack = XMLElement(name: "track", children: preparation.clips.map { videoClipItem(for: $0) })
        let audioTracks: [XMLNode] = audioTrackNames.enumerated().map { offset, name in
            XMLElement(
                name: "track",
                children: [XMLElement.textNode(name: "name", value: name)] + audioClipItems(
                    for: preparation.clips,
                    audioTrackIndex: offset,
                    variant: variant
                )
            )
        }

        var sequenceChildren: [XMLNode] = [
            XMLElement.textNode(name: "name", value: preparation.assembly.name),
            XMLElement(
                name: "rate",
                children: [
                    XMLElement.textNode(name: "timebase", value: "\(preparation.primaryRate.timebase)"),
                    XMLElement.textNode(name: "ntsc", value: preparation.primaryRate.ntsc ? "TRUE" : "FALSE")
                ]
            ),
            XMLElement.textNode(name: "duration", value: "\(preparation.totalFrames)"),
            XMLElement(
                name: "media",
                children: [
                    XMLElement(
                        name: "video",
                        children: [
                            XMLElement(
                                name: "format",
                                children: [
                                    XMLElement(
                                        name: "samplecharacteristics",
                                        children: [
                                            XMLElement.textNode(name: "width", value: "\(preparation.dimensions.width)"),
                                            XMLElement.textNode(name: "height", value: "\(preparation.dimensions.height)"),
                                            XMLElement.textNode(name: "anamorphic", value: "FALSE"),
                                            XMLElement.textNode(name: "pixelaspectratio", value: "square"),
                                            XMLElement(
                                                name: "rate",
                                                children: [
                                                    XMLElement.textNode(name: "timebase", value: "\(preparation.primaryRate.timebase)"),
                                                    XMLElement.textNode(name: "ntsc", value: preparation.primaryRate.ntsc ? "TRUE" : "FALSE")
                                                ]
                                            )
                                        ]
                                    )
                                ]
                            ),
                            videoTrack
                        ]
                    ),
                    XMLElement(name: "audio", children: audioTracks)
                ]
            )
        ]

        if !preparation.timelineMarkers.isEmpty {
            sequenceChildren.append(
                XMLElement(
                    name: "markers",
                    children: preparation.timelineMarkers.map { marker in
                        XMLElement(
                            name: "marker",
                            children: [
                                XMLElement.textNode(name: "name", value: marker.name),
                                XMLElement.textNode(name: "comment", value: marker.body),
                                XMLElement.textNode(name: "in", value: "\(marker.timelineStartFrame)"),
                                XMLElement.textNode(name: "out", value: "\(marker.timelineStartFrame + marker.durationFrames)")
                            ]
                        )
                    }
                )
            )
        }

        switch variant {
        case .premiere:
            sequenceChildren.append(
                XMLElement(
                    name: "slateMetadata",
                    children: [
                        XMLElement.textNode(name: "essentialSoundDefault", value: "Dialogue"),
                        XMLElement.textNode(name: "reviewSurface", value: "Premiere Pro XML")
                    ]
                )
            )
        case .resolve:
            sequenceChildren.append(
                XMLElement(
                    name: "slateResolve",
                    children: [
                        XMLElement(
                            name: "smartbins",
                            children: [
                                XMLElement(name: "smartbin", attributes: ["name": "Circled Takes", "query": "reviewStatus = circled"]),
                                XMLElement(name: "smartbin", attributes: ["name": "Needs Review", "query": "reviewStatus IN (unreviewed, flagged)"])
                            ]
                        ),
                        XMLElement(
                            name: "fairlightTrackLayout",
                            children: [
                                XMLElement.textNode(name: "track", value: "A1 boom"),
                                XMLElement.textNode(name: "track", value: "A2 boom-R"),
                                XMLElement.textNode(name: "track", value: "A3 lav1"),
                                XMLElement.textNode(name: "track", value: "A4 lav2")
                            ]
                        )
                    ]
                )
            )
        }

        return XMLElement(name: "sequence", attributes: ["id": "sequence-1"], children: sequenceChildren)
    }

    private static func videoClipItem(for preparedClip: PreparedClip) -> XMLElement {
        var children: [XMLNode] = [
            XMLElement.textNode(name: "name", value: preparedClip.filename),
            XMLElement.textNode(name: "start", value: "\(preparedClip.timelineStartFrame)"),
            XMLElement.textNode(name: "end", value: "\(preparedClip.timelineStartFrame + preparedClip.durationFrames)"),
            XMLElement.textNode(name: "in", value: "\(preparedClip.sourceInFrame)"),
            XMLElement.textNode(name: "out", value: "\(preparedClip.sourceOutFrame)"),
            fileElement(for: preparedClip)
        ]

        if let reviewKeyword = preparedClip.reviewKeyword {
            children.append(
                XMLElement(
                    name: "labels",
                    children: [
                        XMLElement.textNode(name: "label2", value: reviewKeyword)
                    ]
                )
            )
        }

        return XMLElement(name: "clipitem", attributes: ["id": "video-\(preparedClip.index + 1)"], children: children)
    }

    private static func audioClipItems(
        for clips: [PreparedClip],
        audioTrackIndex: Int,
        variant: XMEMLVariant
    ) -> [XMLNode] {
        clips.compactMap { preparedClip in
            guard audioTrackIndex < max(preparedClip.clip.audioTracks.count, 1) else {
                return nil
            }

            var children: [XMLNode] = [
                XMLElement.textNode(name: "name", value: preparedClip.filename),
                XMLElement.textNode(name: "start", value: "\(preparedClip.timelineStartFrame)"),
                XMLElement.textNode(name: "end", value: "\(preparedClip.timelineStartFrame + preparedClip.durationFrames)"),
                XMLElement.textNode(name: "in", value: "\(preparedClip.sourceInFrame)"),
                XMLElement.textNode(name: "out", value: "\(preparedClip.sourceOutFrame)"),
                fileElement(for: preparedClip),
                XMLElement(
                    name: "sourcetrack",
                    children: [
                        XMLElement.textNode(name: "mediatype", value: "audio"),
                        XMLElement.textNode(name: "trackindex", value: "\(audioTrackIndex + 1)")
                    ]
                )
            ]

            switch variant {
            case .premiere:
                children.append(
                    XMLElement(
                        name: "slateMetadata",
                        children: [
                            XMLElement.textNode(name: "essentialSoundRole", value: "Dialogue"),
                            XMLElement.textNode(
                                name: "audioRole",
                                value: preparedClip.audioRoleNames[min(audioTrackIndex, preparedClip.audioRoleNames.count - 1)]
                            )
                        ]
                    )
                )
            case .resolve:
                if let color = preparedClip.resolveColor {
                    children.append(XMLElement.textNode(name: "colorlabel", value: color))
                }
            }

            return XMLElement(name: "clipitem", attributes: ["id": "audio-\(audioTrackIndex + 1)-\(preparedClip.index + 1)"], children: children)
        }
    }

    private static func fileElement(for preparedClip: PreparedClip) -> XMLElement {
        XMLElement(
            name: "file",
            attributes: ["id": "file-\(preparedClip.index + 1)"],
            children: [
                XMLElement.textNode(name: "name", value: preparedClip.filename),
                XMLElement.textNode(name: "pathurl", value: preparedClip.assetURLString),
                XMLElement.textNode(name: "duration", value: "\(preparedClip.sourceDurationFrames)")
            ]
        )
    }
}
