// test-scope: plugins/themes/hooks/bedroom/scene/lib.ts plugins/themes/hooks/bedroom/lights.ts
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const BEDROOM = new URL('../hooks/bedroom/', import.meta.url)
const read = path => readFileSync(new URL(path, BEDROOM), 'utf8')

const SHADER_ROWS = {
  tv: ['HIT', 0],
  lava: ['HIT', 1],
  pc: ['HIT', 2],
  lamp: ['HIT', 3],
  tape: ['HIT', 4],
  console: ['HIT', 5],
  light: ['HIT', 6],
  spine: ['HIT2', 4],
}

function hitsOf(source) {
  const block = /export const HITS[^=]*= \{\n([\s\S]*?)\n\}/.exec(source)
  assert.ok(block, 'scene/lib.ts declares HITS')
  return Object.fromEntries(
    block[1].split('\n').map(line => {
      const row = /^ {2}(\w+): (\[[\d, ]+\]),$/.exec(line)
      assert.ok(row, `a HITS line reads name: [x, y, width, height]: ${line}`)
      return [row[1], JSON.parse(row[2])]
    }),
  )
}

function tableOf(source, name) {
  const line = source.split('\n').find(text => text.startsWith(`const ${name} = table(`))
  assert.ok(line, `lights.ts declares ${name}`)
  return JSON.parse(line.slice(`const ${name} = table(`.length, -1))
}

test('the shader takes clicks over the same rectangles as HITS', () => {
  const hits = hitsOf(read('scene/lib.ts'))
  const lights = read('lights.ts')
  const tables = { HIT: tableOf(lights, 'HIT'), HIT2: tableOf(lights, 'HIT2') }

  assert.deepEqual(Object.keys(hits).filter(name => name !== 'cat').sort(), Object.keys(SHADER_ROWS).sort(), 'every switch rectangle has a shader row')
  for (const [name, [table, row]] of Object.entries(SHADER_ROWS)) {
    assert.deepEqual(tables[table][row], hits[name], `${name} is ${table} row ${row}`)
  }
  assert.equal(tables.HIT.length, 7, 'HIT has one row per switch column')
  assert.ok(
    tables.HIT2.every((box, row) => row === 4 || box.every(n => n === 0)),
    'HIT2 holds no rectangle but the spine',
  )
})
