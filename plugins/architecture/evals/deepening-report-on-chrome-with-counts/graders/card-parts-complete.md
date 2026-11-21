---
type: regex
pattern: '^(?=[\s\S]*?<article class="card")(?![\s\S]*?(?:<article class="card"(?:(?!</article>|data-part="title")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="badges")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="problem")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="solution")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="diagram")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="wins")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="verified")[\s\S])*</article>|<article class="card"(?:(?!</article>|data-part="files")[\s\S])*</article>|class="v\b[^"]*"[^>]*>\s*</))'
target: { source: file, path: deepening-report/report.html }
---
