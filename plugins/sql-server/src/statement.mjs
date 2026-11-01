// The single-statement reject lists of ADR 0086 section 1 and its write-tier
// amendment: heuristic controls. checkStatement accepts one SELECT, optionally led by WITH, and
// checkWriteStatement one INSERT, UPDATE, DELETE or MERGE; each refuses
// everything else it can recognize. The principals, not these lists, are the
// guarantee.
// It works on tokens, so a keyword inside a comment, a string literal or a
// bracketed or quoted identifier never counts.

export class TokenizeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TokenizeError';
  }
}

// Token kinds: word (an unquoted keyword or name, value upper-cased), ident (a
// [bracketed] or "quoted" identifier), string, number, punct.
export function tokenize(sql) {
  const tokens = [];
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    if (/\s/u.test(c)) {
      i += 1;
    } else if (c === '-' && sql[i + 1] === '-') {
      // Ending at a lone \r too can only refuse more, never hide a keyword.
      const end = sql.slice(i).search(/[\r\n]/u);
      i = end === -1 ? n : i + end + 1;
    } else if (c === '/' && sql[i + 1] === '*') {
      // T-SQL block comments nest.
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (sql[i] === '/' && sql[i + 1] === '*') {
          depth += 1;
          i += 2;
        } else if (sql[i] === '*' && sql[i + 1] === '/') {
          depth -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      if (depth > 0) throw new TokenizeError('unterminated /* comment');
    } else if (c === "'" || c === '[' || c === '"') {
      const close = c === '[' ? ']' : c;
      let j = i + 1;
      let value = '';
      for (;;) {
        if (j >= n) throw new TokenizeError(`unterminated ${c === "'" ? 'string literal' : 'identifier'}`);
        if (sql[j] === close) {
          if (sql[j + 1] !== close) break;
          value += close;
          j += 2;
        } else {
          value += sql[j];
          j += 1;
        }
      }
      tokens.push({ kind: c === "'" ? 'string' : 'ident', value });
      i = j + 1;
    } else if (/[\p{L}_@#]/u.test(c)) {
      const match = /^[\p{L}\p{N}_@#$]+/u.exec(sql.slice(i));
      tokens.push({ kind: 'word', value: match[0].toUpperCase() });
      i += match[0].length;
    } else if (/[0-9.]/u.test(c) && /[0-9]/u.test(c === '.' ? (sql[i + 1] ?? '') : c)) {
      const match = /^(0x[0-9a-f]*|[0-9]*\.?[0-9]+(e[+-]?[0-9]+)?|[0-9]+\.)/iu.exec(sql.slice(i));
      tokens.push({ kind: 'number', value: match[0] });
      i += match[0].length;
    } else {
      tokens.push({ kind: 'punct', value: c });
      i += 1;
    }
  }
  return tokens;
}

// Reserved T-SQL keywords that start a statement and have no place inside a
// single SELECT, so any of them marks a second statement in a batch written
// without semicolons. The first token is checked separately, so this list
// never decides which statement kinds are allowed.
const STATEMENT_WORDS = new Set([
  'ADD',
  'ALTER',
  'BACKUP',
  'BEGIN',
  'BULK',
  'CHECKPOINT',
  'CLOSE',
  'COMMIT',
  'CREATE',
  'DBCC',
  'DEALLOCATE',
  'DECLARE',
  'DELETE',
  'DENY',
  'DROP',
  'EXEC',
  'EXECUTE',
  'GOTO',
  'GRANT',
  'IF',
  'INSERT',
  'KILL',
  'MERGE',
  'OPEN',
  'PRINT',
  'RAISERROR',
  'READTEXT',
  'RECONFIGURE',
  'RESTORE',
  'RETURN',
  'REVERT',
  'REVOKE',
  'ROLLBACK',
  'SAVE',
  'SET',
  'SETUSER',
  'SHUTDOWN',
  'TRUNCATE',
  'UPDATE',
  'UPDATETEXT',
  'USE',
  'WAITFOR',
  'WHILE',
  'WRITETEXT',
]);

const SELECT_REFUSALS = new Map([
  ['INTO', 'SELECT ... INTO writes a table'],
  ['OPTION', 'a user OPTION (...) clause can override the per-call settings'],
  ['OPENROWSET', 'OPENROWSET reaches outside the registered server'],
  ['OPENQUERY', 'OPENQUERY reaches outside the registered server'],
  ['OPENDATASOURCE', 'OPENDATASOURCE reaches outside the registered server'],
]);

export const LOCK_HINTS = Object.freeze([
  'HOLDLOCK',
  'SERIALIZABLE',
  'REPEATABLEREAD',
  'UPDLOCK',
  'XLOCK',
  'PAGLOCK',
  'TABLOCK',
  'TABLOCKX',
]);

const SET_OPERATORS = new Set(['UNION', 'ALL', 'EXCEPT', 'INTERSECT']);

const refuse = (reason) => ({ ok: false, reason });

// Returns { ok: true } or { ok: false, reason }.
export function checkStatement(sql) {
  let tokens;
  try {
    tokens = tokenize(String(sql));
  } catch (error) {
    if (error instanceof TokenizeError) return refuse(error.message);
    throw error;
  }
  while (tokens.length && tokens.at(-1).value === ';' && tokens.at(-1).kind === 'punct') tokens.pop();
  if (tokens.length === 0) return refuse('the statement is empty');
  if (tokens.some((t) => t.kind === 'punct' && t.value === ';')) {
    return refuse('only one statement is allowed; the text holds a batch of several');
  }
  const first = tokens[0];
  if (first.kind !== 'word' || (first.value !== 'SELECT' && first.value !== 'WITH')) {
    return refuse('only a SELECT, optionally led by WITH, is allowed');
  }

  let depth = 0;
  // A WITH preamble may hold one top-level SELECT, the main query.
  let mainSeen = first.value === 'SELECT';
  for (let k = 0; k < tokens.length; k += 1) {
    const t = tokens[k];
    if (t.kind === 'punct') {
      if (t.value === '(') depth += 1;
      if (t.value === ')') depth -= 1;
      if (depth < 0) return refuse('unbalanced parentheses');
      continue;
    }
    if (t.kind !== 'word') continue;
    const prev = tokens[k - 1];
    if (STATEMENT_WORDS.has(t.value)) return refuse(`${t.value} is not allowed: only one read statement may run`);
    if (t.value === 'FETCH' && !(prev?.kind === 'word' && (prev.value === 'ROW' || prev.value === 'ROWS'))) {
      return refuse('FETCH outside OFFSET ... FETCH is not allowed');
    }
    if (SELECT_REFUSALS.has(t.value)) return refuse(SELECT_REFUSALS.get(t.value));
    if (LOCK_HINTS.includes(t.value)) return refuse(`the ${t.value} lock hint is not allowed`);
    if (t.value === 'SELECT' && depth === 0 && k > 0) {
      if (prev?.kind === 'word' && SET_OPERATORS.has(prev.value)) continue;
      if (!mainSeen) {
        mainSeen = true;
        continue;
      }
      return refuse('only one statement is allowed; a second SELECT follows the first');
    }
  }
  if (depth !== 0) return refuse('unbalanced parentheses');
  if (!mainSeen) return refuse('a WITH must lead a SELECT');
  return { ok: true };
}

const DML_WORDS = new Set(['INSERT', 'UPDATE', 'DELETE', 'MERGE']);

// The write tool wraps the statement in its own transaction and row-count
// check, so a word that could end that transaction or start another statement
// is refused. SET is counted below, since UPDATE needs it.
const WRITE_STATEMENT_WORDS = new Set([
  ...[...STATEMENT_WORDS].filter((word) => !DML_WORDS.has(word) && word !== 'SET'),
  // Unreserved, so the read list lets them pass; a write has no use for them.
  'DISABLE',
  'ENABLE',
  'RECEIVE',
  'SEND',
  'THROW',
]);

const WRITE_REFUSALS = new Map([
  ['OUTPUT', 'an OUTPUT clause returns rows; the write tool returns only the row count'],
  ['OPENROWSET', 'OPENROWSET reaches outside the registered server'],
  ['OPENQUERY', 'OPENQUERY reaches outside the registered server'],
  ['OPENDATASOURCE', 'OPENDATASOURCE reaches outside the registered server'],
]);

// The write tier's reject list, a heuristic like the read one: it accepts one
// INSERT, UPDATE, DELETE or MERGE, optionally led by WITH. Returns
// { ok: true, terminated } (whether the text ends in a semicolon) or
// { ok: false, reason }.
export function checkWriteStatement(sql) {
  let tokens;
  try {
    tokens = tokenize(String(sql));
  } catch (error) {
    if (error instanceof TokenizeError) return refuse(error.message);
    throw error;
  }
  // One trailing semicolon is allowed; a second counts as another statement.
  const terminated = tokens.at(-1)?.kind === 'punct' && tokens.at(-1).value === ';';
  if (terminated) tokens.pop();
  if (tokens.length === 0) return refuse('the statement is empty');
  if (tokens.some((t) => t.kind === 'punct' && t.value === ';')) {
    return refuse('only one statement is allowed; the text holds a batch of several');
  }
  const first = tokens[0];
  if (first.kind !== 'word' || !(DML_WORDS.has(first.value) || first.value === 'WITH')) {
    return refuse('only one INSERT, UPDATE, DELETE or MERGE, optionally led by WITH, is allowed');
  }

  let depth = 0;
  let main;
  let updates = 0;
  let sets = 0;
  let selects = 0;
  // Set once an INSERT has its VALUES or DEFAULT VALUES source.
  let sourced = false;
  for (let k = 0; k < tokens.length; k += 1) {
    const t = tokens[k];
    if (t.kind === 'punct') {
      if (t.value === '(') depth += 1;
      if (t.value === ')') depth -= 1;
      if (depth < 0) return refuse('unbalanced parentheses');
      continue;
    }
    if (t.kind !== 'word') continue;
    const prev = tokens[k - 1];
    if (WRITE_STATEMENT_WORDS.has(t.value)) return refuse(`${t.value} is not allowed: only one write statement may run`);
    if (WRITE_REFUSALS.has(t.value)) return refuse(WRITE_REFUSALS.get(t.value));
    if (depth > 0) continue;
    if (DML_WORDS.has(t.value)) {
      // A MERGE's WHEN ... THEN INSERT, UPDATE or DELETE is part of it.
      const mergeAction = main === 'MERGE' && prev?.kind === 'word' && prev.value === 'THEN' && t.value !== 'MERGE';
      if (main !== undefined && !mergeAction) return refuse(`only one statement is allowed; a second ${t.value} follows the first`);
      main ??= t.value;
      if (t.value === 'UPDATE') updates += 1;
    } else if (t.value === 'SET') {
      sets += 1;
      if (sets > updates) return refuse('SET is allowed only in an UPDATE');
    } else if (t.value === 'VALUES' || t.value === 'DEFAULT') {
      if (main === 'INSERT') sourced = true;
    } else if (t.value === 'INTO') {
      // INSERT INTO and MERGE INTO come before any SELECT; one after it is SELECT ... INTO, which creates a table.
      if (selects > 0) return refuse('SELECT ... INTO writes a new table');
    } else if (t.value === 'SELECT' && !(prev?.kind === 'word' && SET_OPERATORS.has(prev.value))) {
      // INSERT ... SELECT is the one write with a top-level SELECT; any other
      // would be a second statement, and @@ROWCOUNT would count its rows.
      selects += 1;
      if (main !== 'INSERT' || sourced || selects > 1) return refuse('a top-level SELECT is allowed only once, as the source of INSERT ... SELECT');
    }
  }
  if (depth !== 0) return refuse('unbalanced parentheses');
  if (main === undefined) return refuse('a WITH must lead an INSERT, UPDATE, DELETE or MERGE');
  return { ok: true, terminated };
}
