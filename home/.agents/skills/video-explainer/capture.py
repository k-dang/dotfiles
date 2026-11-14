# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright==1.64.1"]
# ///
"""Render an animated HTML page to MP4, muxed with a narration track.

Usage: uv run capture.py PAGE.html NARRATION_AUDIO OUT.mp4 [--fps 30]

The video runs as long as the narration. Time 0 is page load: every frame,
each animation on the page is paused and seeked to the frame's time, so all
motion must be CSS animations or Web Animations started at load.
Uses the installed Chrome, falling back to Edge.
"""

import argparse
import subprocess
from pathlib import Path

from playwright.sync_api import Error, sync_playwright

W, H = 1920, 1080

SEEK = """t => {
  for (const a of document.getAnimations()) { a.pause(); a.currentTime = t; }
}"""


def duration(path: Path) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)]
    )
    return float(out)


def launch(p):
    for channel in ("chrome", "msedge"):
        try:
            return p.chromium.launch(channel=channel)
        except Error:
            continue
    raise SystemExit("No Chrome or Edge install found")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page", type=Path)
    ap.add_argument("audio", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--fps", type=int, default=30)
    args = ap.parse_args()

    frames = round(duration(args.audio) * args.fps)
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-f", "image2pipe", "-c:v", "png", "-framerate", str(args.fps), "-i", "-",
         "-i", str(args.audio),
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", "-shortest", str(args.out)],
        stdin=subprocess.PIPE,
    )
    with sync_playwright() as p:
        browser = launch(p)
        page = browser.new_page(viewport={"width": W, "height": H})
        page.goto(args.page.resolve().as_uri())
        page.evaluate("document.fonts.ready")
        for f in range(frames):
            page.evaluate(SEEK, f * 1000 / args.fps)
            ffmpeg.stdin.write(page.screenshot(type="png"))
        browser.close()
    ffmpeg.stdin.close()
    raise SystemExit(ffmpeg.wait())


if __name__ == "__main__":
    main()
