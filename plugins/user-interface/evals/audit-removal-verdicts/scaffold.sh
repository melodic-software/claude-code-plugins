#!/usr/bin/env bash
# An over-animated app with removal hazards: a hidden start state and focus moved after an animation.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src index.html
mkdir -p src
cat > index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head><link rel="stylesheet" href="src/app.css"><script src="src/app.js" defer></script></head>
  <body>
    <section class="reveal"><article class="card">Plan A</article><article class="card">Plan B</article></section>
    <section class="reveal"><details class="accordion"><summary>FAQ</summary><div class="accordion-panel"><p>Answer</p></div></details></section>
    <div class="palette" role="dialog" aria-label="Command palette" hidden><input class="palette-input" aria-label="Command"></div>
    <div class="toast" role="status" hidden>Saved</div>
  </body>
</html>
HTML
cat > src/app.css <<'CSS'
.reveal { opacity: 0; transform: translateY(24px); }
.reveal.is-visible { opacity: 1; transform: none; transition: opacity 600ms ease-out, transform 600ms ease-out; }
.card { transition: transform 300ms ease-out; }
.card:hover { transform: translateY(-4px) scale(1.03); }
.palette:not([hidden]) { animation: palette-in 300ms ease-out; }
@keyframes palette-in { from { opacity: 0; transform: scale(0.9); } to { opacity: 1; transform: none; } }
.toast:not([hidden]) { animation: toast-in 200ms cubic-bezier(0.23, 1, 0.32, 1); }
@keyframes toast-in { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
.accordion-panel { display: grid; grid-template-rows: 0fr; transition: grid-template-rows 200ms ease-out; }
.accordion[open] .accordion-panel { grid-template-rows: 1fr; }
CSS
cat > src/app.js <<'JS'
const observer = new IntersectionObserver((entries) => {
  for (const entry of entries) if (entry.isIntersecting) entry.target.classList.add("is-visible");
});
document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
const palette = document.querySelector(".palette");
palette.addEventListener("animationend", () => document.querySelector(".palette-input").focus());
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "k") { e.preventDefault(); palette.hidden = !palette.hidden; }
});
JS
