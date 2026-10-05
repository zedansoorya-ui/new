# Testing Murmur on your Mac

Each milestone ends with a checklist here. Run it on the Mac after pulling the branch, then send
back the results and the output of **menu bar ▸ Copy Diagnostics**. Diagnostics contain no
transcript text unless *verbose diagnostics* is switched on.

## One-time setup

1. **Install the Command Line Tools** (`xcode-select --install`) or Xcode. Murmur builds with
   `swift build`, so a full Xcode is not required.
2. **Clone the repo and check out the branch:**
   ```bash
   git clone https://github.com/zedansoorya-ui/new.git murmur && cd murmur
   git checkout claude/zen-cerf-uy3oof
   ```
3. **Pick a signing identity.** This keeps macOS permissions working across rebuilds:
   ```bash
   make signing
   ```
   It uses an Apple Development certificate if you have one (Xcode ▸ Settings ▸ Accounts, any
   free Apple ID). If you have none, run `scripts/setup-signing.sh --self-signed`, which
   creates a local certificate and asks for your password once.

**Without building:** every CI run uploads an ad-hoc-signed `Murmur-ci-adhoc.zip` artifact
(under the run's Summary on GitHub, while signed in). It works for a quick look, but:
- macOS blocks it the first time, because it isn't notarised. Since macOS 15, right-click ▸ Open
  no longer gets past this. After the first attempt, go to System Settings ▸ Privacy & Security
  and click **Open Anyway**. Alternatively, clear the download flag in Terminal:
  `xattr -dr com.apple.quarantine /Applications/Murmur.app`.
- macOS forgets its permissions whenever you install a newer one.

**Troubleshooting**

| Symptom | Cause and fix |
|---|---|
| `open -a Murmur` says it can't find the app | It isn't installed yet. `make install` copies it to Applications and prints `Installed /Applications/Murmur.app.` when done. If it stopped earlier, the usual cause is a missing signing identity: run `scripts/setup-signing.sh --self-signed`, then `make install` again. |
| `make install` fails with "Permission denied" | Your account can't write to `/Applications`, which happens on managed Macs. Report it; the installer can use `~/Applications` instead. |

## Milestone 2: Fn → Parakeet → clipboard

### Install and first launch

```bash
git pull
make install
```

1. **Launch Murmur from Spotlight** (⌘Space, "Murmur"), not from the terminal. A small dark
   capsule appears at the bottom centre of the screen, and a waveform icon in the menu bar.
2. **The setup window opens:**
   - Allow **Microphone**.
   - Open **Accessibility** and switch Murmur on.
   - For the Globe key, open **Keyboard Settings** and set *Press 🌐 key to* → **Do Nothing**.
     Or tick *Take over Globe key* instead.
   - Wait for **Speech model** to say Ready. It downloads about 630 MB, once.

### Checks

Tick each one, or describe what happened instead.

| # | Do this | Expected |
|---|---|---|
| 1 | Hold **Fn**, say "The quick brown fox jumps over the lazy dog", release | Pill shows a red dot, waveform and timer while you talk, then *Transcribing*, then *✓ Copied*. ⌘V anywhere pastes the sentence. |
| 2 | Menu bar ▸ Copy Diagnostics, paste it somewhere | Under *Recent dictations*, `release→clipboard` is **under 1000 ms** |
| 3 | Tap **Fn** quickly (under ~0.15 s) | Nothing happens: no pill change, nothing copied. The orange mic dot in the menu bar may blink, because recording starts on press so your first word isn't cut off. |
| 4 | In a text editor, press **Fn+←** and **Fn+→** | The cursor jumps to line start/end as usual; no dictation |
| 5 | Double-tap **Fn**, let go, speak for ~10 s, tap **Fn** once | Recording continues after release (pill says *Hands-free*); the final tap transcribes |
| 6 | Hold **Fn**, speak, press **Esc** | *Cancelled*; nothing copied; the Esc does not reach the app you're in |
| 7 | Click the small idle pill, speak, click it again | Same as hands-free |
| 8 | Type in TextEdit, dictate with Fn, keep typing | The TextEdit cursor never loses focus; the pill never takes it |
| 9 | Make Safari full screen and dictate; switch to another Space and dictate | The pill is visible in both |
| 10 | Right-click the pill | Menu with *Start Hands-free Dictation* and your recent dictations |
| 11 | Menu bar ▸ Hotkey ▸ Right Option, then hold Right Option and dictate | Works the same as Fn |
| 12 | Dictate for about a minute in hands-free mode | Text arrives (slower than short clips for now; Milestone 3 fixes long-form latency) |

**Report back:** which rows passed, anything odd, and the diagnostics text.

### Known limits in Milestone 2

- **No cleanup yet.** Text is Parakeet's raw output with basic spacing fixes; fillers stay.
  Cleanup arrives in Milestone 4.
- **No auto-paste yet.** Text goes to the clipboard only.
- **Long dictations** (more than ~15 s) are transcribed after you stop, so they take longer.
  Milestone 3 transcribes while you talk.
- **Fn+Ctrl** (command mode) currently just dictates. The rewrite behaviour arrives in
  Milestone 4.
- **Changing the speech model** in the menu takes effect after relaunching Murmur.
