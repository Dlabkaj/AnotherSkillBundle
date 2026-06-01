#!/usr/bin/env python3
"""
Fetch YouTube transcript and save in autoresearch raw format.

Usage:
  python fetch_youtube_transcript.py <url_or_id> <output_file>

Output file format:
  SOURCE_URL: https://www.youtube.com/watch?v=<id>
  ---
  <transcript text>
"""
import sys
import re

def extract_video_id(url_or_id):
    patterns = [
        r'[?&]v=([a-zA-Z0-9_-]{11})',
        r'youtu\.be/([a-zA-Z0-9_-]{11})',
        r'embed/([a-zA-Z0-9_-]{11})',
        r'^([a-zA-Z0-9_-]{11})$',
    ]
    for p in patterns:
        m = re.search(p, url_or_id)
        if m:
            return m.group(1)
    return None

def main():
    if len(sys.argv) != 3:
        print("Usage: fetch_youtube_transcript.py <url_or_id> <output_file>")
        sys.exit(1)

    url_or_id  = sys.argv[1]
    output_file = sys.argv[2]

    try:
        from youtube_transcript_api import YouTubeTranscriptApi
    except ImportError:
        print("ERROR: youtube-transcript-api not installed. Run: pip install youtube-transcript-api")
        sys.exit(2)

    video_id = extract_video_id(url_or_id)
    if not video_id:
        print(f"ERROR: cannot extract video ID from: {url_or_id}")
        sys.exit(1)

    canonical_url = f"https://www.youtube.com/watch?v={video_id}"

    try:
        api = YouTubeTranscriptApi()
        transcript_list = api.list(video_id)
        transcript = transcript_list.find_transcript(['en', 'cs', 'en-US', 'en-GB'])
        entries = transcript.fetch()
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    def get_text(e):
        return (e.text if hasattr(e, 'text') else e["text"]).replace("\n", " ")

    text = " ".join(get_text(e) for e in entries)
    content = f"SOURCE_URL: {canonical_url}\n---\n{text}\n"

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"OK: {video_id} -> {output_file} ({len(text)} chars)")

if __name__ == "__main__":
    main()
