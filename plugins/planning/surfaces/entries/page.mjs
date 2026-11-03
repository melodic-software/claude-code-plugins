// A local 127.0.0.1 page this session watches (surface/round.sh). It needs bash, curl and a
// Python 3 (python3 or python), the tools round.sh and watch.sh exit 2 without.
const python = ctx => ctx.has('python3') || ctx.has('python')

export default {
  id: 'page',
  reportName: 'page',
  aliases: ['local page', 'browser'],
  available(ctx) {
    const missing = [!python(ctx) && 'Python 3', !ctx.has('curl') && 'curl', !ctx.has('bash') && 'bash'].filter(Boolean)
    return missing.length ? { ok: false, reason: `missing ${missing.join(', ')}` } : { ok: true, reason: 'Python 3, curl and bash found' }
  },
  start: session => ({
    read: ['skills/interview/context/lane-page.md', 'skills/interview/context/surface.md'],
    rules: session.available.ok
      ? 'Start the page before the first round and ask no round inline. The terminal stays an input, mirrored with ' +
        'record-terminal; a decision this session records or revises in the ledger is mirrored the same way.'
      : 'The page cannot start: take lane-page.md\'s degrade and say in one line which prerequisite failed.',
  }),
}
