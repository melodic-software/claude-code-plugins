<!-- markdownlint-disable MD056 -->
<!-- "Signature instrumentation" annotation rows are single-cell paragraph asides
     within genre tables; padding them with empty pipes would obscure the prose. -->
# Genre taxonomy

Static reference catalog of ~220 genres organized by 12-family tree. Used by the `/suno genre` action when no template matches, and as a vibe-to-genre lookup for the `prompt` and `style` actions. Cross-link: when a family has an existing template under `templates/<name>.md`, prefer it for the prompt skeleton — this file supplies the descriptor vocabulary.

**Format conventions**

- Wide table per family; leaf genres are rows. Differentiator + signature instrumentation as one-line sub-bullets under each row when the table would otherwise wrap awkwardly.
- BPM ranges are typical sweet spots, not hard bounds. Suno responds well to a single numeric value inside the range.
- Confidence column: **H** = multiple authoritative encyclopedia/journalism sources agree (Wikipedia + AllMusic + named music journalism); **M** = community consensus across producer guides + dedicated subreddits but no single canonical encyclopedia entry; **L** = niche/regional, limited cross-source corroboration, treat instrumentation as representative not definitive.
- "Key tendency" describes the harmonic bias (minor/major, modal). Specifying a key in Suno is HIGH confidence per `style.md` — these tendencies are descriptive defaults, not prescriptions.
- "Vocal style" is acoustic-descriptor language (clean / raw / melismatic / spoken / growled / falsetto / etc.) — feed these directly into the Suno style prompt's vocal layer.

**How to use this catalog with the skill**

- `/suno genre <name>` — if a template exists, load it; otherwise return the row from this file as a synthesized starter.
- `/suno prompt <intent>` — when a vibe is given, scan the Vibe-to-genre map at the bottom, pick 1-2 candidates, then pull the row to fill the 6-layer formula.
- Combine families to build a fusion (see Fusion patterns at the bottom).

---

## 1. Rock

Template: `templates/rock.md`. The umbrella subdivides by era (classic / alt / indie / modern), aggression (punk / hard rock), and crossover (folk-rock / blues-rock / country-rock). 6/8 and 12/8 feels common in blues-rock and classic; 4/4 dominates everywhere else.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Classic rock | 1968-1979 | US/UK | 110-140 | Minor pentatonic / blues | Belted male tenor, occasional rasp | Warm analog, tape compression, live-room drums | Bold, anthemic, swaggering | H |
| Hard rock | 1970-1985 | US/UK | 115-145 | Minor, power-chord | Wailing high-tenor, throaty | Cranked Marshall stacks, layered guitars, gated reverb on snare | Aggressive, confident, larger-than-life | H |
| Glam rock | 1971-1980 | UK/US | 120-140 | Major lead, minor verses | Theatrical, androgynous, sneer | Glossy stereo guitars, hand-claps, layered "ooh" backing | Decadent, flashy, theatrical | H |
| Garage rock | 1964-1969; revival 2001-2008 | US | 130-155 | Minor pentatonic | Sneering, lo-fi shout | Single mic, tape saturation, sloppy ensemble | Raw, sneering, immediate | H |
| - *Signature instrumentation:* Fuzz Vox or Farfisa-style organ + distorted Telecaster + tambourine + minimal drum kit. *Differentiator:* Recording artifacts ARE the aesthetic; cleanness sounds wrong. |
| Surf rock | 1961-1965 | California | 130-180 | Minor harmonic, double-picked | Mostly instrumental; sparse close-harmony when present | Heavy spring reverb, single-coil bright | Sunny, energetic, cinematic | H |
| - *Signature instrumentation:* Fender Jaguar/Jazzmaster through Fender Reverb tank + standup bass + four-on-floor surf beat + occasional sax. |
| Psychedelic rock | 1966-1972 | US/UK | 80-130 | Modal, key changes | Languid, drifting, occasionally chanted | Backwards tape, phaser, panned stereo trickery | Trippy, expansive, surreal | H |
| Southern rock | 1972-1979 | US (Florida/Georgia/Alabama) | 110-135 | Major, blues-pentatonic | Drawled male tenor, gritty | Twin lead guitars, B3 organ, dry analog mix | Earthy, swaggering, rebellious | H |
| Blues rock | 1968-present | US/UK | 90-130 | Dominant 7th, blues scale | Smoke-and-whiskey rasp | Live ensemble, minimal overdubs, tube saturation | Soulful, world-weary, defiant | H |
| Folk rock | 1965-1971; revival ongoing | US/UK | 100-130 | Major, modal | Clean melodic, often harmonized | Acoustic 12-string forward, jangly electrics, light reverb | Earnest, literate, melancholy | H |
| Country rock | 1968-1979 | California | 100-130 | Major, country blues | Plaintive harmony, twang | Pedal steel + Telecaster, dry mix | Wistful, road-weary, hopeful | H |
| Heartland rock | 1980-1992 | US Midwest | 115-135 | Major, simple I-IV-V | Anthemic male, weathered | Strummed acoustic + electric, big snare reverb | Working-class, sincere, nostalgic | H |
| Pop rock | 1979-present | US/UK | 100-128 | Major, diatonic | Polished melodic | Layered guitars, click-tight drums, full mastered mix | Catchy, radio-ready, accessible | H |
| Alternative rock | 1989-1999 | US/UK | 95-130 | Minor verse / major chorus | Earnest, often strained | Quiet-loud dynamics, scooped-mid guitars | Disaffected, introspective, defiant | H |
| Grunge | 1989-1996 | Seattle | 90-130 | Minor, drop-D | Raw, throat-shredded screaming | Sludgy distortion, no shimmer, dry analog | Bleak, cathartic, weary | H |
| Indie rock | 1995-present | US/UK | 100-140 | Major, modal | Conversational, often nasal | Lo-fi-leaning mid-fi, jangly Telecaster | Earnest, idiosyncratic, restrained | H |
| Indie folk | 2002-present | US/UK | 80-120 | Major, drone-friendly | Breathy, conversational | Close-mic acoustic, brushed kit, room ambiance | Wistful, intimate, autumnal | H |
| Post-punk | 1978-1984; revival 2005-2010 | UK | 130-160 | Minor, modal | Detached baritone or wail | Trebly bass forward, brittle guitars, gated reverb | Angular, anxious, austere | H |
| Post-punk revival | 2002-2008 | US/UK | 125-150 | Minor | Yelped or deadpan baritone | Dance-rock pocket drums, treble-forward mix | Sharp, urgent, knowing | H |
| Math rock | 1993-present | US | 90-160; shifting | Modal, irregular meters | Often instrumental; spoken-pitch when present | Clean guitars, tapping, polyrhythmic drums | Cerebral, playful, technical | H |
| Post-rock | 1994-present | UK/Canada | 70-110 | Major, modal, drone | Mostly instrumental; ethereal when present | Glassy delay-soaked guitars, slow crescendos, real drums | Cinematic, melancholy, expansive | H |
| Emo (3rd wave) | 2002-2008 | US Midwest | 130-160 | Minor pentatonic | Cracked, near-scream pop melodics | Compressed guitars, double-tracked vocals, polished | Anguished, earnest, cathartic | H |
| Emo (5th wave) | 2018-present | US online | 110-150 | Minor, drop tunings | Pop-punk croon | Trap hi-hats blended with rock kit, slick mix | Sad, nostalgic, online | M |
| Pop punk | 1994-2007 | US (SoCal) | 150-185 | Major | Nasal melodic | Distorted but clean, four-on-floor punk feel | Bratty, hopeful, energetic | H |
| Hardcore punk | 1980-1986; ongoing | US (LA/DC) | 180-220 | Minor pentatonic | Shouted, gang vocals | Trebly distortion, blast snare, dry production | Angry, urgent, raw | H |
| Skate punk | 1992-2002 | California | 180-220 | Major | Snotty melodic | Tight palm-muted chugs, melodic leads | Defiant, hyperactive, sunny | H |
| Krautrock | 1969-1977 | Germany | 100-130 | Modal, drone | Often instrumental; chanted/spoken when present | Motorik 4/4, analog synths, dub mix tricks | Hypnotic, mechanical, transcendent | H |
| Shoegaze | 1989-1995; revival ongoing | UK | 100-140 | Major-ish | Buried, whispered, androgynous | Wall-of-sound guitars, reverse reverb, vocals under guitars | Dreamy, dense, melancholic | H |
| Dream pop | 1985-present | UK/US | 90-120 | Major | Breathy, layered, often female | Chorused guitars, reverb tails, warm pads | Hazy, romantic, ethereal | H |

---

## 2. Metal

Template: `templates/metal.md`. Down-tuned guitars define the family; subdivisions are by aggression vector (speed / heaviness / atmosphere / technicality) and vocal approach (clean operatic / harsh growl / shriek).

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Heavy metal (NWOBHM) | 1979-1983 | UK | 130-180 | Minor, harmonic minor | Operatic high-tenor | Live-room drums, midrange-heavy guitars | Epic, mythic, defiant | H |
| Thrash metal | 1983-1991 | Bay Area / NY / Germany | 150-220 | Minor pentatonic, chromatic | Shouted-sung tenor (not growled) | Scooped-mid distortion, double-bass kicks, picked-bass | Aggressive, technical, urgent | H |
| - *Signature instrumentation:* Tremolo-picked rhythm + dual lead Gibson Explorer/Flying V + double-kick acoustic kit + pick-played bass. *Differentiator:* NWOBHM speed × hardcore-punk aggression × prog technicality; vocals NOT growled. |
| Death metal (Florida) | 1989-1996 | Tampa, FL | 150-210 | Chromatic, diminished | Deep growls, full-throated roars | Studio polish (Morris Sound), tight blast beats | Brutal, technical, ominous | H |
| Death metal (Stockholm) | 1990-1995 | Stockholm | 150-200 | Minor pentatonic, chromatic | Mid-register growls | Boss HM-2 buzzsaw guitar (maxed), Sunlight Studio mix | Filthy, primal, decaying | H |
| - *Signature instrumentation:* Boss HM-2 distortion pedal cranked all dials + tremolo-picked downtuned guitars + double-bass kicks. *Differentiator:* Buzzsaw HM-2 tone is the entire identity — without it, this is generic death metal. |
| Melodic death metal (Gothenburg) | 1995-2005 | Gothenburg, SE | 140-180 | Minor, harmonic minor | Mid-range growls, occasional clean | Polished, harmonic-rich, melodic lead-guitar layers | Melancholy, epic, melodic | H |
| Brutal death metal | 1991-present | NYC (Long Island) | 140-200 with breakdowns | Chromatic | Pitch-shifted gutturals | NY hardcore aggression, breakdown emphasis | Punishing, primitive, suffocating | M |
| Slam death | 2000s-present | International | 90-160 | Chromatic | Pig-squeal + extreme low gutturals | Compressed breakdowns, drum triggers | Goofy-brutal, crushing | M |
| Black metal (2nd wave) | 1991-1996 | Norway | 180-260 | Harmonic minor, Phrygian dominant | High-pitched shrieks, layered delay | Raw 4-track lo-fi, clicky kick, intentional hiss | Icy, hateful, nihilistic | H |
| Atmospheric black metal | 1996-present | Norway/Cascadia | 100-180 | Modal, drone | Distant shrieks + clean chants | Long reverb tails, ambient interludes | Vast, pagan, mournful | H |
| Blackgaze | 2010-present | France/US | 120-180 | Major-leaning | Shrieks transitioning to clean melodic | Wall-of-sound shoegaze pedals, dynamic builds | Bittersweet, transcendent, dreamy | H |
| - *Signature instrumentation:* My Bloody Valentine-style reverb walls (Big Muff / Strymon) + tremolo-picked harmonized leads + polished double-kick + ethereal pads. *Differentiator:* Black metal aggression refracted through shoegaze melody; cleans in the chorus signal blackgaze (not BM-with-effects). |
| Doom metal | 1978-present | UK/Sweden | 50-100 | Minor, blues-pentatonic | Mournful clean baritone, occasional wail | Down-tuned tube saturation, slow plodding kit, organ optional | Heavy, occult, mournful | H |
| Sludge metal | 1989-present | New Orleans | 60-120 | Minor, drop tunings | Shouted, hardcore-rasp | ProCo RAT-style distortion, bass-rig guitars, dirty mix | Filthy, hostile, suffocating | H |
| Stoner metal / desert rock | 1991-present | Palm Desert, CA | 80-130 | Modal, blues | Bluesy melodic shout | Big Muff fuzz + Fender amps, dry analog warmth | Hypnotic, fuzzy, transcendental | H |
| Progressive metal | 1988-present | US/Sweden | 100-200+, shifting | Modal, irregular meters | Clean melodic high-tenor + occasional growl | Polished multi-layer, Mesa Boogie cleans/distortion | Cerebral, virtuosic, expansive | H |
| Power metal | 1986-present | Germany/Italy/Scandinavia | 140-200 | Major, harmonic minor | High operatic clean, multi-tracked | Bright arena polish, double-kick galloping | Triumphant, fantastical, anthemic | H |
| Symphonic metal | 1996-present | Netherlands/Finland | 120-180 | Minor, harmonic minor | Operatic soprano + male growl duets | Real-or-sampled full orchestra, blast drums | Bombastic, gothic, cinematic | H |
| Folk metal | 1995-present | Finland/Ireland/Germany | 110-170 | Modal, folk modes | Clean folk chants + growls | Acoustic folk instruments live with thrash kit, beer-hall energy | Pagan, rowdy, mythic | H |
| Viking metal | 1990-present | Scandinavia | 100-150 | Minor, modal | Hoarse chants + growls | Layered male vocals, war-drum kit | Heroic, ritualistic, mythic | M |
| Nu-metal | 1995-2005 | US (SoCal/Florida) | 75-110 | Drop-tuned 7-string | Rapped + sung (often nasal) | Turntables, slap bass, compressed kit | Angsty, urban, aggressive | H |
| Metalcore | 2001-2010 | US (NE/Midwest) | 150-200 with breakdowns | Minor pentatonic | Screamed verse + clean chorus | Tight quantized chugs, parallel-compressed kit | Cathartic, anthemic, urgent | H |
| Deathcore | 2005-present | US | 150-220 with slams | Chromatic, drop tunings | Pig squeals + low gutturals | Drum triggers, brutal low-end, slam breakdowns | Annihilating, punishing | H |
| Djent | 2007-present | UK/US | 120-170 | Drop-tuned 7/8-string, polymeter | Clean melodic + roars | Quantized palm-mute chugs (Axe-Fx), ambient pads | Mechanical, cerebral, percussive | H |
| Post-metal | 2001-present | US (Boston) | 70-130 | Modal, drone | Buried screams + buried cleans | Spatial reverb, slow crescendos, no vocals upfront | Cinematic, crushing, contemplative | H |
| Grindcore | 1986-present | UK | 200-300+, blast | Chromatic | Cookie Monster + high screech (dual) | Wall-of-chaos, sub-2-minute songs | Apocalyptic, frantic, brutal | H |
| Mathcore | 1996-present | US | 120-200, polymeter | Atonal, dissonant | Shrieked + screamed | Stop-start dynamics, dissonant guitars | Chaotic, technical, abrasive | M |
| Drone metal | 1991-present | US Pacific NW | 30-50 or arrhythmic | Drone, modal | Buried chants, often wordless | Sustained feedback, single-chord epics | Hypnotic, oppressive, ritual | M |

---

## 3. Pop

Template: `templates/pop.md`. Pop is hook-engineering wrapped around the production zeitgeist of the decade; subdivisions track production fashion (analog synths / R&B-blend / EDM-influence / hyperpop chaos) and demographic targeting (teen / adult-contemporary / global-export / niche).

<!-- chord/vocal-production vocabulary in table trips the spell-checker --><!-- spellchecker:off -->
| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Synth-pop | 1980-1987; revival ongoing | UK | 110-130 | Major, often modal | Clean melodic, often male alto/female alto | Analog synths (DX7 FM bass, Jupiter pads), drum machines (LinnDrum, TR-707), gated reverb on snare | Nostalgic, hopeful, longing | H |
| Dance-pop | 1988-present | US/UK | 110-128 | Major | Polished melodic | Sidechain-pumped pads, four-on-floor, EDM drops | Euphoric, escapist, glossy | H |
| Electropop | 2007-2015 | UK/Sweden | 120-130 | Major, minor verses | Processed melodic (Auto-Tune as effect) | Sawtooth supersaws, sidechain bass, big drops | Confident, futuristic, club-ready | H |
| Dream pop | 1985-present | UK/US | 90-120 | Major | Whispered/breathy female (often) | Chorused guitars, reverb tails, warm pads | Hazy, romantic, ethereal | H |
| Indie pop | 1985-present | UK/US | 100-130 | Major | Nasal/conversational | Twee jangly guitars, light kit, mid-fi mix | Quirky, earnest, melancholic | H |
| Bedroom pop | 2017-present | online | 75-110 | Major-with-jazz-7ths | Whispered melodic, lo-fi mic | Chillwave keys, drum-machine kit, off-kilter mix | Intimate, hazy, melancholic | H |
| - *Signature instrumentation:* Cassette-warm chord pads + brushed lo-fi drum machine + reverb-soaked vocal mic + DI bass. *Differentiator:* Production sounds like a teenager's bedroom — not "lo-fi as aesthetic" but actually lo-fi. |
| Hyperpop | 2018-present | online | 135-180 | Major, often pitched-up | Heavy Auto-Tune (fast retune), chipmunk formant | Distorted 808s, bitcrushed hi-hats, OTT compression | Chaotic, maximalist, ironic | H |
| K-pop | 1996-present | South Korea | 90-128 | Major, EDM verse-rap-chorus structure | Multi-vocal-style (rap + sing + ad-lib) | Hyper-polished, multi-genre-blend, EDM drops | Slick, dramatic, choreographic | H |
| J-pop | 1990-present | Japan | 110-140 | Major, melodic-minor borrowings | Bright clean female melodic | Bright mix, ornate arrangements, anime-friendly | Bright, melodic, sentimental | H |
| Latin pop | 1995-present | Latin America | 95-125 | Major | Smooth Spanish-language melodic | Light Latin percussion, polished pop production | Romantic, danceable, warm | H |
| Europop | 1991-2003 | Sweden/Germany | 120-135 | Major | Multi-tracked clean, often female | Eurodance synths, hi-NRG four-on-floor, gated snare | Catchy, glossy, escapist | H |
| Bubblegum pop | 1968-1972; 1996-2002 | US | 110-135 | Major | Sugary multi-tracked harmony | Tight pop production, light kit | Sunny, childlike, addictive | H |
| Teen pop | 1998-2003 | US/UK/Sweden | 95-125 | Major | Polished young vocals (often female) | Max Martin-school polish, big chorus production | Aspirational, hopeful, energetic | H |
| Art pop | 1971-present | UK/US | 80-130 | Modal, surprising changes | Idiosyncratic, often theatrical | Genre-collision, baroque or avant-garde arrangements | Cerebral, surreal, ambitious | H |
| Baroque pop | 1966-1971; revival ongoing | UK/US | 90-125 | Major, modal | Smooth melodic, often falsetto-tinged | Harpsichord, string quartet, brass, mellotron | Ornate, melancholic, literary | H |
| Chamber pop | 1995-present | US/UK | 80-120 | Major | Earnest melodic | String section, woodwinds, intimate vocal mix | Literate, autumnal, wistful | H |
| City pop | 1979-1986 | Japan | 95-125 | Major-7th jazz changes | Smooth Japanese melodic | Fusion-jazz keys, slap bass, sax solos, glossy mix | Cosmopolitan, romantic, glossy | H |
<!-- spellchecker:on -->

---

## 4. Hip-hop

Template: `templates/hip-hop.md` (boom bap, conscious), `templates/trap.md` (trap and modern variants). Hip-hop subdivisions track region, era, and instrumental approach (sample-based vs. synth-based) more than genre boundaries.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Old-school hip-hop | 1979-1986 | NYC | 95-115 | Minor pentatonic, sample-driven | Conversational MC delivery | Funk/disco breaks, scratch DJing, drum machine kicks | Playful, party, foundational | H |
| Boom bap | 1990-1997; ongoing | NYC | 85-95 | Minor, jazz/soul samples | Punchline-dense lyrical rap | Sample-chopped breaks, SP-1200/MPC swing, dusty kick-snare | Gritty, lyrical, cinematic | H |
| Conscious hip-hop | 1988-present | US (East Coast) | 85-100 | Minor, jazz/soul samples | Articulate, didactic | Soul/jazz samples, live band optional, clean mix | Reflective, sociopolitical, literate | H |
| Gangsta rap | 1988-1996 | US (LA/NY) | 90-100 | Minor | Aggressive lyrical, often deep delivery | G-funk synth bass + sample chops, deep 808 kicks | Confrontational, vivid, dark | H |
| G-funk | 1992-1996 | Los Angeles | 90-100 | Minor, dominant-7 funk | Smooth melodic raps | Moog whine leads, P-funk samples, snap snares | Laid-back, menacing, sunny | H |
| Jazz rap | 1989-1996 | US (NYC) | 88-100 | Modal jazz, 7th chords | Conversational lyrical | Live or sampled jazz, upright bass, brush kit | Cerebral, smooth, conversational | H |
| Abstract hip-hop | 1991-present | US/UK | 85-100, varies | Modal, dissonant | Stream-of-consciousness | Sample collage, unconventional structure | Cerebral, experimental, dreamlike | H |
| Horrorcore | 1991-present | US (Detroit/Memphis) | 85-100 | Minor, dissonant | Aggressive, often shouted | Dark sample chops, eerie synth pads | Violent, theatrical, unsettling | M |
| Trap (original) | 2003-2010 | Atlanta | 130-160 (half-time feel 65-80) | Minor, dark | Aggressive lyrical | Roland TR-808 kicks + slides, triplet hi-hats, ominous melody | Menacing, swaggering, cinematic | H |
| Modern trap | 2014-present | US (Atlanta/global) | 130-160 (half-time) | Minor | Auto-Tuned melodic + ad-libs | 808 slides, rolling hi-hats, sparse melodic loops | Triumphant, melancholy, club-ready | H |
| Mumble rap | 2013-present | US | 130-160 (half-time) | Minor | Slurred, melodic, ad-lib-heavy | Trap drums, minimal melodic content | Hazy, woozy, repetitive | H |
| Melodic rap / sing-rap | 2017-present | US | 130-160 (half-time) | Major-tinged | Auto-Tuned melodic singing | Trap drums + emo-leaning chord pads | Vulnerable, melancholy, intimate | H |
| Cloud rap | 2011-present | US | 130-150 (half-time) | Major, ambient | Auto-Tuned dreamy | Reverb-soaked pads, sparse trap kit, vaporwave samples | Hazy, dreamlike, melancholic | M |
| Lo-fi hip-hop | 2015-present | online | 70-90 | Minor 7th, jazz changes | Often instrumental; mumbled when present | Vinyl crackle, sample chops, tape warble | Calm, nostalgic, study-friendly | H |
| Phonk (Memphis original) | 1991-2000 | Memphis | 60-90 (half-time) | Minor | Chopped-and-screwed pitched-down samples | Cowbell + TR-808 + lo-fi tape, screwed vocals | Hypnotic, eerie, slowed | H |
| Drift phonk | 2020-present | Russia/online | 130-160 | Minor | Pitched/distorted ad-libs, Japanese samples | Cowbell + aggressive 808s + saw-bass | High-energy, aggressive, vehicular | M |
| Phonk (Brazilian) | 2022-present | Brazil/online | 130-150 | Minor | Pitched chops | 808s with Brazilian funk tamborzão swing | Aggressive, rhythmic, hyperactive | M |
| Chopped and screwed | 1995-present | Houston | 50-70 (slowed 1.5x) | Minor | Pitched-down slurred | Slowed-and-stopped DJ technique, deep bass | Hazy, syrupy, narcotic | H |
| Chicago drill | 2011-present | Chicago | 60-70 (half-time feel) | Minor | Deadpan, aggressive | Booming 808s, sparse piano, triplet hi-hat rolls | Bleak, menacing, deadpan | H |
| UK drill | 2014-present | South London | 140-145 | Minor (often Phrygian) | Rapid UK-slang flow, monotone | Sliding 808 bass (3+3+2 polyrhythm hi-hats), dark orchestral strings | Cinematic, paranoid, aggressive | H |
| - *Signature instrumentation:* Sliding 808 bass + 3+3+2 syncopated hi-hats + dark orchestral strings + pitched vocal sample. *Differentiator:* Speed (140+) + syncopation + orchestral strings — Chicago drill is half-time/slow, UK drill is sprinting. |
| Brooklyn drill | 2019-present | NYC | 140-150 | Minor triads | Melodic-rap hybrid, aggressive | Sliding 808s + dark piano + bells, UK-flavored swing | Bouncy, aggressive, urban | H |
| Detroit drill / Detroit "scary stories" | 2019-present | Detroit | 130-150 | Minor | Hyped storytelling, Auto-Tune ad-libs | Distorted 808s, eerie piano, horror synths | Goofy-sinister, narrative, frantic | M |
| Irish drill | 2018-present | Dublin | 140-150 | Minor | Irish-accented fast flow | UK-drill production, rawer mix | Gritty, local, urgent | L |
| Grime | 2002-2008; ongoing | East London | 138-142 | Minor | Rapid double-time UK flow | Bleepy synth stabs, sparse 8-bar structure | Aggressive, frantic, urban | H |
| Afroswing | 2015-present | UK | 100-110 | Minor, modal | Melodic rap-singing, UK/African slang | Log drum + 808 bass, hi-hats, shekere, melodic keys | Bouncy, romantic, summer | M |
| Plugg | 2016-present | online | 130-150 (half-time) | Major-tinged | Auto-Tuned dreamy melodic | Serum-style plucks, sub-808s, soft kicks | Dreamy, wavy, melancholy | M |
| Rage rap | 2020-present | online | 140-160 | Minor | Screamed Auto-Tune hype | Distorted 808s, Jersey club kicks, fast hi-hats | High-energy, chaotic, mosh-ready | M |
| Trap soul | 2014-present | US | 130-150 (half-time) | Minor 7th, R&B changes | Smooth Auto-Tuned R&B melodic | Trap drums + R&B chord pads, atmospheric synths | Sensual, melancholy, intimate | H |
| Drumless rap | 2019-present | online | 60-90 or n/a | Minor 7th | Conversational, exposed | Sample loop only, no drum kit | Reflective, exposed, sparse | M |
| Hyphy | 2003-2009 | Bay Area, CA | 95-105 | Minor | Energetic, slang-heavy | Bouncy synth bass, hand claps, club-ready | Goofy-aggressive, party | M |
| Crunk | 1998-2006 | Atlanta/Memphis | 70-90 (half-time) | Minor | Shouted call-response | Aggressive 808s, simple synth stabs | Rowdy, party, aggressive | H |
| Snap | 2003-2007 | Atlanta | 95-105 | Minor | Lazy melodic | Finger-snap percussion + 808s, sparse keys | Laid-back, club, simple | M |
| Bounce (NOLA) | 1991-present | New Orleans | 95-105 | Minor | Call-response chant | Triggerman/Drag Rap break, looping | Frantic, sexual, party | M |
| Drumless soulful rap | 2020-present | online | n/a, sample tempo | Minor 7th, soul samples | Conversational | Soul sample only | Reflective, "real rap" aesthetic | L |

---

## 5. R&B / Soul

Template: `templates/rnb.md`. The family arcs from gospel-rooted classic soul through Motown/Memphis/Philly regional schools, funk, the 80s-90s contemporary R&B mainstream, and post-2010 alt-R&B (PBR&B). Vocal performance is the throughline; instrumentation modernizes per decade.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Classic soul | 1961-1972 | US (South + Detroit) | 90-120 | Major, dominant-7 | Belted, melismatic, gospel-rooted | Live horn section + Hammond B3 + tight rhythm section | Passionate, longing, declarative | H |
| Motown | 1961-1972 | Detroit | 100-135 | Major, dominant-7 | Smooth multi-tracked vocal group | Funk Brothers session band, bright dry mix, baritone sax + tambourine | Joyful, romantic, polished | H |
| Memphis soul | 1962-1975 | Memphis (Stax) | 90-115 | Major, dominant-7 | Gritty raw belt | Stax horn section, live one-take feel, simple kit | Earthy, raw, soulful | H |
| Philly soul | 1971-1979 | Philadelphia | 95-120 | Major-7 jazz changes | Smooth multi-tracked harmonies | Sigma Sound strings + woodwinds + sweet horns, MFSB band | Lush, romantic, orchestral | H |
| Funk | 1968-1980 | US (multi-region) | 95-115 | Dominant-7, modal | Shouted, JB-style | Tight one-chord vamps, syncopated bass, horn stabs, clavinet | Greasy, rhythmic, hypnotic | H |
| P-funk | 1972-1981 | Detroit/DC | 95-115 | Modal, dominant-7 | Multi-character ensemble vocals | Cosmic synths + horn section + slap bass, sprawling arrangements | Psychedelic, cosmic, comedic | H |
| Disco | 1974-1980 | NYC/Munich | 110-125 | Major, dominant-7 | Smooth multi-tracked, often female | Strings + four-on-floor kick + hi-hat on offbeats + bass octaves | Euphoric, hedonistic, glossy | H |
| Doo-wop | 1953-1962 | NYC/Philadelphia | 60-90 | Major (often 50s changes I-vi-IV-V) | Multi-tracked vocal harmony with bass voice + lead | Minimal instrumentation, vocal-forward, room ambiance | Nostalgic, romantic, naive | H |
| New jack swing | 1987-1992 | NYC | 105-120 | Minor 7th, R&B changes | Smooth melodic + occasional rap | Swung 808/909 drums + synth horns + chord stabs | Slick, urban, danceable | H |
| Quiet storm | 1976-1995 | US (radio format) | 70-95 | Major-7 jazz changes | Sultry low-register melodic | Smooth-jazz Rhodes/sax + brushed kit, late-night mix | Intimate, romantic, contemplative | H |
| Contemporary R&B | 1991-2008 | US | 75-110 | Minor 7th, jazz changes | Melismatic, multi-tracked | Hi-fi production, drum machines, synth chord pads | Sensual, polished, vocal-showcase | H |
| Neo-soul | 1995-2007 | US (Philadelphia) | 75-100 | Minor 7th, modal-jazz | Conversational melismatic | Live drums, Rhodes, warm bass, vintage analog | Earthy, contemplative, intimate | H |
| Alt-R&B (PBR&B) | 2010-present | US/Canada | 60-100 | Minor 7th, ambient | Falsetto-heavy, layered | Dark synths, sparse trap drums, reverb-drenched | Brooding, sensual, late-night | H |
| Gospel | 1930s-present | US (Black church) | 70-130 | Major, dominant-7 | Belted melismatic, call-response | Hammond B3 + piano + choir + tambourine | Triumphant, devotional, communal | H |
| Contemporary gospel | 1985-present | US | 70-130 | Major-7, jazz changes | Melismatic + choir | Slick R&B production with sacred lyrical content | Devotional, polished, anthemic | H |

---

## 6. Electronic / Dance

The largest family by subgenre count. Subdivisions follow tempo zone (house ~120-128, techno ~125-145, DnB 170-180, dubstep 138-145 half-time), and rhythmic feel (four-on-floor / breakbeat / syncopated). Template: `templates/edm.md` covers festival house/EDM; ambient and IDM crossover to `templates/ambient.md`.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Deep house | 1986-present | Chicago/NYC | 120-125 | Minor 7th, jazz chords | Smooth melodic, often female | Warm filtered bass, Rhodes pads, soft kicks | Smooth, late-night, soulful | H |
| Tech house | 2000-present | UK | 120-128 | Minor, modal | Often instrumental; sparse vocal chops | Tight punchy kicks, techy percussion, minimal melody | Driving, hypnotic, club-ready | H |
| Acid house | 1987-1990 | Chicago/UK | 120-128 | Minor pentatonic | Mostly instrumental; chanted samples | TB-303 squelching bass + TR-909 kit | Hypnotic, psychedelic, 303-driven | H |
| Garage house | 1988-1996 | NYC (Paradise Garage) | 120-128 | Major-7 | Soulful belted melodic | Funky basslines, Latin percussion, soulful vocals | Sophisticated, soulful, organic | H |
| UK garage / 2-step | 1995-2002 | UK | 130-140 | Minor 7th, R&B | Pitched-up R&B vocal chops | Syncopated 2-step kit, sub-bass, R&B samples | Skippy, sexy, urban | H |
| Speed garage | 1995-1999 | UK | 130-138 | Minor | Pitched vocal chops | Filtered house elements + reggae sub-bass | Bouncy, sub-heavy, club | H |
| Progressive house | 1993-present | UK/Netherlands | 124-130 | Major, modal | Often instrumental; soaring lead vocals when present | Long pad builds, sidechain pumping, big drops | Anthemic, euphoric, festival | H |
| Electro house | 2006-2014 | Netherlands/Sweden | 125-130 | Minor | Pitched chops, festival shouts | Buzzsaw synth lead, big-room kick, drops | High-energy, festival, bombastic | H |
| Future bass | 2014-present | US/Aus | 140-160 (half-time feel) | Major, often pentatonic | Pitched and chopped vocal samples | Supersaw chord stabs + sub-bass + trap drums | Euphoric, emotional, melodic | H |
| Bass house | 2014-present | UK | 124-130 | Minor | Pitched vocal chops | G-house growl bass + house kick + minimal melody | Heavy, club-ready, aggressive | H |
| Slap house / Brazilian bass | 2017-present | Brazil/EU | 125-128 | Minor | Pitched vocal hooks | "Slapping" wobble bass, OTT compression, big festival drops | Aggressive, festival, bouncy | M |
| Big-room house | 2012-2017 | Netherlands | 126-130 | Minor | Pitched shouts | Saw-lead drops, kick + 32nd-snare buildup | Bombastic, festival, simple | H |
| Tropical house | 2014-2018 | Norway | 100-118 | Major | Breezy melodic, often featured | Marimba/steel-drum lead, deep house bass, sidechain | Sun-warmed, vacation, chill | H |
| Detroit techno | 1985-present | Detroit | 125-140 | Minor, modal | Often instrumental; spoken samples | TR-909 kit, analog synths, sci-fi melodies | Futuristic, mechanical, soulful | H |
| Berlin techno | 1991-present | Berlin | 130-145 | Minor, modal | Often instrumental | Punishing 4/4 kicks, industrial textures, long build-and-release | Brutal, hypnotic, industrial | H |
| Minimal techno | 1996-present | Berlin/Cologne | 125-135 | Modal, drone | Mostly instrumental | Tight percussion, micro-edits, drone pads, no melody | Hypnotic, austere, cerebral | H |
| Acid techno | 1992-present | UK/EU | 130-150 | Minor pentatonic | Mostly instrumental | TB-303 + 909 + distortion, harder edges | Aggressive, psychedelic, hardcore | H |
| Industrial techno | 2010-present | Berlin/UK | 130-150 | Minor, drone | Mostly instrumental | Distorted kicks, metallic noise, harsh textures | Brutal, machine, oppressive | H |
| Uplifting trance | 1998-2008 | Netherlands | 138-142 | Minor (often Lydian) | Soaring female melodic, breakdowns | Big saw leads, anthemic chord stacks, gated builds | Euphoric, emotional, melodic | H |
| Psytrance / Goa | 1994-present | Israel/Goa | 142-150 | Minor, modal | Mostly instrumental; chanted samples | Driving 16th-note bassline, swirly leads, psy effects | Psychedelic, hypnotic, festival | H |
| Hard trance | 1993-2002 | Germany | 140-150 | Minor | Pitched chops | Hoover lead synth, kick-driven, gated reverb | Aggressive, anthemic, EU | H |
| Drum & bass (general) | 1993-present | UK | 170-180 | Minor | Pitched chops, MC features | Breakbeat (Amen / Think) + sub-bass + synth | Frantic, sub-heavy, urgent | H |
| Liquid DnB | 1999-present | UK | 170-175 | Minor 7th, jazz-soul samples | Soulful melodic, MC features | Soulful samples + rolling kit + smooth bass + jazz pads | Smooth, melodic, uplifting | H |
| Neurofunk | 1998-present | UK | 170-175 | Minor, drone | Mostly instrumental | Modulated Reese bass, metallic perc, dark sci-fi pads | Dark, technical, futuristic | H |
| Jungle | 1991-1996 | UK | 160-180 | Minor | Ragga MC chops | Amen break chops, deep sub, ragga samples | Frantic, sub-heavy, urban | H |
| Jump-up | 1994-present | UK | 170-175 | Minor | Hyped MC features | Cartoon-bass wobbles, punchy breaks | Goofy, party, club-ready | M |
| Dubstep (UK) | 2003-2008 | South London | 138-142 (half-time 69-71) | Minor | Mostly instrumental; ragga chops | Sub-bass + half-time kit + wobble synths, lots of space | Heavy, dread, half-time | H |
| Brostep | 2010-2014 | US | 138-145 | Minor | Pitched screams, chops | Distorted growl bass, wobble drops, aggressive | Aggressive, festival, brutal | H |
| Riddim dubstep | 2014-present | US/UK | 140-150 | Minor | Mostly instrumental | Triplet bass riddim, minimal melody | Hypnotic, club, minimal | M |
| Breakbeat (UK) | 1989-present | UK | 130-140 | Minor | Mostly instrumental | Funk-break drums + bass + synth stabs | Energetic, urban, party | H |
| Big beat | 1996-2002 | UK (Brighton) | 125-145 | Minor | Pitched chops | Breakbeats + rock samples + filter sweeps | Cinematic, party, swaggering | H |
| IDM (intelligent dance music) | 1992-present | UK | varies 100-180 | Modal, atonal | Mostly instrumental | Glitched percussion, melodic experimentation | Cerebral, experimental, fractal | H |
| Glitch | 1995-present | global | varies | Modal, atonal | Mostly instrumental | Clicks/cuts/pops, granular synthesis | Cerebral, broken, textural | H |
| Drum'n'bass / footwork (Chicago) | 2005-present | Chicago | 160-170 | Minor pentatonic | Pitched-up vocal stutters | Syncopated 808s, off-beat kicks, vocal chops | Frantic, dance-battle, hypnotic | H |
| - *Signature instrumentation:* Off-beat 808 kicks + pitched-up vocal stutters + metallic claps + hi-hat flurries. *Differentiator:* Designed for footwork dancers; off-beat kick patterns specifically support dance footwork battles. |
| Juke | 2005-present | Chicago | 130-160 | Minor | Hyped pitched-up vocals | 808 kicks + rolling hi-hats + wobble bass | Hyped, sexual, club | M |
| Jersey club | 2010-present | New Jersey | 130-140 | Minor | Pitched and chopped samples | Jersey-clap (rapid layered claps), 808 kicks, bed-squeak samples | Hyper, club, sexy | M |
| Baltimore club | 2000-2008 | Baltimore | 130 (often half-time) | Minor | Chopped rap chants | "Think Break" / "Sing Sing" loops, horn stabs, 909 kicks | Rowdy, party, urban | M |
| Ballroom (vogue) | 1989-present | NYC | 128-135 | Modal | Spoken/chanted house calls | "Ha" crash sample, electro/house base, vogue beat | Theatrical, queer, ferocious | M |
| Hardstyle | 2000-present | Netherlands | 140-155 | Minor | Pitched chops, MC features | Reverse bass + distorted kick, screech leads | Aggressive, anthemic, festival | H |
| Gabber / hardcore | 1991-present | Netherlands | 160-220 | Minor | Distorted shouts | Distorted overdriven kick, simple riff | Brutal, frantic, hardcore | H |
| Speedcore | 1995-present | NL/DE | 250-400+ | Minor | Distorted shouts | Frantic distorted kicks, noise | Apocalyptic, frantic, brutal | M |
| Breakcore | 1998-present | global underground | 200-300+ | Modal, atonal | Mangled samples, speedcore shouts | Mangled Amen breaks, hardcore kicks, chiptune | Chaotic, frantic, glitchy | H |
| Ambient techno | 1992-present | UK/Germany | 110-130 | Modal, drone | Mostly instrumental | Soft pads + minimal 4/4, dub-style space | Hypnotic, expansive, late-night | H |
| Microhouse / clicky house | 2001-2008 | Germany | 120-128 | Modal | Mostly instrumental | Clicky percussion + minimal kick + warm sub | Cerebral, hypnotic, intimate | M |
| Synthwave / outrun | 2008-present | online | 80-118 | Minor, often Phrygian | Often instrumental; reverbed when present | Analog supersaws, gated reverb snare, 80s-cassette texture | Nostalgic, neon, cinematic | H |
| Vaporwave | 2011-2016; ongoing | online | 70-100 | Major 7th, jazz chords | Pitched-down 80s samples | Slowed city-pop samples, infinite reverb, VHS warble | Hypnagogic, hauntological, ironic | H |
| Future funk | 2014-present | online | 100-120 | Major 7th | Pitched samples from city-pop | Funky bass + chopped breaks + 80s samples | Sunny, danceable, ironic | H |
| Mallsoft | 2014-present | online | 60-90 | Major 7th | Whispered/distant when present | Sampled muzak + field recordings + endless reverb | Liminal, nostalgic, hauntological | M |
| Witch house | 2008-2013 | US | 110-130 | Minor | Pitched-down distorted | Chopped 808s, occult samples, drag aesthetics | Occult, goth, narcotic | M |

---

## 7. Jazz

Template: `templates/jazz.md`. The family arcs from swing-era big band through bebop's small-group revolution, modal and free's harmonic expansions, and fusion's plug-in revolution. Specifying "modal" or "bop" gives Suno strong direction; vaguer "jazz" defaults to smooth.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Dixieland / New Orleans jazz | 1910-1930 | New Orleans | 100-180 | Major, blues | Often instrumental; gravelly when present | Trumpet/clarinet/trombone front-line, banjo, tuba, snare-rim kit | Joyous, polyphonic, parade | H |
| Swing / big band | 1932-1947 | US | 110-180 | Major, dominant-7 | Smooth crooner male or belted female | Full big band, walking bass, ride-cymbal kit, vocal mic | Elegant, danceable, sophisticated | H |
| Bebop | 1944-1955 | NYC | 200-300 | Modal, rapid chord changes | Often instrumental; scatting when present | Small combo (quintet), fast walking bass, brushed/sticked kit | Cerebral, virtuosic, urgent | H |
| Cool jazz | 1949-1960 | West Coast US | 90-140 | Major-7 | Cool restrained crooner when present | Restrained quintet, smooth horn arrangements, dry mix | Cerebral, restrained, intellectual | H |
| Hard bop | 1953-1965 | NYC | 130-200 | Modal, bop changes | Often instrumental | Bluesy quintet, gospel-soul-influenced grooves, hard-swinging kit | Earthy, virtuosic, soulful | H |
| Modal jazz | 1958-1965 | NYC | 100-150 | Modal (Dorian/Mixolydian) | Often instrumental | Quintet/sextet, sparse changes, sustained modal soloing | Spacious, meditative, expansive | H |
| Free jazz | 1959-1975 | NYC/Europe | varies | Atonal | Often instrumental; vocal cries when present | Small ensemble, no fixed changes, collective improvisation | Cerebral, chaotic, transcendent | H |
| Fusion / jazz fusion | 1969-1980 | US | 100-180 | Modal, complex changes | Often instrumental; soaring melodic when present | Electric guitars + Rhodes + synth + funk/rock kit | Virtuosic, electric, complex | H |
| Smooth jazz | 1986-present | US (radio) | 90-115 | Major-7, R&B changes | Smooth crooner | Sax/guitar lead + Rhodes + soft drum machine + polished mix | Polished, romantic, easy | H |
| Acid jazz | 1988-1998 | UK | 95-115 | Modal jazz with funk grooves | Soulful melodic | Live jazz combo + hip-hop breaks + funky bass | Sophisticated, danceable, urban | H |
| Nu-jazz | 1996-present | Europe | 100-130 | Modal, electronic | Often instrumental | Jazz instrumentation + electronic production, downtempo-leaning | Cerebral, hypnotic, urban | M |
| Spiritual jazz | 1966-present | US | 80-150 | Modal | Chanted, often female | Modal piano + sax + Eastern instruments (sitar, oud) | Devotional, transcendent, vast | H |
| Latin jazz | 1947-present | NY/Cuba | 100-180 | Major, dominant-7 | Often instrumental; Spanish when present | Clave-driven percussion + jazz combo, conga + bongo | Hot, danceable, sophisticated | H |
| Vocal jazz | 1944-present | US | 60-160 | Major-7 | Smooth crooner / belted | Small combo (piano-bass-drums), brushed kit, intimate vocal mic | Romantic, sophisticated, intimate | H |
| Gypsy jazz / Manouche | 1934-present | France | 130-200 | Major, harmonic minor | Often instrumental; Romani when present | Two acoustic guitars + violin + upright bass, no kit | Romantic, virtuosic, swinging | H |
| Contemporary jazz | 1990-present | global | 80-160 | Modal, modern harmony | Often instrumental | Polished modern mix, electric/acoustic blend | Cerebral, polished, modern | H |

---

## 8. Folk / Country / Americana / Blues

The family weaves regional folk traditions, country's evolution (classic → outlaw → bro), blues (Delta → Chicago → contemporary), and the Americana umbrella reuniting them. Templates: `templates/folk.md` covers the indie/Americana lane.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Traditional folk | pre-1960; ongoing | UK/US | 70-120 | Modal (Dorian/Mixolydian) | Plain unaccompanied or duo harmony | Single mic, acoustic guitar / fiddle / banjo, room ambiance | Earnest, communal, ancient | H |
| Celtic folk | pre-1960; ongoing | Ireland/Scotland | 80-160 | Modal, Mixolydian | Plain melodic, often unaccompanied | Fiddle + tin whistle + bodhrán + accordion + acoustic guitar | Joyous, ancient, communal | H |
| Appalachian / old-time | 1900-1945; revival ongoing | US Appalachia | 100-150 | Modal, Mixolydian | High-lonesome harmony | Clawhammer banjo + fiddle + flat-top guitar | Plaintive, communal, ancient | H |
| Bluegrass | 1945-present | US Appalachia | 110-180 | Major, modal | High-lonesome tenor harmony | Five-string banjo + mandolin + fiddle + upright bass + flat-top guitar | Virtuosic, plaintive, driving | H |
| Newgrass / progressive bluegrass | 1972-present | US | 100-170 | Major, modal with jazz changes | High harmony | Bluegrass quintet + extended harmony + virtuoso solos | Virtuosic, modernist, fast | H |
| Country (classic / honky-tonk) | 1947-1965 | Nashville | 100-130 | Major (I-IV-V) | Twangy male/female nasal | Pedal steel + Telecaster + fiddle + walking bass + simple kit | Plain, melancholic, honest | H |
| Bakersfield country | 1956-1975 | California | 100-130 | Major | Twangy male | Telecaster twang + pedal steel + simple beat + dry mix | Working-class, plaintive | H |
| Outlaw country | 1972-1980 | Texas/Tennessee | 90-130 | Major | Weathered male baritone | Country band + rock attitude + dry analog mix | Rebellious, road-weary | H |
| Nashville pop country | 1989-2008 | Nashville | 100-130 | Major | Polished melodic | Pedal steel + acoustic + electric + bright modern mix | Sentimental, polished, radio | H |
| Bro country | 2010-2017 | Nashville | 100-130 | Major | Confident melodic male | Truck country + drum loops + hip-hop swing | Party, fratty, summer | H |
| Texas country / red dirt | 1990-present | Texas | 100-130 | Major | Weathered male | Roots band, dry analog, songwriter focus | Earthy, sincere, road-weary | H |
| Alt-country | 1990-present | US | 90-130 | Major, minor borrowings | Plaintive male/female | Country band with rock attitude, lo-fi-leaning | Wistful, literate, melancholy | H |
| Gothic country | 1995-present | US | 70-110 | Minor | Weathered baritone | Acoustic + minor-key arrangements + reverb-soaked | Brooding, dark, southern-gothic | M |
| Americana | 1998-present | US | 80-120 | Major, modal | Plaintive melodic | Acoustic-led ensemble, roots production | Reflective, autumnal, earnest | H |
| Country rock | 1968-1979 | California | 100-130 | Major | Plaintive harmony | Pedal steel + Telecaster + rock kit | Wistful, sunny, road-weary | H |
| Country pop | 1995-present | Nashville | 100-130 | Major | Polished melodic | Country instruments + pop production | Sentimental, polished, broad | H |
| Delta blues | 1925-1945 | Mississippi Delta | 70-110 | Blues scale, dominant-7 | Gravelly raw male | Solo acoustic slide guitar + voice, room mic | Haunting, raw, ancient | H |
| Chicago blues | 1948-1970 | Chicago | 90-130 | Blues scale, dominant-7 | Belted male, often gravelly | Electric guitar + harmonica + bass + simple kit, live-room | Urban, swaggering, electric | H |
| Texas blues | 1960-present | Texas | 90-130 | Blues scale, dominant-7 | Belted male | Stratocaster + Hammond optional + tight rhythm | Swaggering, soulful, hot | H |
| Electric blues | 1948-present | US | 90-130 | Blues scale | Belted male/female | Electric guitar + bass + drum kit, live ensemble | Swaggering, urban, hot | H |
| Country blues | 1925-present | US South | 70-110 | Blues scale | Plain plaintive male | Acoustic guitar (often picked), harmonica, sparse | Lonesome, rural, ancient | H |
| Indie folk | 2002-present | US/UK | 80-120 | Major, modal | Breathy conversational | Close-mic acoustic, brushed kit, room ambiance | Wistful, intimate, autumnal | H |
| Freak folk | 2002-2010 | US | 80-130 | Modal | Idiosyncratic, often falsetto | Acoustic + odd instruments (autoharp, banjo, glockenspiel) | Eccentric, naive, autumnal | H |
| Chamber folk | 2005-present | UK/US | 80-120 | Major, modal | Smooth melodic | Acoustic + string section + woodwinds | Literate, ornate, wistful | H |
| Anti-folk | 1986-present | NYC | 90-140 | Major, modal | Conversational, ironic | Lo-fi acoustic, simple band | Sardonic, intimate, urban | M |
| Folk punk | 1985-present | US/UK | 130-180 | Major, modal | Shouted melodic | Distorted acoustic + drum kit + accordion/banjo + bass | Rowdy, earnest, political | M |
| Sea shanty | pre-1900; revival 2021 | UK/Atlantic | 90-130 | Modal, major | Multi-tracked gang vocal | A cappella or fiddle/accordion accompaniment | Communal, hearty, rolling | H |

---

## 9. World / Regional

The largest geographically diverse family. Each region has multiple lineages — Latin (reggaeton/bachata/salsa lineage), Caribbean (reggae/dancehall lineage), African (afrobeats/amapiano), East Asian (K-pop/J-rock), South Asian (Bollywood/qawwali). Confidence skews lower for genres outside the Anglophone music-press canon.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Reggae (roots) | 1968-1980 | Jamaica | 60-90 | Major, dominant-7 | Patois melodic, often male | Offbeat skank guitar + bubbling organ + dub bass + one-drop kit | Spiritual, laid-back, righteous | H |
| Dub | 1973-present | Jamaica | 60-90 | Major, dominant-7 | Mostly instrumental; phrase echoes | Heavy effects (tape delay, reverb) on stripped reggae mix, drum-and-bass | Hypnotic, spacious, smoky | H |
| Rocksteady | 1966-1968 | Jamaica | 75-95 | Major | Smooth melodic | Slower ska feel, organ + electric guitar + bass | Romantic, slow-grooving | H |
| Ska (1st wave) | 1962-1966 | Jamaica | 130-170 | Major | Smooth melodic | Offbeat skank + horn section + Hammond organ | Joyous, danceable | H |
| Ska (2-tone / 2nd wave) | 1978-1984 | UK | 130-180 | Major | Shouted melodic | Punk-meets-ska, tight horns + upstroke guitar | Energetic, political, urgent | H |
| Ska (3rd wave) | 1993-2002 | US (SoCal) | 140-190 | Major | Punchy gang vocals | Hammond bubbles + horn section + upstroke guitar + punk kit | Energetic, party, hyperactive | H |
| Dancehall (classic) | 1985-1995 | Jamaica | 90-110 | Minor pentatonic | Patois toasting | Digital riddim (drum machine + synth bass), simple synth stabs | Rowdy, sexual, hard | H |
| Dancehall (modern) | 2010-present | Jamaica | 85-100 (half-time bounce) | Minor | Auto-Tuned patois | 808s, bhangra synths, rapid hi-hats, trap fusion | Energetic, club, rowdy | H |
| Reggaeton | 2002-present | Puerto Rico | 90-95 | Minor | Auto-Tuned Spanish melodic | Dembow riddim + perreo synth bass + reggaeton kick-snare | Sexy, club, melodic | H |
| Dembow (Dominican) | 1992-present | Dominican Republic | 110-120 | Minor | Rapid Spanish flows, call-response | Dembow drum pattern (kick-snare-kick) + güira scraper + congas | Frantic, party, street | M |
| Latin trap | 2015-present | Puerto Rico | 140-160 (half-time) | Minor | Auto-Tuned Spanish | 808 slides + triplet hi-hats + dark piano | Menacing, melodic, club | H |
| Bachata | 1962-present | Dominican Republic | 110-130 | Minor | Plaintive male tenor | Requinto guitar lead + nylon rhythm + bass + bongo + güira | Romantic, melancholy, dance | H |
| Salsa | 1962-present | NYC/Cuba | 150-200 | Minor 7th, mambo changes | Belted Spanish call-response | Piano montuno + brass section + congas + timbales + bongos | Hot, danceable, virtuosic | H |
| Merengue | 1850-present; modern 1960- | Dominican Republic | 130-160 | Major | Belted Spanish | Accordion + tambora + güira + saxophone | Energetic, party, communal | H |
| Cumbia | 1940-present | Colombia/Mexico | 80-100 | Minor | Plaintive Spanish | Accordion + bass + güira + drum kit | Romantic, melancholy, danceable | H |
| Bossa nova | 1958-1968 | Brazil | 120-140 | Major-7, jazz changes | Breathy Portuguese | Nylon-string guitar + upright bass + light brushed kit | Cool, sophisticated, romantic | H |
| Samba | 1920-present | Brazil | 90-120 | Major | Call-response | Surdo drums + tamborim + agogô bells + pandeiro + cavaquinho | Carnival, communal, joyous | H |
| MPB (Música Popular Brasileira) | 1965-present | Brazil | 100-140 | Major, modal | Expressive Portuguese | Acoustic guitar + light percussion + bossa-jazz fusion | Poetic, literate, mid-tempo | H |
| Pagode | 1980-present | Brazil | 95-130 | Major | Call-response | Cavaquinho + pandeiro + surdo + intimate vocal mic | Communal, party, romantic | M |
| Forró | 1940-present | Brazil (NE) | 110-140 | Major, modal | Plaintive | Accordion + zabumba (bass drum) + triangle | Communal, dance, rustic | M |
| Baile funk (funk carioca) | 1989-present | Rio de Janeiro | 120-150 | Minor | Portuguese MC + chops | Tamborzão break + 808 kicks + pitched bass + risers | Rowdy, sexy, party | H |
| Kuduro | 2000-present | Angola | 128-140 | Minor | Aggressive Angolan shouts | Heavy 808 kicks + synth stabs + compressed snare + electronic perc | Aggressive, party, frantic | M |
| Fado | 1820-present | Portugal | 60-90 | Minor | Anguished melodic | Portuguese guitar + classical guitar, intimate | Mournful, fatalistic, intimate | H |
| Flamenco | 1850-present | Andalusia | 90-180 | Phrygian dominant | Anguished melismatic | Nylon guitar + cajón + palmas (handclaps) + voice | Passionate, anguished, communal | H |
| Rai | 1970-present | Algeria | 90-130 | Modal | Plaintive Arabic | Synth + accordion + darbouka + bass | Mournful, romantic, urban | M |
| Qawwali | 800s-present | South Asia | 90-160 | Modal, raga-based | Devotional male, ecstatic harmony | Harmonium + tabla + handclap ensemble | Devotional, ecstatic, ancient | H |
| Bollywood / filmi | 1940-present | India | 90-160 | Modal, raga + Western fusion | Multi-tracked melismatic | Sitar + tabla + Western strings + brass + modern pop production | Romantic, dramatic, dance | H |
| Bhangra | 1980-present | Punjab/UK | 130-160 | Modal | Belted Punjabi | Dhol drum + tumbi + alghoza + modern electronic | Energetic, party, communal | H |
| Indian classical (Hindustani) | 1500s-present | North India | n/a (alap to fast) | Raga-based | Melismatic devotional | Sitar / sarod + tabla + tanpura drone | Meditative, raga-specific moods | H |
| Indian classical (Carnatic) | 1500s-present | South India | n/a | Raga-based | Melismatic devotional | Veena + mridangam + violin + tanpura | Meditative, raga-specific | H |
| Gamelan | 800s-present | Indonesia | n/a (cyclic) | Pelog/slendro tunings | Often instrumental; chant when present | Bronze gongs + metallophones + drums + bamboo flute | Trance-like, ritual, cyclic | H |
| Klezmer | 1850-present | Eastern Europe | 100-180 | Modal (Freygish/Mi Sheberach) | Melismatic when present | Clarinet + violin + accordion + upright bass | Mournful-joyous, communal, dance | H |
| Afrobeats (modern) | 2010-present | Nigeria/Ghana/UK | 100-120 | Major, modal | Auto-Tune-tinged melodic | Log drum + 808 slides + highlife guitar + synth horns + congas | Bouncy, romantic, party | H |
| Afrobeat (Fela-era) | 1968-1980 | Lagos | 110-130 | Modal, vamps | Yoruba/English call-response | Talking drum + shekere + horn section + choppy guitar + congas | Hypnotic, political, communal | H |
| Highlife | 1955-1975 | Ghana/Nigeria | 100-120 | Major | High melodic local-language | Highlife guitar + palmwine guitar + brass + ogene bell + congas | Swinging, romantic, communal | H |
| Soukous | 1970-1995 | Congo (DRC) | 100-130 | Major | Lingala melodic, runs | Interlocking sebene guitars + balafon + ngoma drums + brass | Joyous, virtuosic, dance | H |
| Mbalax | 1980-present | Senegal | 100-120 | Modal | Wolof griot call-response | Sabar/tama talking drums + synth bass + griot guitar | Frenetic, percussive, communal | M |
| Juju | 1960-1985 | Nigeria (Yoruba) | 120-140 | Modal | Yoruba call-response | Talking guitar + ogidigbo bass + shekere + accordion | Hypnotic, proverbial, communal | M |
| Kwaito | 1995-2005 | South Africa | 120-130 | Modal | Spoken/rapped township slang | Deep sub bass + swung kicks + simple stabs + vocal chops | Laid-back, party, township | M |
| Gqom | 2010-present | Durban, SA | 120-130 | Minor monotonic | Repetitive Zulu chants | Distorted bass synth + constant kicks (no 4-on-floor) + triplet perc | Dark, raw, minimal | M |
| Amapiano | 2014-present | South Africa | 110-115 | Major-7, jazz changes | Sung/chanted Zulu/Xhosa | Log drum (woody bass) + Rhodes/synth pads + shaker perc + soft 4-on-floor | Laid-back, jazzy, communal | H |
| - *Signature instrumentation:* Log drum (woody percussive sub-bass) + Rhodes/warm pad with jazz 7ths/9ths + shaker-heavy percussion + soft four-on-the-floor kick. *Differentiator:* Log drum + jazz piano voicings + slower BPM than house — the log drum is the genre-defining sound. |
| K-pop | 1996-present | South Korea | 90-128 | Major, EDM/R&B fusion | Multi-vocal-style group | Hyper-polished, multi-genre verse-chorus structure | Slick, choreographic, dramatic | H |
| J-pop | 1990-present | Japan | 110-140 | Major, melodic-minor borrowings | Bright clean female | Ornate arrangements, anime-friendly | Bright, sentimental | H |
| J-rock | 1985-present | Japan | 130-180 | Minor, modal | Anguished tenor | Distorted guitars + symphonic/electronic blend | Dramatic, anguished, anthemic | H |
| Visual kei | 1985-present | Japan | 130-180 | Minor, harmonic minor | Theatrical anguished | Heavy guitars + symphonic synths + theatrical aesthetic | Theatrical, dramatic | M |
| Mandopop (C-pop) | 1980-present | Greater China | 80-128 | Major, modal | Smooth Mandarin melodic | Polished pop production with Chinese instrument accents | Romantic, smooth, sentimental | H |
| City pop (Japan) | 1979-1986 | Japan | 95-125 | Major-7 jazz changes | Smooth Japanese melodic | Fusion-jazz Rhodes + slap bass + sax + glossy mix | Cosmopolitan, romantic | H |
| Anime OST | 1980-present | Japan | varies | Major/minor, broad range | Multi-style depending on scene | Orchestral + J-pop + rock + EDM, scene-driven | Dramatic, sentimental | H |

---

## 10. Classical / Cinematic

Eras of Western classical music (Baroque → Romantic → Modern) plus the contemporary cinematic/film/game lineage. Specifying the era + named composer's "style" gives Suno strong direction.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Baroque | 1600-1750 | Europe | 60-160 | Tonal, ornate, polyphonic | Operatic / vocal ensemble when present | Harpsichord + chamber strings + recorder + cello continuo | Ornate, contrapuntal, dignified | H |
| Classical era | 1750-1820 | Vienna/Europe | 60-160 | Tonal (major/minor) | Operatic when present | Symphony orchestra (pre-Romantic forces), piano forte, no large brass | Balanced, elegant, expressive | H |
| Romantic | 1820-1900 | Europe | 40-180 | Tonal with chromatic expansion | Operatic when present | Full symphony orchestra, expanded brass, piano | Passionate, dramatic, sweeping | H |
| Late Romantic / Post-Romantic | 1890-1920 | Europe | 40-180 | Heavily chromatic | Operatic when present | Huge orchestra (Mahler/Strauss forces) | Heroic, anguished, expansive | H |
| Impressionist | 1875-1920 | France | 50-130 | Whole-tone, modal | Operatic when present | Orchestra with emphasis on color, woodwinds, harp | Hazy, painterly, atmospheric | H |
| Modern classical | 1900-1975 | Europe/US | varies | Atonal, serial, modal | Operatic, Sprechstimme | Orchestra or chamber, extended techniques | Dissonant, cerebral, experimental | H |
| Minimalist | 1965-present | US | 80-180 | Tonal, modal, repetitive | Often instrumental; chanted when present | Repeating cells, pulsing rhythm, marimba/piano/strings | Hypnotic, meditative, cyclic | H |
| Contemporary classical | 1975-present | global | varies | Tonal/atonal mix | Various | Mixed acoustic/electronic | Cerebral, varied | H |
| Neoclassical (piano-led contemporary) | 2000-present | UK/Iceland | 50-100 | Major/minor, modal | Often instrumental | Solo piano + string section + light electronics | Wistful, melancholic, intimate | H |
| Film score / orchestral cinematic | 1930-present | Hollywood/global | varies | Tonal, modal, leitmotif-driven | Often instrumental; choral when present | Full orchestra + choir + hybrid electronics | Cinematic, dramatic, narrative | H |
| Trailer music | 1995-present | LA | 90-140 | Minor | Often instrumental; "epic" choir | Big drums + brass swells + string ostinati + risers | Epic, urgent, dramatic | H |
| Video game music | 1985-present | global | varies | Tonal | Often instrumental | Genre-spanning (orchestral / chiptune / synth) | Adventurous, looping, leitmotif-driven | H |
| Chamber music | 1750-present | Europe | varies | Tonal | When present, intimate | String quartet / piano trio / wind quintet | Intimate, conversational | H |
| Choral / Sacred | 800-present | Europe | 40-130 | Modal, tonal | Choir-led | Choir + organ ± orchestra | Devotional, transcendent | H |
| Opera | 1600-present | Italy/Europe | varies | Tonal | Operatic ranges, recitative + aria | Full orchestra + soloists + chorus | Dramatic, theatrical | H |
| Lieder / art song | 1810-1925 | Germany/Austria | varies | Tonal | Operatic with chamber phrasing | Piano + voice | Intimate, literate, lyrical | H |
| Solo piano (contemporary) | 1980-present | global | varies | Tonal, modal | Instrumental | Solo grand piano, close-mic | Meditative, contemplative | H |
| Modern minimalism (Ludovico/Einaudi style) | 2000-present | EU | 60-100 | Major/minor | Often instrumental | Piano + string section, simple repeating patterns | Wistful, cinematic, contemplative | H |

---

## 11. Ambient / Experimental

Genres organized around texture and atmosphere rather than song-form. Tempo is often arrhythmic or implicit. Confidence is HIGH for canonical ambient lineage (Eno, Aphex, Stars of the Lid) and MEDIUM for hyper-niche internet subgenres (mallsoft, lowercase) where the canon is small and recent.

| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Ambient | 1978-present | UK | n/a or 60-90 | Modal, drone | Often none; wordless pads when present | Synth pads + tape delay + sparse instruments | Meditative, spacious, calming | H |
| Drone | 1965-present | US/UK | n/a | Drone | Often none | Single sustained note/cluster with overtone evolution | Hypnotic, immersive, oppressive | H |
| Dark ambient | 1989-present | global | n/a or 40-70 | Drone, minor | Distant wordless | Distorted drones + field recordings + dissonant pads | Oppressive, oneiric, dread | H |
| Space ambient | 1976-present | UK/Germany | n/a | Modal | Often none | Spacious synth pads + occasional cosmic effects | Vast, cosmic, weightless | H |
| Ambient pop | 1992-present | UK/US | 80-110 | Major | Whispered/breathy melodic | Reverb-soaked pads + light kit + dream-pop guitars | Hazy, romantic, melancholic | H |
| Ambient techno | 1992-present | UK/Germany | 110-130 | Modal | Often instrumental | Soft pads + minimal 4/4 + dub space | Hypnotic, late-night, expansive | H |
| Drone metal | 1991-present | US Pacific NW | 30-50 or arrhythmic | Drone, modal | Buried chants when present | Sustained guitar feedback + single-chord epics | Hypnotic, oppressive, ritual | M |
| Lowercase | 1995-present | US/Japan | n/a | Modal | None | Near-silent textures + field recordings + granular synthesis | Anti-maximalist, immersive, quiet | M |
| Noise | 1979-present | Japan/US | n/a | Atonal | Distorted screams when present | Layered noise generators + feedback + electronics | Brutal, cathartic, abrasive | H |
| Harsh noise / HNW | 1985-present | global | n/a | Atonal | Rarely | Wall of distorted noise, single texture | Brutal, oppressive, meditative | H |
| Glitch | 1995-present | global | varies | Modal, atonal | Mostly instrumental | Granular synthesis + clicks/cuts/pops | Cerebral, broken, textural | H |
| Plunderphonics | 1985-present | global | varies | varies | Sampled | Heavily edited sample collage | Cerebral, ironic, deconstructive | H |
| Vaporwave | 2011-2016; ongoing | online | 70-100 | Major-7 jazz | Pitched-down samples | Slowed 80s samples + infinite reverb + VHS warble | Hypnagogic, hauntological | H |
| Mallsoft | 2014-present | online | 60-90 | Major-7 | Distant/none | Sampled muzak + mall field recordings + endless reverb | Liminal, nostalgic, lonely | M |
| Plunderphonic vaporwave | 2012-present | online | varies | varies | Sampled distorted | Heavily mangled 80s/90s pop samples | Hauntological, ironic | M |
| Dungeon synth | 1994-present; revival 2017- | Norway/online | 60-100 | Modal, minor | Wordless chants when present | Korg M1 / DX7 emulating harps, flutes, organ, choir | Medieval, fantastical, melancholy | M |
| Witch house | 2008-2013 | US | 110-130 | Minor | Pitched-down distorted | Chopped 808s + occult samples + drag aesthetics | Occult, goth, narcotic | M |
| Hauntology | 2005-present | UK | varies | Modal | Distant when present | Sampled 60s-70s library music + tape decay + vinyl crackle | Hauntological, nostalgic | M |
| Slowcore | 1989-present | US | 50-80 | Major/minor | Whispered/exposed | Minimal indie-rock instrumentation, very slow, dry mix | Melancholic, exposed, contemplative | H |
| Kosmische / krautrock ambient | 1969-1977 | Germany | 70-110 | Modal, drone | Often instrumental | Analog synths + motorik or no rhythm + tape delay | Transcendent, mechanical, vast | H |

---

## 12. Niche / Modern / Internet-era

Genres that emerged primarily through SoundCloud, TikTok, YouTube, and Discord communities, often with rapid cycles and shared producer vocabularies. Confidence skews MEDIUM — communities are recent and definitions still shift.

<!-- chord/vocal-production vocabulary in table trips the spell-checker --><!-- spellchecker:off -->
| Genre | Era | Region | BPM | Key | Vocal | Production | Mood | Conf |
|-------|-----|--------|-----|-----|-------|------------|------|------|
| Hyperpop | 2018-present | online (PC Music descendants) | 135-180 | Major, often pitched up | Heavy Auto-Tune fast-retune, chipmunk formant +5-7 semitones | Distorted 808s + bitcrushed hi-hats + OTT compression + glitch chops | Chaotic, maximalist, ironic | H |
| Glitchcore | 2019-present | online (TikTok/SoundCloud) | 120-220 | Major, often pitched | Extreme Auto-Tune, pitch-shifted emo-rap | Micro-chopped Amen breakbeats + bitcrushing + stutter edits | Hyperactive, glitchy, fragmentary | M |
| Digicore | 2020-present | online | 140-180 | Major-tinged | Auto-Tuned rap-sung, layered harmonies | Plucked Serum bells + 808 slides + rapid hi-hats + glitch pads | Dreamy, melodic, viral | M |
| HexD | 2022-present | online | 130-160 | Minor | Aggressive Auto-Tune, rage screams | Hexed/wobbly 808s + rattling hi-hats + half-time switches | Dark, aggressive, mosh | L |
| Plugg | 2016-present | online (SoundCloud) | 130-150 (half-time) | Major-tinged | Auto-Tuned dreamy | Plucked synths + sub-808 + soft kicks + reverb-heavy mix | Wavy, dreamy, melancholy | M |
| Pluggnb | 2019-present | online | 130-150 (half-time) | Major-7 | Auto-Tuned smooth | Plugg drums + R&B chord pads | Dreamy, romantic, melancholic | M |
| Rage rap | 2020-present | online | 140-160 | Minor | Screamed Auto-Tune hype | Distorted 808s + Jersey-club kicks + fast hi-hats + piano riffs | Mosh-pit, chaotic, anthemic | M |
| Nightcore | 2002-present | YouTube/global | 140-200+ (sped from original) | Major | Pitch-shifted up 4-8 semitones (chipmunk) | Sped-up source material, minimal new production | Cute, hyper, kawaii | H |
| Slowed and reverb / slowed + reverb | 2019-present | TikTok | 60-100 (slowed from original) | Original | Pitch-shifted down 4-8 semitones | Slowed source + massive hall reverb + low-fi haze | Dreamy, dissociative, narcotic | H |
| Sped up | 2022-present | TikTok | 130-170 (sped from original) | Original | Pitch-shifted up 2-4 semitones | Tempo+pitch shift, source preserved | Hyperactive, addictive, meme | M |
| Phonk (Memphis OG) | 1991-2000 | Memphis | 60-90 (half-time) | Minor | Chopped-and-screwed pitched-down | Cowbell + TR-808 + lo-fi tape + screwed vocals | Hypnotic, eerie, narcotic | H |
| Drift phonk | 2020-present | Russia/online | 130-160 | Minor | Pitched/distorted ad-libs (Japanese chops common) | Cowbell + aggressive 808 + saw bass + speedy hi-hats | High-energy, aggressive, vehicular | M |
| Brazilian phonk | 2022-present | Brazil | 130-150 | Minor | Pitched chops | Phonk drums + tamborzão swing | Aggressive, hyperactive | M |
| Vaporwave | 2011-2016; ongoing | online | 70-100 | Major-7 jazz | Pitched-down 80s samples | Slowed city-pop + infinite reverb + VHS warble + bitcrushing | Hypnagogic, hauntological | H |
| Future funk | 2014-present | online | 100-120 | Major-7 jazz | Pitched samples from city-pop | Boogie bass + chopped breaks + funky guitar | Sunny, danceable, ironic | H |
| Mallsoft | 2014-present | online | 60-90 | Major-7 | Whispered/none | Sampled muzak + mall field recordings + endless reverb | Liminal, lonely, hauntological | M |
| Vapor-soul / vapor R&B | 2015-present | online | 70-100 | Minor 7th | Pitched-down soul samples | Sampled 80s-90s soul + Rhodes + warm pads + vinyl crackle | Smooth, melancholic, intimate | L |
| Trapwave | 2017-present | online | 130-160 (half-time) | Minor | Pitched chops | Trap drums + vaporwave samples + 80s synths | Dreamy, melancholic, ironic | L |
| Ballroom (vogue) | 1989-present | NYC (queer) | 128-135 | Modal | Spoken/chanted house calls | "Ha" crash + electro/house base + vogue beat | Theatrical, queer, ferocious | M |
| Jersey club | 2010-present | New Jersey | 130-140 | Minor | Pitched/chopped samples | Jersey-clap (rapid layered claps) + 808 kicks + bed-squeak | Hyper, club, sexy | M |
| Baltimore club | 2000-2008 | Baltimore | 130 | Minor | Chopped rap chants | Think Break / Sing Sing loops + horn stabs + 909 kicks | Rowdy, party | M |
| Footwork | 2005-present | Chicago | 160-170 | Minor pentatonic | Pitched-up vocal stutters | Off-beat 808 kicks + metallic claps + hi-hat flurries + vocal chops | Frantic, dance-battle | H |
| Juke | 2000-present | Chicago | 130-160 | Minor | Hyped pitched | 808 kicks + rolling hi-hats + bass wobbles + vocal chops | Hyped, club, sexual | M |
| Slap house / Brazilian bass | 2017-present | Brazil/EU | 125-128 | Minor | Pitched vocal hooks | Slapping wobble bass + OTT compression + big drops | Festival, aggressive | M |
| Chillwave | 2009-2014 | online | 90-120 | Major | Hazy reverb-buried | Synth pads + drum machine + tape warble | Hazy, nostalgic, summer | H |
| Vapor-trap / SoundCloud rap | 2014-present | online | 130-150 (half-time) | Minor | Auto-Tuned mumble | Trap drums + cloud-rap pads | Hazy, melancholy, dreamy | M |
<!-- spellchecker:on -->

---

## Bonus 1: Fusion patterns

Common AI-music fusion shorthand and how the blend typically works. Suno responds well when one parent is dominant (~60% of descriptor weight) and the other supplies texture or context.

| Fusion | Dominant parent | Supplied by secondary | Suno descriptor sketch |
|---|---|---|---|
| **Synthwave country** | Synthwave (analog supersaws + gated reverb + 80s feel) | Country (pedal steel lead, twangy male vocal, dry mix) | `synthwave-country, analog supersaw pads, pedal steel lead, gated reverb snare, weathered male vocal, 108 BPM, neon-cinematic` |
| **Country trap** | Trap (808 slides, triplet hi-hats, half-time feel) | Country (acoustic strums, twangy vocal, banjo lead) | `country trap, 808 slides + triplet hi-hats, acoustic guitar strums, banjo lead, drawled male vocal with auto-tune, 75 BPM half-time` |
| **Alt-R&B (PBR&B)** | Contemporary R&B vocal phrasing | Dark synth ambient, sparse trap drums | `alt-R&B, falsetto layered vocal, dark synth pads, sparse trap drums, 72 BPM, late-night reverb-drenched mix` |
| **Jazz rap** | Boom-bap rhythm (~88-95 BPM, dusty kick-snare) | Jazz harmony (Rhodes, upright bass, brushed kit, jazz samples) | `jazz rap, dusty boom-bap drums, sampled Rhodes and upright bass, conversational lyrical flow, 90 BPM, vinyl crackle, jazz-7th chords` |
| **Dream-pop synth-pop** | Dream pop (chorused guitars, breathy vocal, hazy reverb) | Synth-pop (analog synths, drum machine kit) | `dreampop-synthpop, chorused Telecaster + analog supersaw pads, drum machine kit, breathy female vocal with reverb tail, 110 BPM, hazy 80s warmth` |
| **Trap soul** | Trap drums (808 slides + half-time hi-hats) | R&B vocal phrasing + chord pads | `trap soul, 808 slides + rolling hi-hats, R&B chord pads, smooth auto-tuned falsetto, 140 BPM half-time, sensual reverb` |
| **Indie folk + post-rock** | Indie folk (fingerpicked acoustic, breathy vocal) | Post-rock (slow build, glassy delay guitars, real drum crescendo) | `indie folk post-rock, fingerpicked acoustic intro building to delay-soaked electric guitars and crashing real drums, 85 BPM, cinematic crescendo` |
| **Blackgaze** | Black metal (tremolo-picked guitars, shrieks, blast drums) | Shoegaze (wall-of-sound reverb, melodic leads) | `blackgaze, tremolo-picked harmonized guitars with My Bloody Valentine reverb wall, shrieked vocals transitioning to clean melodic, double-kick, 140 BPM` |
| **Future bass + R&B** | Future bass drops (chord stabs, supersaw, half-time trap) | R&B vocal phrasing + chord pads | `future bass R&B, chopped vocal samples + supersaw chord stabs, half-time trap drums, melodic R&B sung verses, 150 BPM` |
| **Trap metal / rage metal** | Trap drums + 808s | Metal (down-tuned distorted guitars, screamed vocal) | `trap metal, distorted 808 kicks + drop-tuned palm-muted guitars + screamed-and-rapped vocal, 75 BPM half-time, brutal compressed mix` |
| **Amapiano-afrobeats** | Amapiano (log drum + jazz piano + slower tempo) | Afrobeats (highlife guitar, melodic Auto-Tune vocal) | `amapiano-afrobeats, log drum bassline + Rhodes jazz chords + shaker percussion, melodic auto-tuned afrobeats vocal, 112 BPM, laid-back warm mix` |
| **Synth-pop boom-bap** | Synth-pop (LinnDrum, DX7, analog warmth) | Boom-bap (sample-chop swing, dusty drums) | `synth-pop boom-bap, LinnDrum + DX7 FM bass + DX7 chord stabs, sampled vocal chops with swing, 92 BPM, dusty analog mix` |
| **Cinematic trap** | Trap drums | Orchestral cinematic (strings, brass, choir, big builds) | `cinematic trap, 808 slides + half-time hi-hats, dark orchestral strings, low brass swells, choir pads, 75 BPM, blockbuster mix` |
| **Lo-fi jazz** | Jazz harmony (modal, 7th chords, brushed kit) | Lo-fi hip-hop production (vinyl crackle, tape warble) | `lo-fi jazz, sampled jazz piano + brushed kit + upright bass, vinyl crackle, tape warble, 80 BPM, study-friendly hazy mix` |
| **Dembow trap** | Reggaeton/dembow rhythm | Trap drums + 808s | `dembow trap, dembow kick-snare + 808 slides + güira scraper, Spanish auto-tuned melodic, 95 BPM` |

---

## Bonus 2: Vibe → genre mapping

For each mood/vibe, 3-5 fitting genres ordered by descriptor density (first = most reliable Suno match).

| Vibe | Genre suggestions (most-reliable first) |
|---|---|
| **Dark / melancholic** | dark ambient, blackgaze, gothic country, post-punk, alt-R&B (PBR&B), doom metal, witch house |
| **Euphoric** | uplifting trance, future bass, big-room house, gospel, disco, K-pop, power metal |
| **Aggressive** | thrash metal, hardcore punk, deathcore, UK drill, hardstyle, grindcore, rage rap, brostep |
| **Intimate** | bedroom pop, neo-soul, indie folk, slowcore, vocal jazz, lo-fi hip-hop, neoclassical piano |
| **Nostalgic** | synth-pop, city pop, vaporwave, dream pop, synthwave, chillwave, boom bap |
| **Dreamy** | dream pop, shoegaze, dream pop, future bass, plugg, ambient pop, cloud rap |
| **Dystopian** | industrial techno, dark ambient, witch house, post-punk, glitchcore, Berlin techno |
| **Romantic** | bossa nova, bachata, quiet storm, neo-soul, classic soul, K-pop ballad, baroque pop |
| **Triumphant** | power metal, trailer music, gospel, symphonic metal, anthemic pop rock, uplifting trance |
| **Contemplative** | neoclassical piano, ambient, slowcore, modal jazz, minimalist classical, post-rock |
| **Eerie** | dark ambient, witch house, dungeon synth, horrorcore, atmospheric black metal, drone metal |
| **Hopeful** | indie folk, gospel, synth-pop, indie pop, heartland rock, contemporary classical |
| **Cathartic** | post-hardcore, emo, metalcore, post-rock crescendos, gospel, grunge |
| **Gritty** | Delta blues, garage rock, sludge metal, hardcore punk, Chicago drill, outlaw country |
| **Polished** | dance-pop, K-pop, smooth jazz, contemporary R&B, Nashville country pop, electropop |
| **Hypnotic / trance-like** | psytrance, Berlin techno, drone metal, krautrock, dub, gamelan, footwork |
| **Festive / party** | reggaeton, baile funk, ska 3rd wave, salsa, big-room house, bro country, dancehall |
| **Cosmic / vast** | space ambient, post-rock, kosmische, drone, atmospheric black metal, ambient techno |
| **Cinematic / narrative** | film score orchestral, trailer music, post-rock, cinematic trap, neoclassical, synthwave |
| **Sexy / sensual** | trap soul, alt-R&B, quiet storm, bossa nova, dancehall, future bass + R&B fusion |
| **Hyperactive / chaotic** | hyperpop, glitchcore, breakcore, footwork, speedcore, drift phonk, rage rap |
| **Spiritual / devotional** | gospel, qawwali, spiritual jazz, choral sacred, Indian classical, dungeon synth |

---

## Cross-reference

- Templates with prompt skeletons + tweak knobs: `templates/{pop,rock,hip-hop,trap,edm,jazz,classical,folk,metal,ambient,lofi,rnb}.md`
- 6-layer formula and confidence policy: parent `../SKILL.md` "Load-bearing fundamentals"
- Style-prompt construction details: `context/style.md`
- Live research recipes for niche genres: `context/research-recipes.md`
