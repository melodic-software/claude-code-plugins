#!/usr/bin/env bash
# Seeds a Svelte app with an unanimated task list and no animation library.
set -euo pipefail

mkdir -p src/lib
cat > package.json <<'JSON'
{
  "name": "tallyhome",
  "private": true,
  "type": "module",
  "devDependencies": { "@sveltejs/vite-plugin-svelte": "^5.0.0", "svelte": "^5.0.0", "vite": "^6.0.0" }
}
JSON
cat > src/lib/TodoList.svelte <<'SVELTE'
<script>
  let { items = [] } = $props();
</script>

<ul class="todos">
  {#each items as item (item.id)}
    <li class="todo">{item.text}</li>
  {/each}
</ul>

<style>
  .todos { display: grid; gap: 8px; padding: 0; list-style: none; }
</style>
SVELTE
