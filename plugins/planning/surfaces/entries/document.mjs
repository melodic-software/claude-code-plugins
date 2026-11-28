export default {
  id: 'document',
  reportName: 'document',
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
