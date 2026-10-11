import { expect, test } from 'claude-code/testing'
import { blankProps, blocks, compilePatterns, distinct, maskProps, maskText, splitBlocks, splitMatches } from './mask.ts'

const M = '[hidden]'
const { patterns } = compilePatterns([])
const mask = (text: string) => maskText(text, patterns, M)

// Token prefixes are joined at run time so no secret scanner reads this file as a credential.
const GH = 'gh' + 'p_'
const PAT = 'github' + '_pat_'
const SLACK = 'xo' + 'xb-'

test('masks an email address that has a TLD', () => {
  expect(mask('mail kyle@example.com now')).toBe(`mail ${M} now`)
})

test('leaves an at-sign without a TLD alone', () => {
  expect(mask('user@localhost and @mention')).toBe('user@localhost and @mention')
})

test('masks an sk- key', () => {
  expect(mask('key sk-abc123_DEF-456 end')).toBe(`key ${M} end`)
})

test('masks a ghp_ token', () => {
  expect(mask(`t ${GH}AbC123xyz9 end`)).toBe(`t ${M} end`)
})

test('masks a github_pat_ token', () => {
  expect(mask(`t ${PAT}11ABC_def456 end`)).toBe(`t ${M} end`)
})

test('masks a Slack token', () => {
  expect(mask(`t ${SLACK}123456789012-abcDEF end`)).toBe(`t ${M} end`)
})

test('masks an AWS access key id', () => {
  expect(mask('id AKIAIOSFODNN7EXAMPLE end')).toBe(`id ${M} end`)
})

test('masks a JWT', () => {
  expect(mask('jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln end')).toBe(`jwt ${M} end`)
})

test('masks a terminated PEM private key block', () => {
  const pem = '-----BEGIN RSA PRIVATE KEY-----\nMIIabc\nxyz\n-----END RSA PRIVATE KEY-----'
  expect(mask(`before\n${pem}\nafter`)).toBe(`before\n${M}\nafter`)
})

test('masks an unterminated PEM block through the end of the text', () => {
  expect(mask('before\n-----BEGIN PRIVATE KEY-----\nMIIabc\nstill str')).toBe(`before\n${M}`)
})

test('masks a token that is still streaming', () => {
  expect(mask('sk-')).toBe(M)
  expect(mask(`${GH}`)).toBe(M)
  expect(mask('AKIA')).toBe(M)
  expect(mask('eyJhbGc')).toBe(M)
  expect(mask('eyJhbGciOi.eyJzdWI')).toBe(M)
})

test('does not mask the sk- inside a longer word', () => {
  expect(mask('the task-force and risk-based plan')).toBe('the task-force and risk-based plan')
})

test('leaves noreply addresses alone', () => {
  const text = 'Co-Authored-By: Claude <noreply@anthropic.com> and 12345+kyle@users.noreply.github.com'
  expect(mask(text)).toBe(text)
})

test('leaves a git@ remote alone but masks a git@ address without the colon', () => {
  expect(mask('git@github.com:melodic-software/repo.git')).toBe('git@github.com:melodic-software/repo.git')
  expect(mask('write to git@example.com please')).toBe(`write to ${M} please`)
})

test('leaves plain text untouched', () => {
  const text = 'Run the tests, then open the pull request. Cost is 5 @ 3.50 each.'
  expect(mask(text)).toBe(text)
})

test('masks every occurrence and uses the mask literally', () => {
  expect(maskText('a@b.io c@d.io', patterns, '$&')).toBe('$& $&')
})

test('applies a valid extra pattern', () => {
  const r = compilePatterns(['ACME-\\d{4}'])
  expect(r.invalid).toEqual([])
  expect(maskText('ticket ACME-1234 here', r.patterns, M)).toBe(`ticket ${M} here`)
})

test('returns invalid, over-long, empty-matching and nested-quantifier patterns in invalid and skips them', () => {
  const tooLong = 'a'.repeat(201)
  const bad = [
    '(unclosed',
    tooLong,
    '(a+)+$',
    '((x*)y)*',
    'a*',
    '(\\d+){2,}',
    // Alternation in a quantified group, and unbounded quantifiers over overlapping classes.
    '(a|a)*b',
    '(?:x|(y|z))+w',
    '\\d+\\d+\\d+\\d+x',
    '.*=.*=.*=.*;',
    '\\w*\\d{0,99}x',
    'a?'.repeat(20) + 'x',
  ]
  const r = compilePatterns([...bad, 'ok-\\d+'])
  expect(r.invalid).toEqual(bad)
  expect(maskText('ok-12 and aaa and (unclosed', r.patterns, M)).toBe(`${M} and aaa and (unclosed`)
})

test('skips a pattern with a backreference, which can backtrack without bound', () => {
  const bad = ['(a*)\\1b', '(?<n>a+)\\k<n>c']
  const r = compilePatterns([...bad, 'x\\\\1'])
  expect(r.invalid).toEqual(bad)
  const start = Date.now()
  maskText('a'.repeat(100_000), r.patterns, M)
  expect(Date.now() - start).toBeLessThan(1000)
})

test('accepts a quantifier in a group that is not itself quantified, and an escaped paren', () => {
  const r = compilePatterns(['(ab+)c', '\\(x+\\)?', '(?:ab|cd)?e+', '[A-Z]{2,10}-\\d{1,6}'])
  expect(r.invalid).toEqual([])
})

test('maskProps masks only the named keys, recursing into nested strings', () => {
  const props = { text: 'hi a@b.io', nested: { rows: ['x', 'c@d.io'], n: 3 }, other: 'e@f.io' }
  const out = maskProps(props, ['text'], patterns, M)
  expect(out).toEqual({ text: `hi ${M}`, nested: { rows: ['x', 'c@d.io'], n: 3 }, other: 'e@f.io' })
  const deep = maskProps({ body: [{ t: 'a@b.io' }, 7, null], keep: 'a@b.io' }, ['body'], patterns, M)
  expect(deep).toEqual({ body: [{ t: M }, 7, null], keep: 'a@b.io' })
})

test('maskProps keeps key presence and never adds a key or turns a value undefined', () => {
  const props: { a?: string; b?: string; c: undefined } = { b: undefined, c: undefined }
  const out = maskProps(props, ['a', 'b', 'c'], patterns, M)
  expect(Object.keys(out)).toEqual(['b', 'c'])
  expect('a' in out).toBe(false)
  expect(out.b).toBe(undefined)
  expect(props).toEqual({ b: undefined, c: undefined })
})

test('maskProps does not change its input', () => {
  const props = { text: 'a@b.io', nested: { s: 'c@d.io' } }
  maskProps(props, ['text', 'nested'], patterns, M)
  expect(props).toEqual({ text: 'a@b.io', nested: { s: 'c@d.io' } })
})

test('masks 100,000 characters quickly, including adversarial runs', () => {
  const filler = 'plain words and numbers 12345 '.repeat(3300)
  const inputs = [
    `${filler}kyle@example.com ${filler}sk-abc`,
    'a'.repeat(100_000),
    'a.'.repeat(50_000),
    'x@' + 'a.'.repeat(50_000),
    'x@' + 'a'.repeat(100_000),
    'sk-'.repeat(33_000),
    'eyJ' + 'a.'.repeat(50_000),
    '-----BEGIN PRIVATE KEY-----'.repeat(3_700),
  ]
  const start = Date.now()
  for (const input of inputs) mask(input)
  expect(Date.now() - start).toBeLessThan(1000)
  expect(mask(inputs[0] as string)).toBe(`${filler}${M} ${filler}${M}`)
})

test('distinct leaves values that are already distinct alone', () => {
  expect(distinct(['a [hidden]', 'b [hidden]'], M)).toEqual(['a [hidden]', 'b [hidden]'])
})

const isDistinct = (list: readonly string[]) => new Set(list).size === list.length

test('distinct makes values distinct that masking made equal, keeping the mask', () => {
  const out = distinct(['Mail [hidden]', 'Mail [hidden]', 'Skip'], M)
  expect(out.length).toBe(3)
  expect(isDistinct(out)).toBe(true)
  expect(out[0]).toContain('[hidden')
  expect(out[1]).toContain('[hidden')
  expect(out[2]).toContain('Skip')
})

test('distinct still makes values distinct when renumbering the masks would collide', () => {
  for (const values of [['x [hidden 2]', 'x [hidden]', 'x [hidden]'], ['same', 'same']]) {
    const out = distinct(values, M)
    expect(out.length).toBe(values.length)
    expect(isDistinct(out)).toBe(true)
  }
})

test('masks an email that is still streaming, before its TLD arrives', () => {
  expect(mask('kyle@example')).toBe(M)
  expect(mask('reply to kyle@exa')).toBe(`reply to ${M}`)
  expect(mask('reply to kyle@')).toBe(`reply to ${M}`)
})

test('leaves at-signs that are not addresses alone', () => {
  const text = 'npm i @scope/pkg and foo @ bar, pkg@1.2.3, uses actions/checkout@v4 here'
  expect(mask(text)).toBe(text)
})

test('allows only a noreply local part or a GitHub noreply address', () => {
  expect(mask('a kyle.noreply@example.com b')).toBe(`a ${M} b`)
  expect(mask('a xnoreply@example.com b')).toBe(`a ${M} b`)
  expect(mask('a kyle@users.noreply.github.com b')).toBe(`a ${M} b`)
  expect(mask('a noreply@example.com b')).toBe('a noreply@example.com b')
})

test('maskProps masks object keys and keeps them distinct', () => {
  const out = maskProps({ answers: { 'Mail a@b.io?': 'yes', 'Mail c@d.io?': 'no' } }, ['answers'], patterns, M)
  const keys = Object.keys(out.answers)
  expect(keys.length).toBe(2)
  expect(isDistinct(keys)).toBe(true)
  expect(JSON.stringify(out)).not.toContain('.io')
  expect(Object.values(out.answers).sort()).toEqual(['no', 'yes'])
})

test('maskProps masks a value nested past its depth limit instead of passing it through', () => {
  let deep: unknown = { leaf: 'kyle@example.com' }
  for (let i = 0; i < 100; i++) deep = { next: deep }
  const out = maskProps({ deep }, ['deep'], patterns, M)
  expect(JSON.stringify(out)).not.toContain('kyle@example.com')
})

test('splitMatches returns the text around each match and the matches, as String.split and match do', () => {
  expect(splitMatches('Write a@example.com or b@example.com today.', patterns)).toEqual({
    parts: ['Write ', ' or ', ' today.'],
    hidden: ['a@example.com', 'b@example.com'],
  })
})

test('splitMatches leaves allowed addresses in the text and finds nothing in plain text', () => {
  const text = 'From noreply@example.com, push to git@github.com:o/r'
  expect(splitMatches(text, patterns)).toEqual({ parts: [text], hidden: [] })
})

test('splitMatches joins matches that overlap into one', () => {
  const { patterns: extra } = compilePatterns(['kyle@example'])
  expect(splitMatches('to kyle@example.com.', extra)).toEqual({ parts: ['to ', '.'], hidden: ['kyle@example.com'] })
})

test('blocks splits on blank lines and keeps a fenced block whole', () => {
  const text = 'One\nstill one\n\n```\na\n\nb\n```\n\n  \nThree'
  expect(blocks(text)).toEqual(['One\nstill one', '```\na\n\nb\n```', 'Three'])
})

test('blocks keeps an unclosed fence through the end of the text', () => {
  expect(blocks('Intro\n\n~~~\nx\n\ny')).toEqual(['Intro', '~~~\nx\n\ny'])
})

// The worst user patterns the guard accepts: each tries many lengths at every start.
const WORST_ACCEPTED = ['.*x', '[\\s\\S]*x', '.*.?.?x', '\\w*\\d{0,3}x', '(?=[\\s\\S]*x)y', 'a{0,4000}x', '(?:ab){0,4000}x']

test('runs each of the worst accepted extra patterns over 100,000 characters in under a second', () => {
  const r = compilePatterns(WORST_ACCEPTED)
  expect(r.invalid).toEqual([])
  const extras = r.patterns.slice(-WORST_ACCEPTED.length)
  expect(extras.map((p) => p.source)).toEqual(WORST_ACCEPTED)
  const inputs = ['a'.repeat(100_000), '1'.repeat(100_000), 'ab'.repeat(50_000), '= '.repeat(50_000)]
  for (const pattern of extras) {
    const start = Date.now()
    for (const input of inputs) maskText(input, [pattern], M)
    expect(Date.now() - start).toBeLessThan(1000)
  }
})

test('masks a token right after a color code and keeps every escape intact', () => {
  expect(mask(`\u001b[32m${GH}AbC123xyz9\u001b[0m`)).toBe(`\u001b[32m${M}\u001b[0m`)
  expect(mask('\u001b[01;31m\u001b[Ksk-abc123\u001b[m\u001b[K')).toBe(`\u001b[01;31m\u001b[K${M}\u001b[m\u001b[K`)
  expect(mask('\u001b[1mkyle@example.com\u001b[0m done')).toBe(`\u001b[1m${M}\u001b[0m done`)
})

test('keeps an escape inside a masked span and hides the text around it', () => {
  const pem = '-----BEGIN PRIVATE KEY-----\n\u001b[2mMIIabc\u001b[0m\n-----END PRIVATE KEY-----'
  expect(mask(`a ${pem} b`)).toBe(`a ${M}\u001b[2m\u001b[0m b`)
})

test('masks a whole token with an escape inside it, keeping the escape', () => {
  expect(mask('key sk-abc\u001b[0mdef123 end')).toBe(`key ${M}\u001b[0m end`)
  expect(mask('to a\u001b[1mb@example.com')).toBe(`to ${M}\u001b[1m`)
  expect(mask('x\u001b[32msk-abc')).toBe(`x\u001b[32m${M}`)
})

test('splitMatches finds a token after a color code and leaves the code outside the match', () => {
  expect(splitMatches('\u001b[32msk-abc\u001b[0m', patterns)).toEqual({ parts: ['\u001b[32m', '\u001b[0m'], hidden: ['sk-abc'] })
})

test('splitBlocks hides a match that crosses a blank line in every block it reaches', () => {
  const head = '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,0A1B'
  const body = 'MIIbody\n-----END RSA PRIVATE KEY-----'
  const split = splitBlocks(`Key:\n\n${head}\n\n${body}\n\nDone.`, patterns)
  expect(split).toEqual([
    { block: 'Key:', parts: ['Key:'], hidden: [] },
    { block: head, parts: ['', ''], hidden: [head] },
    { block: body, parts: ['', ''], hidden: [body] },
    { block: 'Done.', parts: ['Done.'], hidden: [] },
  ])
})

test('splitBlocks applies an extra pattern across a blank line', () => {
  const { patterns: extra } = compilePatterns(['TOP\\n\\nBOTTOM'])
  expect(splitBlocks('a TOP\n\nBOTTOM b', extra)).toEqual([
    { block: 'a TOP', parts: ['a ', ''], hidden: ['TOP'] },
    { block: 'BOTTOM b', parts: ['', ' b'], hidden: ['BOTTOM'] },
  ])
})

test('masks the other GitHub token kinds, including one still streaming', () => {
  for (const kind of ['o', 'u', 's', 'r', 'p']) {
    expect(mask(`t gh${kind}_AbC123xyz9 end`)).toBe(`t ${M} end`)
    expect(mask(`gh${kind}_`)).toBe(M)
  }
  expect(mask('the ghost_town and sigh_x')).toBe('the ghost_town and sigh_x')
})

test('masks a PGP private key block', () => {
  const block = '-----BEGIN PGP PRIVATE KEY BLOCK-----\n\nlQOYBF\n=abcd\n-----END PGP PRIVATE KEY BLOCK-----'
  expect(mask(`before\n${block}\nafter`)).toBe(`before\n${M}\nafter`)
})

test('maskProps recurses into an object with no prototype', () => {
  const bare = Object.assign(Object.create(null) as Record<string, unknown>, { to: 'kyle@example.com' })
  expect(maskProps({ body: bare }, ['body'], patterns, M)).toEqual({ body: { to: M } })
})

test('maskProps masks a value of any other object type whole', () => {
  class Envelope {
    constructor(readonly to: string) {}
  }
  const props = { a: new Envelope('kyle@example.com'), b: new Map([['k', 'kyle@example.com']]), c: [new Date(0)] }
  expect(maskProps(props, ['a', 'b', 'c'], patterns, M)).toEqual({ a: M, b: M, c: [M] })
})

test('blankProps masks every string, keeps field-name keys, and masks any other key', () => {
  const props = {
    input: { command: 'echo hi', count: 2, [`${GH}AbC123`]: 'x', 'Mail a@b.io?': 'yes', 'Go on?': 'no' },
    keep: 'plain',
  }
  const out = blankProps(props, ['input'], patterns, M)
  expect(out.keep).toBe('plain')
  expect(Object.entries(out.input).slice(0, 2)).toEqual([['command', M], ['count', 2]])
  const rest = Object.keys(out.input).slice(2)
  expect(rest.length).toBe(3)
  expect(new Set(rest).size).toBe(3)
  expect(rest.every((k) => k.startsWith('[hidden'))).toBe(true)
})
