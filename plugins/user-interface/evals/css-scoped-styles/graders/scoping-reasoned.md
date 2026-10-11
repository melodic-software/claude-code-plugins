---
type: llm
arm: both
---
The fixture has no installed dependencies and the run has no shell, so no build can run here.
Criterion 4 therefore accepts a stated way to check the compiled output, not only a check that ran.

PASS only if the answer (1) identifies that the components use Vue `<style scoped>`, (2) places the
new rules in PriceTag.vue's scoped style block, (3) reaches `.info-link__icon` with `:deep()` (or an
equivalent such as moving the rule into InfoLink.vue) and says why a plain descendant selector would
not match, and (4) checks, or says how to check, the compiled selector: the `data-v-*` attribute in
the built CSS or in browser devtools. FAIL if it writes a plain `.price-tag:hover .info-link__icon`
rule in the scoped block as the delivered answer, or never addresses scoping.
