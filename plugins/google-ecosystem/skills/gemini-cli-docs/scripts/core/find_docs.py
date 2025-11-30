#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
find_docs.py - Find and resolve documentation references

CLI tool for discovering and resolving documentation:
- Resolve doc_id to file path
- Search by keywords
- Search by natural language query
- Filter by category/tag
- Find related documents

Usage:
    python find_docs.py resolve <doc_id>
    python find_docs.py search <keyword1> [keyword2 ...]
    python find_docs.py query "natural language query"
    python find_docs.py category <category>
    python find_docs.py tag <tag>
    python find_docs.py related <doc_id>
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import argparse
import json

from utils.cli_utils import add_common_index_args
from utils.script_utils import (
    configure_utf8_output,
    resolve_base_dir,
    EXIT_SUCCESS,
    EXIT_NO_RESULTS,
    EXIT_BAD_ARGS,
    EXIT_INDEX_ERROR,
    normalize_url_for_display,
)
from utils.logging_utils import get_or_setup_logger

# Configure UTF-8 output for Windows console compatibility
configure_utf8_output()

# Script logger (structured, with performance tracking)
logger = get_or_setup_logger(__file__, log_category="search")

try:
    from core.doc_resolver import DocResolver
except ImportError:
    try:
        from scripts.core.doc_resolver import DocResolver
    except ImportError:
        print("❌ Error: Could not import doc_resolver")
        print("Make sure doc_resolver.py is available (core/doc_resolver.py).")
        sys.exit(EXIT_INDEX_ERROR)


def cmd_resolve(resolver: DocResolver, doc_id: str, extract_path: str | None = None, json_output: bool = False) -> int:
    """Resolve doc_id to file path. Returns 1 if found, 0 if not found."""
    path = resolver.resolve_doc_id(doc_id, extract_path)

    if json_output:
        result = {
            'doc_id': doc_id,
            'path': str(path) if path else None,
            'found': path is not None
        }
        print(json.dumps(result, indent=2))
    else:
        if path:
            print(f"✅ Resolved: {path}")
            print(f"   doc_id: {doc_id}")
        else:
            print(f"❌ Not found: {doc_id}")
            sys.exit(EXIT_NO_RESULTS)

    return 1 if path else 0


def _format_result_entry(doc_id: str, metadata: dict) -> dict:
    """
    Format a single result entry with standardized field ordering and classification.

    Result Classification:
    - 'subsection': Document has relevant subsection match
    - 'general': Document matches query (full document match)

    Priority ordering:
    1. doc_id (primary identifier for Claude Code references)
    2. path (local file path - PRIMARY reference for Claude Code)
    3. section_ref (subsection anchor if applicable)
    4. section_heading (human-readable section title)
    5. title (document title)
    6. url (web URL - SECONDARY/informational only)
    7. type (subsection or general)
    8. description, category, tags (metadata)
    9. extraction_command (if subsection match)
    """
    # Build result with proper field ordering
    result = {
        'doc_id': doc_id,
        'path': metadata.get('path')
    }

    # Get matched subsection (if any)
    matched_subsection = metadata.get('_matched_subsection')

    # Classify result type
    if matched_subsection:
        # Document has relevant subsection
        result['type'] = 'subsection'
        result['section_ref'] = matched_subsection.get('anchor')
        result['section_heading'] = matched_subsection.get('heading')
    else:
        # General match (full document match)
        result['type'] = 'general'

    # Add remaining fields
    result['title'] = metadata.get('title')
    result['url'] = normalize_url_for_display(metadata.get('url'))
    result['description'] = metadata.get('description')
    result['category'] = metadata.get('category')
    result['tags'] = metadata.get('tags', [])

    # Add extraction command for subsections
    if matched_subsection and metadata.get('_extraction_command'):
        result['extraction_command'] = metadata.get('_extraction_command')

    return result


def _display_search_results(results: list[tuple[str, dict]], header: str, verbose: bool = False) -> None:
    """Display search results with consistent formatting.

    Args:
        results: List of (doc_id, metadata) tuples
        header: Header text to display (e.g., "Found X document(s):")
        verbose: If True, show score details
    """
    print(f"📋 {header}\n")
    for i, (doc_id, metadata) in enumerate(results, 1):
        entry = _format_result_entry(doc_id, metadata)

        # Display with clear hierarchy
        type_indicator = " [SUBSECTION]" if entry['type'] == 'subsection' else ""
        score_indicator = f" (score: {metadata.get('_score', 'N/A')})" if verbose else ""
        print(f"{i}. {entry['title']}{type_indicator}{score_indicator}")
        print(f"   doc_id: {entry['doc_id']}")
        if entry['path']:
            print(f"   path: {entry['path']}")
        if entry.get('section_ref'):
            print(f"   section: {entry['section_ref']} ({entry.get('section_heading')})")
        if entry['url']:
            print(f"   url: {entry['url']} (web reference only)")
        if entry.get('description'):
            desc = entry['description'][:100] + '...' if len(entry['description']) > 100 else entry['description']
            print(f"   description: {desc}")
        if entry.get('extraction_command'):
            print(f"   extract: {entry['extraction_command']}")
        print()


def cmd_search(resolver: DocResolver, keywords: list[str], category: str | None = None,
              tags: list[str | None] = None, limit: int = 10, json_output: bool = False,
              verbose: bool = False) -> int:
    """Search documents by keywords. Returns number of results found."""
    results = resolver.search_by_keyword(keywords, category=category, tags=tags, limit=limit, return_scores=verbose)

    if json_output:
        output = [_format_result_entry(doc_id, metadata) for doc_id, metadata in results]
        print(json.dumps(output, indent=2))
    else:
        if not results:
            print(f"❌ No documents found for keywords: {', '.join(keywords)}")
            sys.exit(EXIT_NO_RESULTS)

        _display_search_results(results, f"Found {len(results)} document(s):", verbose)

    return len(results)


def cmd_query(resolver: DocResolver, query: str, limit: int = 10, json_output: bool = False,
              verbose: bool = False) -> int:
    """Search documents using natural language query. Returns number of results found."""
    results = resolver.search_by_natural_language(query, limit=limit, return_scores=verbose)

    if json_output:
        output = [_format_result_entry(doc_id, metadata) for doc_id, metadata in results]
        print(json.dumps(output, indent=2))
    else:
        if not results:
            print(f"❌ No documents found for query: {query}")
            sys.exit(EXIT_NO_RESULTS)

        _display_search_results(results, f"Found {len(results)} document(s) for query: '{query}'", verbose)

    return len(results)


def cmd_category(resolver: DocResolver, category: str, json_output: bool = False) -> int:
    """List all documents in a category. Returns number of results found."""
    results = resolver.get_by_category(category)

    if json_output:
        output = [_format_result_entry(doc_id, metadata) for doc_id, metadata in results]
        print(json.dumps(output, indent=2))
    else:
        if not results:
            print(f"❌ No documents found in category: {category}")
            sys.exit(EXIT_NO_RESULTS)

        print(f"📋 Documents in category '{category}' ({len(results)}):\n")
        for i, (doc_id, metadata) in enumerate(results, 1):
            title = metadata.get('title', 'Untitled')
            print(f"{i}. {title} ({doc_id})")
        print()

    return len(results)


def cmd_tag(resolver: DocResolver, tag: str, json_output: bool = False) -> int:
    """List all documents with a specific tag. Returns number of results found."""
    results = resolver.get_by_tag(tag)

    if json_output:
        output = [_format_result_entry(doc_id, metadata) for doc_id, metadata in results]
        print(json.dumps(output, indent=2))
    else:
        if not results:
            print(f"❌ No documents found with tag: {tag}")
            sys.exit(EXIT_NO_RESULTS)

        print(f"📋 Documents with tag '{tag}' ({len(results)}):\n")
        for i, (doc_id, metadata) in enumerate(results, 1):
            title = metadata.get('title', 'Untitled')
            print(f"{i}. {title} ({doc_id})")
        print()

    return len(results)


def cmd_content(resolver: DocResolver, doc_id: str, section: str | None = None, json_output: bool = False) -> int:
    """Get document content (full or partial section). Returns 1 if found, 0 if not found."""
    content_result = resolver.get_content(doc_id, section)

    if not content_result:
        print(f"❌ Document not found or content unavailable: {doc_id}")
        sys.exit(EXIT_NO_RESULTS)

    if json_output:
        # Normalize URL in JSON output
        content_result_copy = content_result.copy()
        if 'url' in content_result_copy:
            content_result_copy['url'] = normalize_url_for_display(content_result_copy['url'])
        print(json.dumps(content_result_copy, indent=2))
    else:
        print(f"📄 Document: {content_result.get('title', doc_id)}")
        print(f"   doc_id: {doc_id}")
        if content_result.get('url'):
            print(f"   url: {normalize_url_for_display(content_result.get('url'))}")
        if content_result.get('section_ref'):
            print(f"   section: {content_result.get('section_ref')}")
        print(f"   content_type: {content_result.get('content_type', 'unknown')}")
        print()
        print("⚠️ " + content_result.get('warning', 'Do not store file paths.'))
        print()
        if content_result.get('content'):
            content = content_result['content']
            # Show first 500 chars if content is long
            if len(content) > 500:
                print(content[:500] + "\n... (truncated, use --json for full content)")
            else:
                print(content)
        else:
            print("(Content not available - link only)")

    return 1 if content_result else 0


def cmd_related(resolver: DocResolver, doc_id: str, limit: int = 5, json_output: bool = False) -> int:
    """Find related documents. Returns number of results found."""
    results = resolver.get_related_docs(doc_id, limit=limit)

    if json_output:
        output = []
        for doc_id_result, metadata in results:
            output.append({
                'doc_id': doc_id_result,
                'title': metadata.get('title'),
                'url': normalize_url_for_display(metadata.get('url'))
            })
        print(json.dumps(output, indent=2))
    else:
        if not results:
            print(f"❌ No related documents found for: {doc_id}")
            sys.exit(EXIT_NO_RESULTS)

        print(f"📋 Related documents for '{doc_id}' ({len(results)}):\n")
        for i, (related_id, metadata) in enumerate(results, 1):
            title = metadata.get('title', 'Untitled')
            print(f"{i}. {title} ({related_id})")
        print()

    return len(results)


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Find and resolve documentation references',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Resolve doc_id to path (using default base directory)
  python find_docs.py resolve code-claude-com-docs-en-skills

  # Resolve doc_id and output JSON (for tools/agents)
  python find_docs.py --json resolve code-claude-com-docs-en-skills
  
  # Get full document content
  python find_docs.py content code-claude-com-docs-en-skills
  
  # Get specific section content
  python find_docs.py content code-claude-com-docs-en-skills --section "Progressive disclosure"
  
  # Search by keywords
  python find_docs.py search skills progressive-disclosure
  
  # Natural language search
  python find_docs.py query "how to create skills"
  
  # List by category
  python find_docs.py category api
  
  # List by tag
  python find_docs.py tag skills
  
  # Find related docs
  python find_docs.py related code-claude-com-docs-en-skills
        """
    )
    
    add_common_index_args(parser, include_json=True)
    parser.add_argument('--limit', type=int, default=10, help='Maximum results (default: 10)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Show scoring details for search results')
    parser.add_argument('--clear-cache', action='store_true', help='Clear cache before operation (forces rebuild)')

    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Resolve command
    resolve_parser = subparsers.add_parser('resolve', help='Resolve doc_id to file path')
    resolve_parser.add_argument('doc_id', help='Document ID to resolve')
    resolve_parser.add_argument('--extract-path', help='Optional extract path')
    
    # Content command
    content_parser = subparsers.add_parser('content', help='Get document content (full or partial section)')
    content_parser.add_argument('doc_id', help='Document ID')
    content_parser.add_argument('--section', help='Optional section heading to extract')
    
    # Search command
    search_parser = subparsers.add_parser('search', help='Search by keywords')
    search_parser.add_argument('keywords', nargs='+', help='Keywords to search for')
    search_parser.add_argument('--category', help='Filter by category')
    search_parser.add_argument('--tags', nargs='+', help='Filter by tags')
    
    # Query command
    query_parser = subparsers.add_parser('query', help='Natural language search')
    query_parser.add_argument('query', help='Natural language query')
    
    # Category command
    category_parser = subparsers.add_parser('category', help='List documents by category')
    category_parser.add_argument('category', help='Category name')
    
    # Tag command
    tag_parser = subparsers.add_parser('tag', help='List documents by tag')
    tag_parser.add_argument('tag', help='Tag name')
    
    # Related command
    related_parser = subparsers.add_parser('related', help='Find related documents')
    related_parser.add_argument('doc_id', help='Document ID to find related docs for')
    
    args = parser.parse_args()
    
    if not args.command:
            parser.print_help()
            sys.exit(EXIT_BAD_ARGS)
    
    # Log script start
    logger.start({
        'command': args.command,
        'base_dir': args.base_dir,
        'json': args.json
    })
    
    exit_code = EXIT_SUCCESS
    result_count = 0
    try:
        # Resolve base directory
        base_dir = resolve_base_dir(args.base_dir)

        # Clear cache if requested
        if getattr(args, 'clear_cache', False):
            try:
                from utils.cache_manager import CacheManager
                cm = CacheManager(base_dir)
                cm.clear_inverted_index()
                print('Cache cleared. Rebuilding index...\n')
            except ImportError:
                print('Warning: CacheManager not available, skipping cache clear')

        # Initialize resolver
        resolver = DocResolver(base_dir)

        # Execute command and capture result count
        if args.command == 'resolve':
            result_count = cmd_resolve(resolver, args.doc_id, getattr(args, 'extract_path', None), args.json)
        elif args.command == 'content':
            result_count = cmd_content(resolver, args.doc_id, getattr(args, 'section', None), args.json)
        elif args.command == 'search':
            result_count = cmd_search(resolver, args.keywords, getattr(args, 'category', None),
                      getattr(args, 'tags', None), args.limit, args.json, args.verbose)
        elif args.command == 'query':
            result_count = cmd_query(resolver, args.query, args.limit, args.json, args.verbose)
        elif args.command == 'category':
            result_count = cmd_category(resolver, args.category, args.json)
        elif args.command == 'tag':
            result_count = cmd_tag(resolver, args.tag, args.json)
        elif args.command == 'related':
            result_count = cmd_related(resolver, args.doc_id, args.limit, args.json)
        else:
            parser.print_help()
            exit_code = 1

        logger.end(exit_code=exit_code, summary={'results_found': result_count})
        
    except SystemExit:
        raise
    except Exception as e:
        logger.log_error("Fatal error in find_docs", error=e)
        exit_code = 1
        logger.end(exit_code=exit_code)
        sys.exit(exit_code)


if __name__ == '__main__':
    main()

