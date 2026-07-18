# Workflow recipes — demo to finished track

End-to-end paths from "I have an idea" to "I have a finished song." Each recipe lists trigger condition, Suno features used, and step-by-step.

## Decision tree: Cover vs Extend vs Replace Section vs Reuse

You have a generated song or uploaded demo. Now what?

| Want | Use | Why |
|------|-----|-----|
| Same melody, different style | **Cover** | Re-renders the song in a new style while preserving melody/lyrics |
| Continue past the end (longer song) | **Extend** | Adds new sections from a chosen point. `Quick Extend` for seamless |
| Fix one bad section in the middle | **Replace Section** (Pro/Premier) | Surgical swap; rest of the song stays intact |
| Use the audio as a seed for a new generation | **Reuse** + Audio Influence slider | Demo becomes input, model creates fresh interpretation |
| Generate vocals over an instrumental I made | **Audio Upload** + style prompt | Treat upload as instrumental bed, prompt for vocal performance |

## Recipe 1: Demo upload → finished track

**Starting point:** you have a recorded demo (vocal acapella, instrumental sketch, melody hum, full rough demo).

**Steps:**

1. **Upload Audio** → button next to `Create` on Create page
2. Demo lands in Library (reusable later)
3. Choose path:
   - Full re-imagining → **Cover** in target style
   - Vocal performance over your instrumental → keep upload, prompt for vocals only (style prompt should describe vocals + the existing instrumental should not be re-described)
   - Use as melodic / harmonic seed → set as **Audio Influence**, generate fresh
4. **Audio Influence slider** appears as the third creative slider (alongside Weirdness + Style Influence). Tune:
   - 80-100% — demo strongly shapes output (use when demo is the spine)
   - 50% — balanced; demo is reference, model has creative liberty
   - 20% — demo is loose vibe inspiration only
5. Generate 4 versions
6. Pick winner → open in Studio
7. (Optional) Replace Section on weak spots
8. (Optional) Stem export → external DAW for final mix
9. Export full mix

**Upload limits** (verified 2026-07-18 against <https://suno.com/pricing>):

| Tier | Max upload |
|------|-----------|
| Free | up to 8 minutes |
| Pro / Premier | up to 30 minutes |

## Recipe 2: Edit / rearrange an existing song

**Starting point:** you generated a song. Verses are in wrong order, or you want to add a new section.

**Steps:**

1. Open the song in **Studio** (Premier tier)
2. Each section appears as a clip on the timeline
3. **Drag clips** to rearrange — verse 2 before verse 1, chorus repeated, bridge moved
4. **Cut / split clips** to subdivide
5. To add a NEW section between existing ones:
   - Position playhead at insertion point
   - `Add a new track` → arm Record → generate the new section
   - Suno produces alternates in **Take Lanes**
   - Audition → `Copy to Main Track` to finalize
6. (Optional) `Remove FX` per clip to dry the audio for consistency
7. Use **Warp Markers** if section transitions need timing tightening
8. Export `Full Song` or `Multitrack`

## Recipe 3: Add an instrument to existing track

**Starting point:** existing song needs a new instrument layer (sax solo, string pad, harmony vocal, percussion fill).

**Steps:**

1. Open in **Studio**
2. `Add a new track` for the new instrument
3. Arm with Record button
4. Set the prompt for that track only — describe just the instrument:

   ```
   tenor sax solo, smooth jazz phrasing, breathy mid-register, 8-bar lead
   ```

5. Generate → multiple alternates in Take Lanes
6. Audition each alternate against the playing track
7. `Copy to Main Track` to lock the winner
8. (Optional) Comp across alternates if no single take is perfect — splice best phrases from each
9. Export

**Tip:** generate the new instrument over a SHORT loop region first (8-16 bars). Once you have a take you like, regenerate over full song length using that take as reference.

## Recipe 4: Replace one bad instrument

**Starting point:** the drums are wrong / the bass is muddy / the lead synth doesn't fit.

**Steps:**

1. Open in **Studio**
2. Mute or delete the offending track
3. `Add a new track` for the replacement
4. Prompt narrowly — describe just the instrument:

   ```
   punchy 808 trap drums with hi-hat triplets, no other percussion, 140 BPM
   ```

5. Generate → audition Take Lanes → `Copy to Main Track`
6. Re-mix levels (drag track volume sliders)
7. Export

## Recipe 5: Vocal cloning + custom backing

**Starting point:** you trained a Voice (your singing identity) and want a song featuring it.

**Steps:**

1. Custom mode + select your Voice
2. **Drop all gender/tone descriptors** from the style prompt (see `voices.md`)
3. Style prompt describes only the BACKING (genre, instrumentation, BPM, production)
4. Lyrics field — full song lyrics with section tags + performance directives in `()`
5. Audio Influence slider ≥70% to preserve vocal identity
6. Generate 4 versions
7. (Optional) Open winner in Studio for arrangement tweaks
8. Stem export → external DAW for final polish

## Recipe 6: Iterative cover chain

**Starting point:** you have a melody you love but want to test multiple genres.

**Steps:**

1. Generate or upload the original
2. **Cover** in style A (e.g., orchestral)
3. **Cover** the original again in style B (e.g., trap)
4. **Cover** the original in style C (e.g., bossa nova)
5. Compare the three — a melody sometimes shines in unexpected genres
6. Pick the winner → continue refining via Studio

Note: covers chain. Cover-of-cover-of-cover is allowed; each version traces back to original. Commercial-use rights apply only to YOUR originals — covers of someone else's track are not commercially usable.

## Recipe 7: Comp the perfect vocal

**Starting point:** every alternate of the vocal has SOME good moments and some bad.

**Steps:**

1. Open in Studio, navigate to the vocal track
2. Take Lanes show all generated alternates
3. Edit Mode → split each alternate at section boundaries (verse/chorus/bridge)
4. Audition each section across alternates
5. Drag the best section from each alternate onto the main track
6. (Optional) Crossfade at splice points to avoid clicks
7. `Remove FX` per spliced section if reverb tails clash
8. Re-export

## Recipe 8: Build from a hummed melody

**Starting point:** you hummed a melody into your phone.

**Steps:**

1. **Upload Audio** the hum
2. Set as **Audio Influence** at 60-80%
3. Style prompt describes the target arrangement (full band, instrumentation, mood, BPM)
4. Lyrics field with section structure + actual lyrics
5. Generate 4 versions
6. Model interprets the hum as melody guide while building the arrangement
7. Pick winner → Studio for refinements

## Recipe 8a: Demo as Custom Model training data

**Note:** Custom Models train on **finished tracks YOU own**, not on demos. If you have a catalog of 6+ owned originals, train a Custom Model on those. Demos / unfinished sketches aren't the right input — use as Audio Influence on a per-song basis instead.

## Sources

`help.suno.com/en/articles/6141569` (Audio Uploads), `help.suno.com/en/articles/6141377` (Creative Sliders), `help.suno.com/en/articles/5663873` (Remix FAQs / Cover), `help.suno.com/en/articles/2409601` (Extend), `help.suno.com/en/articles/3271873` (Replace Section), `help.suno.com/en/articles/6141505` (Song Editor).
