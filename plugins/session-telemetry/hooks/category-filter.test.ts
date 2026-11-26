import { expect, test } from 'claude-code/testing'
import { categoryFilter } from './register.ts'

const CATEGORIES = ['session', 'prompt', 'tool', 'permission', 'agent', 'task', 'turn', 'config', 'worktree', 'compaction', 'model', 'mcp', 'display', 'other']

const cases: [unknown, readonly string[]][] = [
  [undefined, CATEGORIES],
  ['', CATEGORIES],
  [' ', []],
  ['tool,permission', ['tool', 'permission']],
  [' tool , permission ', ['tool', 'permission']],
  ['tool,,permission', ['tool', 'permission']],
  ['TOOL', []],
  ['bogus', []],
  ['tool\tpermission', ['tool', 'permission']],
  ['tool\npermission', ['tool', 'permission']],
  ['tool\rpermission', []],
]

for (const [input, enabled] of cases) {
  test(`categoryFilter(${JSON.stringify(input)}) enables ${enabled.length === CATEGORIES.length ? 'every category' : JSON.stringify(enabled)}`, async () => {
    const wants = categoryFilter(input)
    expect(CATEGORIES.filter(wants).sort()).toEqual([...enabled].sort())
  })
}
