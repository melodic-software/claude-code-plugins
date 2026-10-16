---
type: llm
arm: both
focus: last_message
---

The user made a request. Judge the reply's final message.

PASS only if the reply names at least one concrete method, technique or tool a domain expert would use that the obvious first version of this work would skip, identifiable by name, and presents it as going beyond the default approach (for example "beyond the basic build, add X" or "an expert would also do X").

FAIL if every method named is part of the default way to do the request (the framework, library or language the request implies and its standard usage), if the methods are generic ("follow best practices", "test thoroughly", "use modern tools"), or if a method beyond the default is mentioned without being identifiable by name.
