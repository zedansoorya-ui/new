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

**Milestone 1 of 6 — reference study and architecture.** There is no app code yet.

| Document | Contents |
|---|---|
| [docs/REFERENCE_NOTES.md](docs/REFERENCE_NOTES.md) | What nine open-source dictation and meeting apps do, what to borrow, licences |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The approved design, decision log and milestones |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Credits and licence texts |

To read the reference projects locally, run `scripts/fetch-references.sh`. It clones them at
the pinned commits into `./references/`, which is gitignored.

## Requirements (planned)

- Apple Silicon Mac, macOS 14.2 or later.
- macOS 26 or later with Apple Intelligence enabled, for the on-device cleanup model.
