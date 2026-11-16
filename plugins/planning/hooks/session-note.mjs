export const NOTE =
  'planning session note: /planning:interview is the planning plugin step that asks the user about the problem, ' +
  "users and scope before code is written, for a build request that states none of them, such as 'Add search to the product.'"

process.stdout.write(`${JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: NOTE } })}\n`)
