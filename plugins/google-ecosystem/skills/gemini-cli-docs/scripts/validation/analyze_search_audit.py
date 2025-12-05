#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_search_audit.py - Analyze search audit results and identify issues

Reviews search results for:
- Relevance issues (top result not matching topic)
- Domain distribution issues
- Missing relevant docs
- Irrelevant docs in top 10
"""

import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bootstrap; skill_dir = bootstrap.skill_dir

# Configure UTF-8 output for Windows console compatibility
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def analyze_topic(topic: str, topic_data: dict[str, Any]) -> dict[str, Any]:
    """Analyze all queries for a single topic"""

    issues = []
    stats = {
        "total_queries": len(topic_data["queries"]),
        "queries_with_issues": 0,
        "total_results": 0,
        "domain_distribution": {}
    }

    for query in topic_data["queries"]:
        query_type = query["type"]
        query_text = query["query"]
        results = query["results"]
        result_count = query["result_count"]

        stats["total_results"] += result_count

        # Check if top result is relevant
        if results:
            top_result = results[0]
            top_title = top_result["title"].lower()
            top_doc_id = top_result["doc_id"]
            top_domain = top_result["domain"]

            # Aggregate domain distribution
            for domain, count in query["domain_distribution"].items():
                stats["domain_distribution"][domain] = stats["domain_distribution"].get(domain, 0) + count

            # Relevance checks based on topic
            is_relevant = False

            # Define expected keywords for each Gemini CLI topic
            topic_mapping = {
                "installation": ["install", "setup", "getting started"],
                "authentication": ["auth", "login", "credential", "api key"],
                "commands": ["command", "cli"],
                "tools": ["tool", "function"],
                "extensions": ["extension", "plugin"],
                "mcp": ["mcp", "model context protocol"],
                "checkpointing": ["checkpoint", "save", "restore"],
                "sandbox": ["sandbox", "isolation", "security"],
                "settings": ["setting", "configuration", "config"],
                "models": ["model", "gemini"],
                "context": ["context", "window"],
                "prompts": ["prompt", "system prompt"],
            }

            expected = topic_mapping.get(topic, [topic])

            # Check if any expected keyword is in title or doc_id
            for keyword in expected:
                if keyword in top_title or keyword in top_doc_id.lower():
                    is_relevant = True
                    break

            if not is_relevant:
                stats["queries_with_issues"] += 1
                issues.append({
                    "severity": "HIGH",
                    "query_type": query_type,
                    "query": query_text,
                    "issue": "Top result not relevant to topic",
                    "top_result_title": top_result["title"],
                    "top_result_doc_id": top_doc_id,
                    "top_result_domain": top_domain,
                    "expected_keywords": expected
                })

            # Check if geminicli.com docs are present
            has_geminicli = any(r["domain"] == "geminicli.com" for r in results)
            if not has_geminicli:
                issues.append({
                    "severity": "MEDIUM",
                    "query_type": query_type,
                    "query": query_text,
                    "issue": "No geminicli.com results for Gemini CLI feature",
                    "note": "Gemini CLI features should include geminicli.com docs"
                })

            # Check for very low result counts on common topics
            if result_count < 3 and topic in ["installation", "commands", "tools", "models"]:
                issues.append({
                    "severity": "MEDIUM",
                    "query_type": query_type,
                    "query": query_text,
                    "issue": f"Low result count ({result_count}) for common topic",
                })
        else:
            stats["queries_with_issues"] += 1
            issues.append({
                "severity": "CRITICAL",
                "query_type": query_type,
                "query": query_text,
                "issue": "No results returned",
            })

    return {
        "topic": topic,
        "issues": issues,
        "stats": stats
    }


def find_latest_audit_file() -> Path | None:
    """Find the most recent search audit results file"""
    logs_dir = skill_dir / 'logs' / 'validation'
    if not logs_dir.exists():
        return None

    audit_files = list(logs_dir.glob('*_search-audit-results.json'))
    if not audit_files:
        return None

    # Return most recent by filename (contains timestamp)
    return max(audit_files, key=lambda p: p.name)


def main() -> int:
    """Main entry point"""

    # Find latest audit results
    results_file = find_latest_audit_file()
    if not results_file or not results_file.exists():
        print(f"❌ No search audit results found. Run run_search_audit.py first.")
        return 1

    print(f"📄 Loading: {results_file}")

    with open(results_file, "r", encoding="utf-8") as f:
        audit_results = json.load(f)

    print("=" * 80)
    print("GEMINI CLI DOCS SEARCH AUDIT ANALYSIS")
    print("=" * 80)
    print()

    all_issues = []
    critical_count = 0
    high_count = 0
    medium_count = 0

    for topic, topic_data in audit_results["topics"].items():
        analysis = analyze_topic(topic, topic_data)

        if analysis["issues"]:
            all_issues.append(analysis)

            # Count by severity
            for issue in analysis["issues"]:
                severity = issue["severity"]
                if severity == "CRITICAL":
                    critical_count += 1
                elif severity == "HIGH":
                    high_count += 1
                elif severity == "MEDIUM":
                    medium_count += 1

    # Print summary
    print(f"📊 Summary:")
    print(f"  - Total topics analyzed: {len(audit_results['topics'])}")
    print(f"  - Topics with issues: {len(all_issues)}")
    print(f"  - Critical issues: {critical_count}")
    print(f"  - High severity issues: {high_count}")
    print(f"  - Medium severity issues: {medium_count}")
    print()

    # Print detailed issues by topic
    if all_issues:
        print("🔍 Detailed Issues by Topic:")
        print()

        for analysis in all_issues:
            topic = analysis["topic"]
            issues = analysis["issues"]
            stats = analysis["stats"]

            print(f"📌 Topic: {topic}")
            print(f"   Queries with issues: {stats['queries_with_issues']}/{stats['total_queries']}")
            print(f"   Domain distribution: {stats['domain_distribution']}")
            print()

            for issue in issues:
                severity = issue["severity"]
                emoji = "🔴" if severity == "CRITICAL" else "🟠" if severity == "HIGH" else "🟡"

                print(f"   {emoji} [{severity}] {issue['query_type']}: {issue['issue']}")
                print(f"      Query: {issue['query']}")

                if "top_result_title" in issue:
                    print(f"      Top result: {issue['top_result_title']}")
                    print(f"      Top doc_id: {issue['top_result_doc_id']}")
                    print(f"      Expected keywords: {issue['expected_keywords']}")

                if "note" in issue:
                    print(f"      Note: {issue['note']}")

                print()
    else:
        print("✅ No issues found!")

    # Save analysis report
    logs_dir = skill_dir / 'logs' / 'validation'
    logs_dir.mkdir(parents=True, exist_ok=True)

    from datetime import datetime, timezone
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M%S')
    output_file = logs_dir / f"{timestamp}_search-audit-analysis.json"

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({
            "summary": {
                "total_topics": len(audit_results["topics"]),
                "topics_with_issues": len(all_issues),
                "critical_issues": critical_count,
                "high_severity_issues": high_count,
                "medium_severity_issues": medium_count
            },
            "issues_by_topic": all_issues
        }, f, indent=2, ensure_ascii=False)

    print("=" * 80)
    print(f"📄 Detailed analysis saved to: {output_file}")
    print("=" * 80)

    return 0


if __name__ == "__main__":
    sys.exit(main())
