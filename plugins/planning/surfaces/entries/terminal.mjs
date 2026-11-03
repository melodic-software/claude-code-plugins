// Inline prose rounds in the conversation. Needs no tool, so it is always available.
export default {
  id: 'terminal',
  reportName: 'terminal',
  aliases: ['inline', 'prose', 'conversation'],
  available: () => ({ ok: true, reason: 'needs no tool' }),
  start: () => ({
    read: [],
    rules:
      'Ask each round as inline prose per SKILL.md "Question surface: inline prose by default" and the Stance; ' +
      'AskUserQuestion cards apply only here, when the user opted in and the round qualifies. ' +
      'On a dense round, offer the alternatives this resolution lists.',
  }),
}
