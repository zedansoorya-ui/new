#!/usr/bin/env bash
# Clone the reference repos studied in docs/REFERENCE_NOTES.md into ./references (gitignored),
# each pinned to the exact commit the notes describe.
#
# Usage: scripts/fetch-references.sh [destination]   (default: references)
#
# Existing checkouts are left alone. Reading these repos is fine; copying code is governed by
# docs/ARCHITECTURE.md decision D3 — never copy from voiceink (GPL-3.0) or dictator (no licence).
set -euo pipefail

cd "$(dirname "$0")/.."
dest="${1:-references}"
mkdir -p "$dest"

# name | url | commit
repos=(
  "muesli|https://github.com/Muesli-HQ/muesli|906df1c743642546a2e9cb8a43a9797c31186a28"
  "fluidaudio|https://github.com/FluidInference/FluidAudio|04e363c29d9a754022d602d6fe1468ab80a0f705"
  "voiceink|https://github.com/Beingpax/VoiceInk|c09cc1f677f40f2ee665843a61f07670210f012e"
  "meetily|https://github.com/Zackriya-Solutions/meetily|a2cb62e827da7ef59f65064c97233efb2313878e"
  "anarlog|https://github.com/fastrepl/anarlog|91d47ae603dd17153a6c0920fdf9661ef5398cdf"
  "audiotee|https://github.com/makeusabrew/audiotee|56ac954369a09318e46b88a6eec33c2d2b0d32a3"
  "audiocap|https://github.com/insidegui/AudioCap|6f609e8ad1b1e11fa0e8edbe91864cb099f00de3"
  "pushtext|https://github.com/EvanCNavarro/PushText|adf166086f871533115d94afdef4099cbcde9836"
  "dictator|https://github.com/floydnant/dictator|38542525031340df34e73f0104026991bca7b978"
)

for entry in "${repos[@]}"; do
  IFS='|' read -r name url commit <<<"$entry"
  dir="$dest/$name"
  if [ -e "$dir/.git" ]; then
    echo "skip  $name (already present)"
    continue
  fi
  echo "fetch $name @ ${commit:0:7}"
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  # Shallow fetch of the pinned commit only. LFS objects stay as pointer stubs.
  GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" fetch -q --depth 1 origin "$commit"
  GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" checkout -q --detach FETCH_HEAD
done

echo "done: $(ls "$dest" | wc -l | tr -d ' ') repos in $dest/"
