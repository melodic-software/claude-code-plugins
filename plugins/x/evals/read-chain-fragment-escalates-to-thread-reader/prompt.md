---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reads the saved step-1 Markdown, recognizes from the thread request and the 1/ marker that it is a chain fragment, looks up the Thread Reader App page by the id from the X URL (not the quoted post''s id), confirms its final URL does not end in /error and that it carries the posts, and says step 2 assembled the chain.'
---

/x:read https://x.com/fakehandle/status/1234567890123456789

This one is a thread — I want the whole thing, not just the first post.

I already fetched on my laptop and copied the results here. The xtomd step: curl exited 0, HTTP 200, and the converted Markdown is in notes/xtomd-1234567890123456789.md. Every Thread Reader App page I fetched is saved under notes/threadreaderapp.com/ named by the URL path I requested, with a .txt beside each page holding its final URL and HTTP status. Use these files instead of fetching again.
