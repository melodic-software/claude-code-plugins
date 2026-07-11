# AI Tools — Supplements to Internal Rhyme Generation

The model's internal phonetic vocabulary is the **primary** rhyme generation
tool. It covers common words, proper nouns, pop culture, regional /
dialectal words, era-specific vocabulary, brand names, and — most
importantly — vocabulary from the song's developed world. A generic rhyming
dictionary misses most of that. See `rhyme-generation.md` for the internal
discipline.

This file documents EXTERNAL tools that supplement internal generation when
specific limits are hit. They do not replace Pat's craft application; they
plug specific gaps.

## When external data actually helps

| Need | Internal handles? | External helps |
|---|---|---|
| Common-word rhymes | YES | rarely needed |
| Proper noun / pop culture / setting-specific rhymes | YES — model's strongest territory | Datamuse weak here |
| Phonetic family classification | YES — Pat's taxonomy is in the model | n/a |
| Stability tier assignment | YES | n/a |
| Identity vs rhyme check | YES — once applied | n/a |
| Cliche detection | YES | n/a |
| Vowel triangle / diphthong decomposition | YES — Pat's framework is internal | n/a |
| HIGH volume (50+) brainstorm candidates | PARTIAL | YES — Datamuse for breadth |
| Syllable count on rare polysyllabic words | UNRELIABLE | YES — Datamuse `syllables` |
| Verifying word actually exists / current usage | UNRELIABLE | YES — Datamuse |
| Statistical semantic field for metaphor | INTUITIVE only | YES — Datamuse `trg` |
| Stress pattern detection on rare words | UNRELIABLE | YES — pronouncing library |

**Rule:** use the internal discipline (per `rhyme-generation.md`) FIRST.
External tools come in to verify, expand, or fill specific gaps.

## Datamuse — vocabulary breadth + verification

`scripts/datamuse.sh` is a bash + curl + jq wrapper around
<https://api.datamuse.com/words>. Free, no auth, no key.

**Where Datamuse shines:**

- 100K+ candidate vocabulary breadth
- Statistical semantic associations (`rel_trg`) — broader than model's tight
  semantic neighborhoods
- `numSyllables` returned per word — exact, not estimated
- Sound-pattern search (`sp=t???t`) for letter-pattern constraints

**Where Datamuse fails:**

- Proper nouns and brand names (limited)
- Pop culture references (limited)
- Setting / era / regional vocabulary (limited)
- Slang and informal registers
- Contextual fit (no awareness of the song)

The model's strengths and Datamuse's strengths are complementary.

### Modes

| Mode | Param | Use |
|---|---|---|
| `rhyme` | `rel_rhy` | perfect-rhyme breadth — verify model's candidates + add uncommon ones |
| `near` | `rel_nry` | near-rhyme breadth |
| `cons` | `rel_cns` | consonance candidates |
| `family` | merged near + cons | one-shot family rhyme breadth |
| `syn` | `rel_syn` | synonyms |
| `ant` | `rel_ant` | antonyms |
| `trg` | `rel_trg` | semantic-field triggers — primary metaphor-mining tool |
| `jja` | `rel_jja` | adjectives describing a noun |
| `jjb` | `rel_jjb` | nouns described by an adj |
| `means` | `ml` | reverse dictionary |
| `sounds` | `sl` | sounds-like |
| `pattern` | `sp` | letter pattern |
| `syllables` | `sp` + `md=s` | exact syllable count |

### Invocation

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pat-pattison/scripts/datamuse.sh" <mode> <word>
LIMIT=50 bash "${CLAUDE_PLUGIN_ROOT}/skills/pat-pattison/scripts/datamuse.sh" near grief
```

Output is TSV: `word\tscore\tnumSyllables\ttags`. Higher score = stronger match.

### Worked example — supplementing internal generation

User: "find rhymes for *stranger* that fit a 1970s Tennessee bar setting."

Internal pass first:

1. Apply `rhyme-generation.md` Steps 1-6 against the model's vocabulary
2. Surface 8-15 candidates per tier (perfect / family / assonance / consonance)
3. Pull setting-specific candidates from the song's world (jukebox words, era brand names, regional terms, character names)

Then Datamuse pass for breadth:

1. `datamuse.sh family stranger` → 25 candidates
2. Identity check on each
3. Cross-check against setting fit
4. Merge with internal list, label tier + setting fit

Datamuse adds breadth; the model applies craft. Both passes matter.

### Worked example — metaphor source mining

User: "give me metaphor sources for grief."

Datamuse `rel_trg` shines here. The model's semantic associations for
"grief" are tight (sadness, loss, mourning); `rel_trg` returns statistical
co-occurrences (winter, weight, river, ash, hollow) — broader, more
metaphor-ready.

```bash
datamuse.sh trg grief | head -20
datamuse.sh jja grief | head -20    # adjectives for grief (heavy, raw, old)
datamuse.sh jjb heavy | head -20    # nouns described by "heavy" (load, silence, hand)
```

Feed candidates into Pat's metaphor recipes (`metaphor.md`).

## pronouncing — syllable + stress (Python, optional)

For higher-fidelity stress / syllable work, the `pronouncing` Python library
wraps CMUdict (127K words, ARPAbet phonetic transcription with stress
digits 0/1/2):

```bash
pip install pronouncing
```

```python
import pronouncing
phones   = pronouncing.phones_for_word("disappointment")
syl      = pronouncing.syllable_count(phones[0])      # 4
stresses = pronouncing.stresses(phones[0])            # e.g., "20010"
# Find iambic words: pronouncing.search_stresses("^01$")
```

CMUdict misses neologisms, proper nouns, and slang. For those, `pyphen`
provides a typographic-hyphenation fallback (`pip install pyphen`).

The skill does NOT require the user to install pronouncing — Datamuse's
`numSyllables` covers routine needs. Pronouncing is the upgrade path for
stress-pattern work.

## Genius API — exemplar analysis (optional)

For lyric-exemplar study (NOT reproduction): <https://docs.genius.com>.
Requires free account + access token. Annotations data is ToS-compliant;
lyrics scraping is not. Use Genius for community annotation insights, not
for lyric reproduction.

## The skill's combined discipline

For rhyme requests, the model:

1. **Generate internally** via `rhyme-generation.md` discipline — primary
2. **Apply Pat's framing** to every candidate (identity check, stability
   tier, cliche risk, world fit)
3. **Supplement via Datamuse** when:
   - The writer wants 30+ candidates
   - The model is uncertain about a polysyllabic word's syllable count
   - The writer is metaphor-mining (semantic field)
   - The writer asks for explicit external verification
4. **Surface labeled lists** of 8-15 candidates per tier, not single answers

For syllable / stress on rare words: verify via Datamuse `syllables` or
pronouncing library. Do not guess.

## What this file does NOT do

- It does not assert that Datamuse is the primary rhyme tool. It isn't.
  The model's internal vocabulary plus Pat's framework is primary.
- It does not replace `rhyme-generation.md` — that file is the internal
  discipline; this file is supplements only.
- It does not enforce stability choice — that is the writer's emotional
  decision per `rhyme-strategy.md`.

## Recheck triggers

- Datamuse API endpoint deprecated → update `scripts/datamuse.sh`
- A purpose-built songwriting MCP appears in registries → re-evaluate
- pronouncing replaced by a model-shipped phoneme tool → drop the Python path
- Model gains reliable syllable / stress on rare polysyllabic words → drop pronouncing
