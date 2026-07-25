#!/usr/bin/env python3
"""Report PreToolUse hook timeout rate and latency from Claude Code transcripts.

Ground truth comes from the harness's own hook attachments: `timedOut`,
`timeoutMs`, `durationMs`. A hook killed at its timeout contributes no verdict,
so `timeout_rate` is the guard's non-enforcement rate, not just a latency stat.

Usage:
    python hook_latency_report.py [--since YYYY-MM-DD] [--json OUT.json]

Regression gate: run once before a fix and once after, over comparable date
windows, and compare timeout_rate and p50_completed per command.
"""
import argparse, collections, glob, json, os, statistics, sys

PROJECTS = os.path.expanduser('~/.claude/projects/*/*.jsonl')


def hook_attachments(obj):
    if isinstance(obj, dict):
        if str(obj.get('type', '')).startswith('hook_'):
            yield obj
        for v in obj.values():
            yield from hook_attachments(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from hook_attachments(v)


def collect(since):
    rows, fanout = [], collections.Counter()
    for path in glob.glob(PROJECTS):
        for line in open(path, encoding='utf-8', errors='replace'):
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            ts = rec.get('timestamp') or ''
            if since and ts[:10] < since:
                continue
            for att in hook_attachments(rec):
                if 'durationMs' not in att:
                    continue
                rows.append({
                    'event': att.get('hookEvent'),
                    'command': att.get('command', ''),
                    'ms': att['durationMs'],
                    'timeout_ms': att.get('timeoutMs'),
                    'timed_out': bool(att.get('timedOut')),
                    'tool_use_id': att.get('toolUseID'),
                    'date': ts[:10],
                })
                fanout[(path, att.get('toolUseID'))] += 1
    return rows, fanout


def pct(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * p))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', help='only transcripts on/after this YYYY-MM-DD')
    ap.add_argument('--event', default='PreToolUse')
    ap.add_argument('--min-runs', type=int, default=5)
    ap.add_argument('--json', dest='json_out')
    args = ap.parse_args()

    rows, fanout = collect(args.since)
    rows = [r for r in rows if r['event'] == args.event]
    if not rows:
        sys.exit('no %s hook runs found (check --since)' % args.event)

    by_cmd = collections.defaultdict(list)
    for r in rows:
        by_cmd[r['command']].append(r)

    report = []
    for cmd, rs in by_cmd.items():
        if len(rs) < args.min_runs:
            continue
        killed = [r['ms'] for r in rs if r['timed_out']]
        done = [r['ms'] for r in rs if not r['timed_out']]
        report.append({
            'command': cmd,
            'runs': len(rs),
            'timeout_rate': round(len(killed) / len(rs), 4),
            'declared_timeout_ms': next((r['timeout_ms'] for r in rs if r['timeout_ms']), None),
            'p50_completed_ms': int(statistics.median(done)) if done else None,
            'p90_completed_ms': int(pct(done, .9)) if done else None,
            'p50_all_ms': int(statistics.median([r['ms'] for r in rs])),
        })
    report.sort(key=lambda d: (-d['timeout_rate'], -d['runs']))

    print('%-52s %6s %8s %8s %11s %11s' % (
        'command', 'runs', 'tmo(ms)', 'kill%', 'p50 done', 'p90 done'))
    for d in report:
        print('%-52s %6d %8s %7.0f%% %11s %11s' % (
            d['command'][:52], d['runs'], d['declared_timeout_ms'] or '-',
            d['timeout_rate'] * 100,
            d['p50_completed_ms'] if d['p50_completed_ms'] is not None else 'never',
            d['p90_completed_ms'] if d['p90_completed_ms'] is not None else 'never'))

    overall = sum(1 for r in rows if r['timed_out']) / len(rows)
    print('\n%s runs: %d | overall timeout (non-enforcement) rate: %.1f%%'
          % (args.event, len(rows), overall * 100))

    fan = collections.Counter(fanout.values())
    print('hooks-per-tool-call histogram: %s'
          % ', '.join('%d:%d' % (k, fan[k]) for k in sorted(fan)))

    if args.json_out:
        with open(args.json_out, 'w', encoding='utf-8') as fh:
            json.dump({'overall_timeout_rate': overall, 'commands': report}, fh, indent=2)
        print('wrote %s' % args.json_out)


if __name__ == '__main__':
    main()
