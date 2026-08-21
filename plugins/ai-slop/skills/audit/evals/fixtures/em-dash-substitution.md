# Parser release notes

## 0.4

The parser accepts empty input — a change from 0.3. Callers that relied on the
old rejection path have to check for the empty case themselves.

The token table grew by two entries. Both of them are punctuation.
