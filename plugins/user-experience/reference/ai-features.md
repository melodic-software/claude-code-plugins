# UX of AI features

Load when: the app being built has a feature driven by AI (generated content, predictions,
recommendations, a chat assistant, an agent acting for the person), and its flow, expectations,
failure handling or measures are being designed or reviewed.

This file is about AI inside the app. AI inside the plugin's own work is covered where it applies:
synthetic users in `reference/research-methods.md`, AI-assisted analysis in
`reference/synthesis.md`, LLM inspection in `reference/evaluation.md`.

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## The checklist

Microsoft, Google PAIR and Apple publish this guidance independently and agree on the checks each
row cites them for; Apple and Microsoft are not sources for calibrated trust. These are guidance documents, not
studies of end-user outcomes; NN/g corroborates the expectation, calibrated-trust and fallibility
parts only.

| Check | What to design | Basis |
|---|---|---|
| Set expectations | Say what the feature can do and how well. | [ms-guidelines], [pair-guidebook], [apple-genai], [nng-hallucinations], HIGH |
| Calibrate trust | Aim for people knowing when to rely on the output and when to use their own judgment, not for maximal trust. | [pair-guidebook], [pair-trust], [zhang-calibration], [nng-explainable], HIGH; one study, of a classical ML classifier rather than an LLM, found calibration alone did not improve decision accuracy |
| Show it can be wrong | Tell people generated content may contain errors, and give them a way to check it (sources, uncertainty cues). A generic disclaimer alone is easy to ignore, and fine-grained numeric confidence can confuse. | [apple-genai], [nng-hallucinations], [ms-guidelines], [pair-trust], HIGH |
| Keep people in control | Make dismissing, editing, reverting and retrying cheap. | [ms-guidelines], [pair-guidebook], [apple-genai], HIGH |
| Plan for failure | Define errors from the person's point of view, narrow or degrade the feature when the AI is uncertain, hand control back, and confirm before any irreversible action. | [ms-guidelines], [pair-errors], [apple-genai], HIGH |
| Collect feedback | Let people tell the product when an output is wrong or unhelpful. | [ms-guidelines], [pair-guidebook], [apple-genai], HIGH |

Microsoft's 18 guidelines group these checks by when they apply: initially, during interaction,
when the AI is wrong, and over time. Walk a feature's flow through those four moments. Basis:
[ms-guidelines], HIGH (single source); the guidelines were validated with design practitioners, not
measured on end users.

- **Pointer**: for Apple's current guidance on generative AI features, read the Human Interface
  Guidelines, Generative AI, at <https://developer.apple.com/design/human-interface-guidelines/generative-ai>.
- **As of**: 2026-10-04
- **Recheck trigger**: the page's change log shows an update.
- **Pointer**: for Google's chapters on user needs, mental models, trust, feedback and errors, read
  the People + AI Guidebook at <https://pair.withgoogle.com/guidebook/>.
- **As of**: 2026-10-04
- **Recheck trigger**: PAIR publishes a new guidebook version or re-dates its principles.

## Chat and answer interfaces

- People use a site's own AI chatbot transactionally, like search, and prefer short, scannable,
  specific answers with suggested follow-ups over open conversation. Basis: [nng-less-chat], HIGH
  (single source; nine participants, site-specific chatbots).
- Citations and step-by-step explanations can raise trust without being accurate, and people rarely
  open the citations. Do not treat their presence as verification. Basis: judgment over MEDIUM
  evidence ([nng-explainable]).

## What this plugin owns

- **Flow.** Where the AI step sits in the user flow, what the person sees while it works, and every
  path when it is wrong, slow or unavailable (`reference/flows-ia.md`). Basis: judgment.
- **Content structure.** What the feature must tell people about its abilities and limits, at which
  step. Basis: judgment.
- **Research and evaluation.** Test with real people on realistic inputs, including inputs the AI
  gets wrong, and record how people notice and recover from a wrong output. Basis: judgment.
- **Measures.** Task success counts the cases where the AI was wrong and the person still finished
  the task, beside the cases where it was right (`reference/measurement.md`). Basis: judgment.

How the feature looks, its wording and its accessibility conformance belong to
`/user-interface:design`. Basis: judgment.

[ms-guidelines]: https://www.microsoft.com/en-us/research/wp-content/uploads/2019/01/Guidelines-for-Human-AI-Interaction-camera-ready.pdf
[pair-guidebook]: https://pair.withgoogle.com/guidebook/
[pair-trust]: https://pair.withgoogle.com/chapter/explainability-trust/
[zhang-calibration]: https://arxiv.org/abs/2001.02114
[pair-errors]: https://pair.withgoogle.com/chapter/errors-failing/
[apple-genai]: https://developer.apple.com/design/human-interface-guidelines/generative-ai
[nng-hallucinations]: https://www.nngroup.com/articles/ai-hallucinations/
[nng-explainable]: https://www.nngroup.com/articles/explainable-ai/
[nng-less-chat]: https://www.nngroup.com/articles/less-chat-more-answer/
