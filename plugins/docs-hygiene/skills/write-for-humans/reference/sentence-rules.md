# Sentence rules — address, load, and ambiguity

The three sentence-level layers of the default set, in one file because they apply to every sentence
at once. Splitting them by standard would make you open three files per sentence.

Read this while drafting. It is the fallback set — when the consuming project declares its own style
guide, that guide replaces everything here, and the skill body says so before you get this far.

## Address — how the sentence talks to the reader

Paraphrased from the Google developer documentation style guide.

- Talk to the reader as "you", in the present tense. Use "will" only for something that genuinely
  happens later.
- Say who does what: "the compiler checks", not "is checked". Passive is fine only when the actor is
  unknown or beside the point.
- Write instructions as commands: "Click Submit." State facts plainly, never "should be done".
- Put the condition before the instruction: "To delete the document, click Delete." The reader skips
  what does not apply to them.
- Put the common case first. Exceptions after.
- Sound like a knowledgeable friend. No buzzwords, no figurative language, no "please" in
  instructions, and never "simply", "easy", or "quickly" in a procedure — if it were simple the
  reader would not be here.
- Do not pre-announce ("we will soon support…"), and do not start consecutive sentences with the
  same phrase.
- Read the awkward sentence aloud. If it stays awkward, rewrite it.
- Link with words that say where the link goes — the page title or a short description, never
  "click here". A sentence of context on the page beats a link off it.
- Headings carry the point, not just the topic ("Pick the mode first", not "Modes"). Sentence case.
  A task heading is a bare verb phrase; a concept heading is a noun phrase. One h1 per page, no
  skipped levels.
- Numbered lists for sequences, bullets for everything else. Introduce a list with a complete
  sentence. Keep the items parallel.
- Code goes in code font, UI elements in bold. Use serial commas. Drop "etc." and say up front when
  a list is partial.

## Load — how much one sentence carries

Paraphrased from ASD-STE100 Simplified Technical English. The numbered rules and the controlled
dictionary live in the specification itself; these are the transferable principles, which is why
this file is a paraphrase and never a substitute for the spec.

- One instruction per sentence. One thought per sentence everywhere else.
- Split instructions longer than about 20 words, and other sentences longer than about 25.
- Put the warning or condition before the step it guards: "If hot oil touches your skin, injuries
  can occur."
- Keep "the" and "a". "Remove backup file" reads two ways; "Remove the backup file" reads one.
- Give each word one meaning and one job, then keep it. If "check" means inspect, do not also use it
  for restrain.
- Pick one word per action and stick to it: "start", not "start" here and "initiate" there.
- Write procedures as direct commands, never as narration and never in the passive: "Install the
  component", not "the component must be installed".
- Avoid "-ing" words where you can. They take too many grammatical jobs and breed misreadings.

## Ambiguity — can this be read two ways?

Paraphrased from Kohl, *The Global English Style Guide*. The audience these rules protect is the
non-native reader, the translator, and the agent, all of whom parse plain constructions best.

- Keep words like "only" and "not" next to the word they change. "Only fails on growth" and "fails
  only on growth" say different things.
- Break up long noun strings: "the proto import budget check script" becomes "the script that checks
  the proto-import budget".
- Make every "it", "they", and "this" point at one obvious thing. Repeat the noun when in doubt.
  Never use "this" or "which" to point at a whole clause.
- Do not drop verbs. "Phase 1 moves the converters and Phase 2 the runtime" leaves Phase 2 without
  one. Give it one.
- Keep the small words that show structure. "Ensure that the switch is off" keeps "that" because it
  makes the sentence parse one way. Never trade clarity for word count.
- Repeat the article in a series when it prevents a misread: "the client and the host", not "the
  client and host", when they are two things.
- Say which parts "and" or "or" joins when a sentence can group two ways. "Both…and", "either…or",
  and "if…then" are free disambiguators.
- Make text in parentheses a full grammatical unit or its own sentence. Never form plurals with
  "(s)".
- No slashes: write "a, b, or both" instead of "a/b" or "and/or".
- Call each thing by one name, everywhere. A document that says "the gate", "the ratchet", and "the
  budget check" for one thing teaches three things. Rewording an unchanged sentence between edits
  costs the same way — do not churn what did not change.
- Skip idioms, colloquialisms, Latin abbreviations, and metaphors.

### Two punctuation rules that a project may well disable

Kohl's guidelines also say: prefer periods to semicolons, and replace an em dash with a new
sentence. Both are here because they are part of the standard being paraphrased, and both are the
first rules a project with a deliberate house style is likely to overrule.

That is the intended outcome, not a defect. A project that uses em dashes on purpose disables this
pair the same way it disables any other rule — through its own declared style guide or its prose
linter's configuration — and the disabled rule stays visible as a decision rather than vanishing.
Do not apply either rule to a project that has ruled against it, and do not delete them for
projects that have not.
