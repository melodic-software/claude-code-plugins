#!/usr/bin/env node
// Build a codebase-mode lesson page: Teach chunks (each may end in a quiz
// block), Practice, then Go deeper.
//
// Every interpolated field goes through escapeHtml from the synced helper,
// including the raw concept name in the concept meta tag the slug-collision
// guard reads. The page has no script, image, or link: a quiz is a list of
// questions the learner answers in chat.

import { asText, e, pageShell, paragraphs, rows, runCli, textList } from "../../../lib/page-kit.mjs";

function quizBlock(questions) {
  const items = rows(questions).filter((row) => asText(row.question) !== "");
  if (items.length === 0) return "";
  const list = items
    .map((row) => {
      const choices = textList(row.choices);
      const choiceList =
        choices.length === 0 ? "" : `<ol class="choices">${choices.map((item) => `<li>${e(item)}</li>`).join("")}</ol>`;
      return `<li><p>${e(row.question)}</p>${choiceList}</li>`;
    })
    .join("\n");
  return `<h3>Check yourself</h3>\n<p class="muted">Answer in the conversation, for example 1B 2A. Your coach grades it there.</p>\n<ol>\n${list}\n</ol>`;
}

function citationList(citations) {
  const items = textList(citations);
  if (items.length === 0) return "";
  return `<ol>${items.map((item) => `<li><code>${e(item)}</code></li>`).join("")}</ol>`;
}

function teachBlock(chunk) {
  return `<section>\n<h3>${e(chunk.heading)}</h3>\n${paragraphs(chunk.paragraphs)}\n${citationList(chunk.citations)}\n${quizBlock(chunk.quiz)}\n</section>`;
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildLessonPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const concept = asText(source.concept) || "Lesson";
  const body = `<h1>Lesson: ${e(concept)}</h1>
<p class="muted">${e(source.mission)}</p>
<h2 id="teach">Teach</h2>
${rows(source.teach).map(teachBlock).join("\n")}
<h2 id="practice">Practice</h2>
${paragraphs(source.practice)}
${quizBlock(source.practiceQuiz)}
<h2 id="go-deeper">Go deeper</h2>
${paragraphs(source.goDeeper)}
${citationList(source.citations)}`;
  return pageShell(concept, body, `<meta name="concept" content="${e(concept)}">`);
}

runCli(import.meta.url, "build-lesson", buildLessonPage);
