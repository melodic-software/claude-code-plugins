# Suno Studio (1.2) — full guide

Suno Studio is a **Generative Audio Workstation (GAW)** — multitrack DAW in the browser, with AI generation built into the timeline. **Premier tier** — verified 2026-07-18 against <https://suno.com/pricing> (Pro has no Studio access; tiers drift, re-check before relying).

Where to go AFTER initial generation when you want to: rearrange sections, comp across multiple takes, isolate/replace instruments, fix timing, strip reverb, export stems, or build a song from scratch using AI-generated parts on individual tracks.

## Core capabilities

### Track + clip operations

- **Add tracks** — `Add a new track` button. Each track holds clips on the timeline.
- **Drag / move clips** — standard DAW timeline gestures.
- **Right-click context menu** on a clip — includes `Remove FX` (de-reverb / de-delay → "dry version"), `Download .WAV`, more.
- **Transport** — `Play/Pause` (spacebar). Bottom info panel shows tempo, time signature, position.

### Generation on a track (Take Lanes / Alternates)

The killer feature. Generate AI parts directly into a track:

1. Arm a track with the red `Record` button
2. Suno generates multiple alternates (basslines, percussion, melodies, vocals)
3. **`Take Lanes` / `Alternates`** show all generated versions in lanes under the main track
4. Audition each alternate
5. **`Copy to Main Track`** finalizes the take
6. Comp across alternates — splice the best parts of each into the main track

### Warp Markers (timing correction)

Time-stretch without pitch shift.

1. Enable **Edit Mode** on a clip
2. Click the waveform to add a Warp Marker at any beat / transient
3. Drag the marker to retime that section
4. Pitch is preserved; the rest of the clip stretches to compensate

Use cases: align drums to grid, fix a vocal that lands early on a downbeat, swing a straight rhythm.

### Remove FX

Right-click clip → `Remove FX`. Strips reverb / delay processing from the audio, producing a dry version. Useful when you want to apply your own reverb in another DAW, or when generated content has too much room sound for the mix.

### Time signature picker (1.2)

- Bottom info panel
- Numerator 1–99, custom denominator
- Updates the grid + metronome
- **Caveat: NOT yet sent to the generative model.** New clips you generate ignore the picker. Use it to reshape EXISTING clips visually; lock to 4/4 for generation.

### Project versions / auto-save

- Auto-saves continuously
- `Project Menu` → `Versions` to roll back
- Each generation creates a checkpoint

## MIDI

`Get MIDI` button — extracts a MIDI representation from a stem.

- **Cost: 10 credits** per MIDI extraction (verify current pricing)
- Useful for: chord analysis, exporting a melody to a notation app, feeding the part into a sampler / soft synth in your external DAW
- Quality varies by stem — clean monophonic leads convert best; dense polyphonic mixes are noisy

## Stem isolation / export

Studio's export menu has **3 scopes**:

| Scope | What you get |
|-------|--------------|
| `Full Song` | Final mix saved to your Library |
| `Selected Time Range` | Just the highlighted region as a clip |
| `Multitrack` | All stems exported to your device |

**Stem export formats:** MP3, WAV, Tempo-Locked WAV, MIDI, WAV+MIDI bundle.

**Tempo-Locked WAV** is the key one for DAW workflows — embeds tempo + grid info so the stem snaps cleanly when imported into Logic / Ableton / Pro Tools.

### 2-track vs 12-track stems (v5.5)

| Tier | Stem split |
|------|-----------|
| Free / lower | 2-track: vocals + instrumental |
| Pro / Premier | 12-track: drums, bass, vocals, harmony, lead synth, pads, sax/lead, percussion, FX, etc. |

12-track is what you want for serious external mixing — replace any single instrument, automate per-stem, master each lane independently.

## Demo / file upload into Studio

`Upload Audio` from Project Menu. Bring in:

- A demo recording you want to develop
- An external instrumental for vocals to be generated over
- Reference material for timing comparison

Upload limits (unverified — conflicts with the 120-second Pro/Premier figure in the tier matrix elsewhere in this skill; re-verify before relying on either):

| Tier | Max upload |
|------|-----------|
| Basic | 60 seconds |
| Pro / Premier | 8 minutes |

## What Studio does NOT do (current 1.2)

- **Third-party plugins / VSTs** — not documented in any current help article. Treat as unsupported. Do plugin work in your external DAW after stem export.
- **Time signature in generation** — picker affects grid + metronome only; generative model still works in 4/4 internally.
- **Real-time MIDI input from external controller** — generation is button-driven, not played-in.
- **Direct collaboration** — single-user project at a time (verify if Premier ever ships multi-user).

## Workflow patterns

**Comp a vocal across alternates:**

1. Generate vocal part on a track → 4 alternates land in Take Lanes
2. Use Edit Mode to splice — verse 1 from alternate 2, chorus from alternate 4, bridge from alternate 1
3. `Copy to Main Track` to finalize the comp
4. Run `Remove FX` if the alternates have inconsistent reverb
5. Export `Multitrack` for external polish

**Replace a single instrument:**

1. Open existing song in Studio (or upload it)
2. Mute / delete the unwanted instrument's track
3. `Add a new track` → generate replacement with prompt for that part only
4. Audition alternates, comp the winner
5. Re-export full mix

**Build a song from scratch:**

1. New empty project
2. Add drums track → generate 4-bar loop
3. Add bass track → generate against the drums
4. Add chord track → keys / pads
5. Add lead → melody / vocals
6. Arrange clips on timeline (intro / verse / chorus structure)
7. Comp + export

**Tighten timing on a generated track:**

1. Identify the slipping section
2. Edit Mode → place Warp Markers at downbeats
3. Drag markers to grid
4. Repeat for any drifting clips
5. Export Tempo-Locked WAV

## Sources

`help.suno.com/en/articles/7940161` (Introduction to Studio), `help.suno.com/en/articles/10625089` (Studio 1.2 release notes), `help.suno.com/en/articles/8128193` (Exporting from Studio), `help.suno.com/en/articles/6141505` (Song Editor).
