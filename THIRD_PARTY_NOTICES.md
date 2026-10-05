# Third-party notices

Murmur builds on the open-source projects below. This file has two parts:

1. **Dependencies** linked into the app.
2. **Adapted code**: projects whose source we adapt, with their full licence texts.

Each source file adapted from one of these projects starts with a header naming the project, the
original path, the commit and the licence. As of Milestone 1, **no third-party code has been
copied into this repository yet**. Entries under "Adapted code" are pre-approved sources (see
`docs/ARCHITECTURE.md`, decision D3). The files that use them will be listed under each entry as
they land.

Never used as a source: VoiceInk (GPL-3.0), dictator (no licence), and anything under anarlog's
`enterprise/` directory (commercial licence).

---

## 1. Dependencies

### FluidAudio

- Project: https://github.com/FluidInference/FluidAudio
- Licence: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
- Use: Swift package dependency, pinned to an exact version (added in Milestone 2). It provides
  ASR, VAD, diarization, ITN and echo cancellation.
- Models downloaded at runtime carry their own licences. Parakeet models are derived from
  NVIDIA checkpoints under CC-BY-4.0; Sortformer is under the NVIDIA Open Model License;
  LocalVQE is under Apache-2.0; Silero VAD is under MIT. These are attributed in the app's About
  window.

Further dependencies (for example GRDB.swift, MIT) are added here when they enter
`Package.swift`.

---

## 2. Adapted code

### Muesli

- Project: https://github.com/Muesli-HQ/muesli (commit `906df1c743642546a2e9cb8a43a9797c31186a28`)
- Planned use: audio capture, system-audio tap, paste and clipboard handling, dictionary
  matching, meeting detection, transcript merging, onboarding. Mapping in `docs/ARCHITECTURE.md`
  §17.
- Files in Murmur: none yet.

```
MIT License

Copyright (c) 2026 Pranav Hari

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### PushText

- Project: https://github.com/EvanCNavarro/PushText (commit `adf166086f871533115d94afdef4099cbcde9836`)
- Planned use: event-tap hotkey monitor, dictation state machine with watchdog, cleanup drift
  guard.
- Files in Murmur: none yet.

```
MIT License

Copyright (c) 2026 Evan C. Navarro

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### AudioCap

- Project: https://github.com/insidegui/AudioCap (commit `6f609e8ad1b1e11fa0e8edbe91864cb099f00de3`)
- Planned use: System Audio Recording permission probe (TCC preflight/request).
- Files in Murmur: none yet.

```
Copyright (c) 2024 Guilherme Rambo

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### meetily

- Project: https://github.com/Zackriya-Solutions/meetily (commit `a2cb62e827da7ef59f65064c97233efb2313878e`)
- Planned use: meeting-template JSON schema and template-filling pattern.
- Files in Murmur: none yet.

```
MIT License

Copyright (c) 2024 Zackriya Solutions

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### anarlog (community edition, outside `enterprise/`)

- Project: https://github.com/fastrepl/anarlog (commit `91d47ae603dd17153a6c0920fdf9661ef5398cdf`)
- Planned use: structure of the notes-merge ("enhance") prompt.
- Files in Murmur: none yet.

```
MIT License

Copyright (c) 2023-present Fastrepl, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
