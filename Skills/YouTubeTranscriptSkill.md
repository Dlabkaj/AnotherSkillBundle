---
name: YouTubeTranscriptSkill
description: Fetch YouTube video transcripts and save in autoresearch raw format for ingestion. Used standalone or automatically by AutoresearchSkill/Run-Autoresearch.ps1 for [youtube] candidates.
triggers: ["youtube transcript", "fetch transcript", "download transcript", "youtube source"]
---

# YouTube Transcript Skill

Fetches auto-generated or manual YouTube transcript and saves it as a source file compatible with SourceScrapeSkill ingestion format.

> `{{RAW_ROOT}}` resolves from `skillSettings.json`. See repo `README.md`.

## Requirements

```
pip install youtube-transcript-api
```

Works for any YouTube video that has auto-generated or manual captions (majority of English content).
Does NOT work for: videos with no captions, age-gated videos, private videos.

## Standalone usage

```
python Skills/SharedScripts/fetch_youtube_transcript.py <url_or_id> <output_file>
```

Examples:
```
python Skills/SharedScripts/fetch_youtube_transcript.py https://www.youtube.com/watch?v=ABC123 {{RAW_ROOT}}/my-topic/raw/youtube-ABC123.txt
python Skills/SharedScripts/fetch_youtube_transcript.py ABC123 {{RAW_ROOT}}/my-topic/raw/youtube-ABC123.txt
```

Output format (autoresearch-compatible):
```
SOURCE_URL: https://www.youtube.com/watch?v=ABC123
---
<full transcript as continuous text>
```

## Autoresearch integration

Add YouTube candidates to `candidates.md` using type `[youtube]`:

```
- [youtube] Title of the video -- https://www.youtube.com/watch?v=ABC123
  snippet: One-line description of what the video covers
  status: pending
```

`AutoresearchSkill/Run-Autoresearch.ps1` auto-detects `[youtube]` candidates and calls `Skills/SharedScripts/fetch_youtube_transcript.py`
instead of `Invoke-WebRequest`. No manual step needed.

## Language fallback

Script tries transcripts in order: `en`, `cs`, `en-US`, `en-GB`.
First available language wins.
If none available, exits with error and marks candidate `skipped-fetch`.

## Limitations

- Transcript is spoken content only — no visuals, no code shown on screen
- Auto-generated transcripts have no punctuation (run-on sentences)
- Timestamps included in raw entries but stripped in the output text
- For code-heavy tutorials: transcript alone may miss implementation details. Note in candidates.md.
