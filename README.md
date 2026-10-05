# Murmur

*Working name; the final name is still to be chosen.*

A native macOS app for two jobs:

- **Dictation anywhere.** Hold Fn, speak, release. Clean text lands on the clipboard and,
  optionally, in the app you are typing in.
- **Meeting notes.** Records your mic and the call audio without a bot joining, then produces a
  speaker-labelled transcript, notes and action items.

It is local-first. Speech recognition runs on-device (Parakeet on the Apple Neural Engine via
FluidAudio), and cleanup uses Apple's on-device model. There are no word limits, no
subscription and no telemetry.

## Status

**Milestone 2 of 6: push-to-talk dictation to the clipboard.**

Hold Fn (or Right Option / Right Command), speak and release. Parakeet transcribes on the
Neural Engine and the text goes to the clipboard. Double-tap for hands-free; Esc cancels.

There is no cleanup, auto-paste or meeting recording yet. See the milestones in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §18.

| Document | Contents |
|---|---|
| [docs/TESTING.md](docs/TESTING.md) | How to install on your Mac, and the checklist for each milestone |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The approved design, decision log and milestones |
| [docs/REFERENCE_NOTES.md](docs/REFERENCE_NOTES.md) | What nine open-source dictation and meeting apps do, what to borrow, licences |
| [evals/README.md](evals/README.md) | Measuring accuracy and latency on recordings of your own voice |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Credits and licence texts |

## Build and install

```bash
make signing   # once: pick a stable code-signing identity so permissions survive rebuilds
make install   # build, sign and copy to /Applications
```

Then launch Murmur from Spotlight. Don't launch it from a terminal: macOS would attach the
permissions to the terminal instead of Murmur.

| Command | What it does |
|---|---|
| `make test` | Core unit tests |
| `make eval` | Accuracy and latency report |
| `make references` | Clone the reference projects at their pinned commits into `./references/` (gitignored) |

## Requirements

- Apple Silicon Mac with macOS 14.2 or later.
- Xcode 16.4 or later, or the Command Line Tools, to build.
- From Milestone 4: macOS 26 or later with Apple Intelligence on, for the on-device cleanup
  model.
