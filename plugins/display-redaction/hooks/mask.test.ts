import { expect, test } from 'claude-code/testing'
import { compilePatterns, maskProps, maskText } from './mask.ts'

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
  const bad = ['(unclosed', tooLong, '(a+)+$', '((x*)y)*', 'a*', '(\\d+){2,}']
  const r = compilePatterns([...bad, 'ok-\\d+'])
  expect(r.invalid).toEqual(bad)
  expect(maskText('ok-12 and aaa and (unclosed', r.patterns, M)).toBe(`${M} and aaa and (unclosed`)
})

test('accepts a quantifier in a group that is not itself quantified, and an escaped paren', () => {
  const r = compilePatterns(['(ab+)c', '\\(x+\\)+'])
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
