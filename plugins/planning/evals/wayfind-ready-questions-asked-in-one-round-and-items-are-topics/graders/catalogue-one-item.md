---
type: llm
---

The user asked wayfind to chart a notification-preferences effort (destination: a PRD). Open: three yes/no questions the assistant already recommended answers for that wait on nothing (email digests on by default? keep the legacy SMS toggle? show a per-channel mute?), and two topics with no recommendation yet: the notification catalogue (which events exist, their names, who receives each) and the delivery-retry policy. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply charts the notification catalogue as one item holding its related questions (which events, their names, who receives each), not one item per question.

FAIL if it splits the catalogue into several items, or charts no catalogue item.
