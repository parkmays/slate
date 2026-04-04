#!/usr/bin/env python3

import json
import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PYTHON_DIR = SCRIPT_DIR / "python"
if str(PYTHON_DIR) not in sys.path:
    sys.path.insert(0, str(PYTHON_DIR))

try:
    import aaf2
    from aaf2 import ama
except Exception as exc:  # pragma: no cover - surfaced to Swift
    sys.stderr.write(f"Unable to load bundled pyaaf2 resources: {exc}\n")
    sys.exit(1)


def fps_rational_string(fps: float) -> str:
    if abs(fps - 23.976) < 0.01:
        return "24000/1001"
    if abs(fps - 29.97) < 0.01:
        return "30000/1001"
    return f"{max(int(round(fps)), 1)}/1"


def duration_seconds(duration_frames: int, fps: float) -> float:
    return float(duration_frames) / max(fps, 0.001)


def audio_sample_format(bit_depth: int) -> str:
    if bit_depth <= 16:
        return "s16"
    return "s32"


def make_video_metadata(clip: dict, manifest: dict) -> dict:
    fps = manifest["fps"]
    duration_frames = clip["durationFrames"] + clip["sourceInFrame"]
    return {
        "format": {
            "format_name": "mov",
            "format_long_name": "QuickTime / MOV",
            "filename": clip["videoPath"],
            "duration": str(duration_seconds(duration_frames, fps)),
        },
        "streams": [
            {
                "codec_type": "video",
                "codec_name": "h264",
                "profile": "High",
                "pix_fmt": "yuv420p",
                "width": manifest["dimensions"]["width"],
                "height": manifest["dimensions"]["height"],
                "avg_frame_rate": fps_rational_string(fps),
                "nb_frames": str(duration_frames),
                "duration": str(duration_seconds(duration_frames, fps)),
                "duration_ts": str(duration_frames),
                "time_base": f"1/{max(int(round(fps)), 1)}",
                "start_time": "0",
            }
        ],
    }


def make_audio_metadata(clip: dict, manifest: dict) -> dict:
    audio_tracks = clip.get("audioTracks") or []
    sample_rate = int(round(audio_tracks[0]["sampleRate"])) if audio_tracks else 48000
    bit_depth = audio_tracks[0]["bitDepth"] if audio_tracks else 24
    channels = max(len(audio_tracks), 1)
    duration_samples = int(round(duration_seconds(clip["durationFrames"], manifest["fps"]) * sample_rate))
    bytes_per_sample = max((bit_depth + 7) // 8, 2)
    return {
        "format": {
            "format_name": "mov",
            "format_long_name": "QuickTime / MOV",
            "filename": clip["audioPath"],
            "duration": str(duration_seconds(clip["durationFrames"], manifest["fps"])),
        },
        "streams": [
            {
                "codec_type": "audio",
                "codec_name": "pcm_s24le",
                "sample_rate": str(sample_rate),
                "duration": str(duration_seconds(clip["durationFrames"], manifest["fps"])),
                "duration_ts": str(duration_samples),
                "channels": channels,
                "channel_layout": "mono" if channels == 1 else "stereo",
                "sample_fmt": audio_sample_format(bit_depth),
                "bit_rate": str(sample_rate * channels * bytes_per_sample),
                "time_base": f"1/{sample_rate}",
                "start_time": "0",
            }
        ],
    }


def select_audio_slot_indices(audio_tracks: list[dict]) -> list[int | None]:
    remaining = list(audio_tracks)
    selected: list[int | None] = []

    def take_matching(*roles: str) -> int | None:
        for index, track in enumerate(remaining):
            if track["role"] in roles:
                return remaining.pop(index)["trackIndex"]
        return None

    selected.append(take_matching("boom", "mix", "iso", "unknown"))
    selected.append(take_matching("boom", "mix", "iso", "unknown"))
    selected.append(take_matching("lav", "mix", "iso", "unknown"))
    selected.append(take_matching("lav", "mix", "iso", "unknown"))

    return selected


def write_aaf(manifest_path: pathlib.Path, output_path: pathlib.Path) -> None:
    manifest = json.loads(manifest_path.read_text())
    edit_rate = fps_rational_string(manifest["fps"])

    with aaf2.open(str(output_path), "w") as file_handle:
        composition = file_handle.create.CompositionMob()
        composition.name = f"{manifest['assemblyName']} v{manifest['version']}"
        composition.usage = "Usage_TopLevel"
        file_handle.content.mobs.append(composition)

        video_slot = composition.create_picture_slot(edit_rate=edit_rate)
        video_slot.name = "V1"

        audio_slots = []
        for slot_name in ["A1 Boom", "A2 Boom-R", "A3 Lav 1", "A4 Lav 2"]:
            slot = composition.create_sound_slot(edit_rate=edit_rate)
            slot.name = slot_name
            audio_slots.append(slot)

        for clip in manifest["clips"]:
            video_master_mob, _, _ = ama.create_media_link(
                file_handle,
                clip["videoPath"],
                make_video_metadata(clip, manifest),
            )
            video_master_mob.comments["SLATE Scene"] = clip["sceneLabel"]
            if clip.get("reviewKeyword"):
                video_master_mob.comments["SLATE Review"] = clip["reviewKeyword"]

            picture_slot_id = video_master_mob.slots[0].slot_id
            picture_clip = video_master_mob.create_source_clip(
                slot_id=picture_slot_id,
                start=clip["sourceInFrame"],
                length=clip["durationFrames"],
                media_kind="picture",
            )
            video_slot.segment.components.append(picture_clip)

            audio_master_mob = None
            if clip.get("audioPath"):
                audio_master_mob, _, _ = ama.create_media_link(
                    file_handle,
                    clip["audioPath"],
                    make_audio_metadata(clip, manifest),
                )
                audio_master_mob.comments["SLATE Source Audio"] = clip["sourcePath"]

            selected_indices = select_audio_slot_indices(clip.get("audioTracks") or [])
            for target_index, source_index in enumerate(selected_indices):
                if audio_master_mob is not None and source_index is not None and source_index < len(audio_master_mob.slots):
                    source_slot_id = audio_master_mob.slots[source_index].slot_id
                    audio_clip = audio_master_mob.create_source_clip(
                        slot_id=source_slot_id,
                        start=0,
                        length=clip["durationFrames"],
                        media_kind="sound",
                    )
                    audio_slots[target_index].segment.components.append(audio_clip)
                else:
                    filler = file_handle.create.Filler(media_kind="sound", length=clip["durationFrames"])
                    audio_slots[target_index].segment.components.append(filler)


def collect_locator_urls(file_handle) -> list[str]:
    urls: list[str] = []
    for source_mob in file_handle.content.sourcemobs():
        descriptor = getattr(source_mob, "descriptor", None)
        if descriptor is None:
            continue

        descriptors = []
        try:
            file_descriptors = descriptor["FileDescriptors"].value
            if file_descriptors:
                descriptors.extend(file_descriptors)
        except Exception:
            descriptors.append(descriptor)

        for item in descriptors:
            try:
                locators = item["Locator"].value or []
            except Exception:
                locators = []
            for locator in locators:
                try:
                    url = locator["URLString"].value
                except Exception:
                    url = None
                if url:
                    urls.append(url)
    return urls


def inspect_aaf(aaf_path: pathlib.Path) -> None:
    with aaf2.open(str(aaf_path), "r") as file_handle:
        top_level = next(file_handle.content.toplevel())
        payload = {
            "topLevelName": top_level.name,
            "slotNames": [slot.name for slot in top_level.slots],
            "masterMobNames": [mob.name for mob in file_handle.content.mastermobs()],
            "locatorURLs": collect_locator_urls(file_handle),
        }
    sys.stdout.write(json.dumps(payload))


def main() -> None:
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: aaf_bridge.py write <manifest> <output> | inspect <aaf>\n")
        sys.exit(1)

    command = sys.argv[1]
    if command == "write":
        if len(sys.argv) != 4:
            sys.stderr.write("write requires a manifest path and output path\n")
            sys.exit(1)
        write_aaf(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
        return

    if command == "inspect":
        if len(sys.argv) != 3:
            sys.stderr.write("inspect requires an AAF path\n")
            sys.exit(1)
        inspect_aaf(pathlib.Path(sys.argv[2]))
        return

    sys.stderr.write(f"Unknown command: {command}\n")
    sys.exit(1)


if __name__ == "__main__":
    main()
