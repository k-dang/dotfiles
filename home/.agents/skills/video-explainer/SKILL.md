---
name: video-explainer
description: Narrated motion-graphics video recap of the session's changes. Use when the user asks for a video explainer, a video recap, or to explain the changes as a video.
---

# video-explainer

Make a ~30 second motion graphics video that explains the changes from this session, with TTS narration, built as an animated HTML page and exported with ffmpeg. The viewer has not read the session's final summary; the video replaces it.

Focus: $ARGUMENTS

1. **Script.** Write the narration first: about 75 spoken words for 30 seconds, split into 4–6 scenes. Open with the one-sentence outcome, give each scene one idea (what changed and why it matters), and close on anything the user must act on. Plain speech: no file paths, symbols, or code read aloud. Done when every scene has a line of narration and a matching visual.
2. **Voice.** Synthesize each scene's narration to its own audio file with the platform's built-in TTS (macOS `say`, Windows `System.Speech` run from a `.ps1` file) unless a better engine is installed. Measure each clip with `ffprobe`, then concatenate them with ffmpeg, padding each with a little silence, into one narration track. The padded clip lengths are the scene timings.
3. **Motion.** Build the video as one 1920×1080 HTML page. Scenes are moving graphics: elements that enter, build, and transition, so the screen tracks what the voice is saying. Show diffs as visuals (boxes, arrows, before/after, short code snippets), with large text readable at a glance. All motion is CSS keyframe animations (or Web Animations) running from page load, with each scene's delays offset by its start time, since time 0 is the start of the narration.
4. **Export.** Run `uv run capture.py page.html narration.wav out.mp4` with `capture.py` from this skill's directory. It seeks every animation frame by frame in headless Chrome and muxes the narration into an H.264 MP4. Work in the scratchpad directory.
5. **Check.** Extract a frame from the middle of every scene and look at them; fix clipped, overflowing, or overlapping elements and re-export. Done when every frame reads cleanly.

Reply with the video embedded by its absolute path and a one-line summary of what it covers.
