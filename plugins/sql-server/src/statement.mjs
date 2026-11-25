
export class TokenizeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TokenizeError';
  }
}

export function tokenize(sql) {
  const tokens = [];
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    if (/\s/u.test(c)) {
      i += 1;
    } else if (c === '-' && sql[i + 1] === '-') {
      const end = sql.slice(i).search(/[\r\n]/u);
      i = end === -1 ? n : i + end + 1;
    } else if (c === '/' && sql[i + 1] === '*') {
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

const REMOTE_REFUSALS = ['OPENROWSET', 'OPENQUERY', 'OPENDATASOURCE'].map((word) => [
  word,
  `${word} reaches outside the registered server`,
]);

const SELECT_REFUSALS = new Map([
  ['INTO', 'SELECT ... INTO writes a table'],
  ['OPTION', 'a user OPTION (...) clause can override the per-call settings'],
  ...REMOTE_REFUSALS,
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
const isSetOperator = (t) => t?.kind === 'word' && SET_OPERATORS.has(t.value);

const refuse = (reason) => ({ ok: false, reason });
const isSemicolon = (t) => t?.kind === 'punct' && t.value === ';';
const BATCH_REFUSAL = 'only one statement is allowed; the text holds a batch of several';

function tokenizeOrRefuse(sql) {
  try {
    return { tokens: tokenize(String(sql)) };
  } catch (error) {
    if (error instanceof TokenizeError) return { refusal: refuse(error.message) };
    throw error;
  }
}

export function checkStatement(sql) {
  const { tokens, refusal } = tokenizeOrRefuse(sql);
  if (refusal) return refusal;
  while (isSemicolon(tokens.at(-1))) tokens.pop();
  if (tokens.length === 0) return refuse('the statement is empty');
  if (tokens.some(isSemicolon)) return refuse(BATCH_REFUSAL);
  const first = tokens[0];
  if (first.kind !== 'word' || (first.value !== 'SELECT' && first.value !== 'WITH')) {
    return refuse('only a SELECT, optionally led by WITH, is allowed');
  }

  let depth = 0;
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
      if (isSetOperator(prev)) continue;
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

const WRITE_STATEMENT_WORDS = new Set([
  ...[...STATEMENT_WORDS].filter((word) => !DML_WORDS.has(word) && word !== 'SET'),
  'DISABLE',
  'ENABLE',
  'RECEIVE',
  'SEND',
  'THROW',
]);

const WRITE_REFUSALS = new Map([
  ['OUTPUT', 'an OUTPUT clause returns rows; the write tool returns only the row count'],
  ...REMOTE_REFUSALS,
]);

export function checkWriteStatement(sql) {
  const { tokens, refusal } = tokenizeOrRefuse(sql);
  if (refusal) return refusal;
  const terminated = isSemicolon(tokens.at(-1));
  if (terminated) tokens.pop();
  if (tokens.length === 0) return refuse('the statement is empty');
  if (tokens.some(isSemicolon)) return refuse(BATCH_REFUSAL);
  const first = tokens[0];
  if (first.kind !== 'word' || !(DML_WORDS.has(first.value) || first.value === 'WITH')) {
    return refuse('only one INSERT, UPDATE, DELETE or MERGE, optionally led by WITH, is allowed');
  }

  let depth = 0;
  let main;
  let updates = 0;
  let sets = 0;
  let selects = 0;
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
      if (selects > 0) return refuse('SELECT ... INTO writes a new table');
    } else if (t.value === 'SELECT' && !isSetOperator(prev)) {
      selects += 1;
      if (main !== 'INSERT' || sourced || selects > 1) return refuse('a top-level SELECT is allowed only once, as the source of INSERT ... SELECT');
    }
  }
  if (depth !== 0) return refuse('unbalanced parentheses');
  if (main === undefined) return refuse('a WITH must lead an INSERT, UPDATE, DELETE or MERGE');
  return { ok: true, terminated };
}
