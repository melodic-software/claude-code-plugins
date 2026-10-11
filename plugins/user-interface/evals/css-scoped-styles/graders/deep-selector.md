---
type: llm
arm: both
---
PASS only if the delivered rule that colors `.info-link__icon` can match under Vue scoped styles:
either it is written in PriceTag.vue's scoped block with `:deep()` (or `::v-deep`) around the child
selector, or the icon rule is moved into InfoLink.vue's own scoped block (driven by a prop, class or
hover state passed from PriceTag). FAIL if the only icon rule is a plain descendant selector such as
`.price-tag:hover .info-link__icon` in PriceTag.vue's scoped block, or if there is no icon rule.

Examples:
- PASS: `.price-tag:hover :deep(.info-link__icon) { color: var(--accent); }`
- PASS: "Move the icon rule into InfoLink.vue and drive it with a hover prop from PriceTag." with
  the rule shown in InfoLink.vue's `<style scoped>`.
- FAIL: "Add a prop to InfoLink ... `.price-tag:hover .info-link__icon { color: var(--accent); }`"
  in PriceTag.vue, with nothing scoped to InfoLink and no `:deep()`.
