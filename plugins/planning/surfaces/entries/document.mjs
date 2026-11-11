// A Markdown document another person fills in, for a decision only they can answer. Needs no
// tool. It is not a way for the user to answer, so it is never offered beside the other surfaces:
// the user's request for it, or the handoff's recommendation, picks it.
export default {
  id: 'document',
  reportName: 'document',
  aliases: ['questionnaire', 'doc'],
  onRequest: true,
  available: () => ({ ok: true, reason: 'needs no tool' }),
  start: () => ({
    read: ['skills/interview/context/lane-document.md', 'skills/interview/context/question-shape.md'],
    rules:
      'Ask the user only about the send: who the document goes to and what they need back. The ' +
      'questions go into the document, in the shared question shape, each under its register id; ' +
      'write it to the memory slice, report the path, and never send it.',
  }),
}
