let text = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', (chunk) => (text += chunk))
process.stdin.on('end', () => {
  const { source, session_id: id } = JSON.parse(text)
  const additionalContext = `Probe nonce: probe-nonce-${source}-${String(id).slice(0, 8)}`
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext } }))
})
