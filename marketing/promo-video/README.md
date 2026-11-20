# Scanly promo video

A 48-second vertical (1080Ã—1920, 30 fps) marketing video with a Bangla
voice-over, built in code with [Remotion](https://www.remotion.dev).

Story: there are many scanner apps, but they stamp their logo on every page
and charge to remove it â†’ Scanly reveal â†’ auto edge detection, crop/rotate/
filters, Bangla + English OCR, searchable PDF â†’ no logo, ads or
subscription, works offline â†’ free download for Android.

## Files

| Path | What |
| --- | --- |
| `voiceover/script.json` | Bangla narration, one line per scene, voice and speed |
| `scripts/make_voiceover.py` | Makes `public/vo/*.mp3` and `timeline.json` (scene timing follows the voice) |
| `scripts/make_music.py` | Synthesises the music and sound effects into `public/music.wav` (no samples, no licences) |
| `src/scenes/` | The animated scenes |
| `out/Scanly-promo.mp4` | Rendered video (not committed) |

## Rebuild

Requires Node and the project venv (`tools/py-venv` with `edge-tts`, `mutagen`,
`numpy`, `scipy`).

```powershell
npm install --cache ..\..\tools\npm-cache
..\..\tools\py-venv\Scripts\python.exe scripts\make_voiceover.py
..\..\tools\py-venv\Scripts\python.exe scripts\make_music.py
npm run render
```

`npm run studio` opens a live preview for editing.

The voice is Microsoft Edge's free neural text-to-speech (`bn-BD-NabanitaNeural`),
which needs internet only while generating. Change the text in
`voiceover/script.json` and re-run both scripts; the scenes follow the new timing.
Fonts (Hind Siliguri, Outfit) come from Google Fonts under the OFL. Remotion is
free for individuals and companies of up to three people.
