"""Generates the Bangla voice-over, one MP3 per scene, plus timeline.json.

Uses Microsoft Edge's free neural text-to-speech (edge-tts, no account).
Run with the project venv:
    ..\\..\\tools\\py-venv\\Scripts\\python.exe scripts\\make_voiceover.py
"""

import asyncio
import json
import math
from pathlib import Path

import edge_tts
from mutagen.mp3 import MP3

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "voiceover" / "script.json"
OUT = ROOT / "public" / "vo"
FPS = 30
VOICE_DELAY = 0.12  # seconds of silence at the start of each scene


async def main() -> None:
    spec = json.loads(SCRIPT.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    timeline = []
    for scene in spec["scenes"]:
        path = OUT / f"{scene['id']}.mp3"
        tts = edge_tts.Communicate(
            scene["text"],
            scene.get("voice", spec["voice"]),
            rate=scene.get("rate", spec["rate"]),
            pitch=scene.get("pitch", spec["pitch"]),
        )
        await tts.save(str(path))
        seconds = MP3(path).info.length
        timeline.append({"id": scene["id"], "file": f"vo/{path.name}", "seconds": round(seconds, 3)})
        print(f"{scene['id']:8s} {seconds:5.2f}s")
    # Scene layout: each scene starts, waits VOICE_DELAY, speaks, then holds
    # for its "pad" so the visuals can land.
    frame = 0
    for item, scene in zip(timeline, spec["scenes"]):
        length = math.ceil((VOICE_DELAY + item["seconds"] + scene.get("pad", 0.8)) * FPS)
        item.update(startFrame=frame, durationFrames=length, voiceDelayFrames=round(VOICE_DELAY * FPS))
        frame += length
    total = sum(s["seconds"] for s in timeline)
    print(f"total voice {total:.2f}s, video {frame / FPS:.2f}s ({frame} frames)")
    (OUT / "timeline.json").write_text(json.dumps(timeline, indent=2), encoding="utf-8")


asyncio.run(main())
