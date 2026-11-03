// A shared session several people answer through a public tunnel link (shared/share.sh). Its
// ensure-running exits 2 without Python 3, curl or cloudflared. It opens a public link, so a
// setting alone never starts it: the owner's request (the `share` action) or yes does.
const python = ctx => ctx.has('python3') || ctx.has('python')

export default {
  id: 'shared-session',
  reportName: 'shared session',
  aliases: ['share', 'shared', 'group'],
  available(ctx) {
    const missing = [!python(ctx) && 'Python 3', !ctx.has('curl') && 'curl', !ctx.has('cloudflared') && 'cloudflared'].filter(Boolean)
    return missing.length ? { ok: false, reason: `missing ${missing.join(', ')}` } : { ok: true, reason: 'Python 3, curl and cloudflared found' }
  },
  start: session => ({
    read: ['skills/interview/context/lane-shared.md'],
    needsYes: session.decidedBy !== 'argument',
    rules:
      'One session per audience; several may run at once. It opens a public link: unless the user asked for it ' +
      '(needsYes false), offer it in one line and start only on the owner\'s yes, else take the default surface.',
  }),
}
