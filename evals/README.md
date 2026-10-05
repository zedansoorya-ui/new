# Evals

Every quality change is checked against recordings of your own voice. This folder holds:
- the manifest format and the suggested prompts (committed);
- the recordings and reports, which stay on your Mac. `evals/audio/`, `evals/reports/` and
  `evals/manifest.json` are gitignored, because this repository is public.

## 1. Record clips

Record 30 or more short clips (3–20 s), roughly following [prompts.md](prompts.md). Speak
naturally: hesitations, self-corrections and fast bits are the point.

The simplest way is QuickTime Player:
1. File ▸ New Audio Recording.
2. Record, then save to `evals/audio/001.m4a`, `002.m4a`, and so on.

Any format macOS can decode works (M4A, WAV, MP3).

## 2. Write the manifest

```bash
cp evals/manifest.example.json evals/manifest.json
```

Then add one entry per clip:

| Field | What to write |
|---|---|
| `id` | Clip name, for example `"001"` |
| `audio` | Path relative to the manifest, for example `"audio/001.m4a"` |
| `category` | casual, fast, self-correction, list, names, hinglish or code |
| `reference` | **Exactly what you said**, word for word, including "um" and false starts. Raw speech recognition is scored against this. |
| `expected` | The text you would want pasted, after cleanup. Scored from Milestone 4. |
| `app` | Optional bundle ID of the app it was meant for (Slack, Mail, Terminal…), for app-aware styles |

Number formatting is not normalised yet in v0 scoring. Write numbers in `reference` the way
you expect the recogniser to write them ("4", not "four").

## 3. Run

```bash
make eval                                   # Parakeet Ultra
swift run -c release murmur-eval run --model v3
swift run -c release murmur-eval transcribe evals/audio/001.m4a
```

Each run writes `evals/reports/<time>-<engine>.md` and a JSON twin. Each report gives:
- corpus WER, with substitutions, deletions and insertions;
- WER per category;
- transcription latency p50/p95;
- per-clip results.

From Milestone 4 the report adds:
- edit distance between the cleaned output and `expected`;
- cleanup guard rejections;
- latency per pipeline stage.
