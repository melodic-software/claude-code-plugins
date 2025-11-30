#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
get_subsection_content.py - Get subsection content from documents (token-optimized)

Retrieves specific subsection content from documents without loading the full document.
Designed for token-efficient access when search results indicate a subsection match.

Usage:
    # Get subsection by doc_id and heading
    python get_subsection_content.py <doc_id> --section "Section Heading"
    
    # Get subsection by doc_id and anchor
    python get_subsection_content.py <doc_id> --anchor "#section-heading"
    
    # Output JSON format (for tools/agents)
    python get_subsection_content.py <doc_id> --section "Skills vs slash commands" --json

Examples:
    python get_subsection_content.py code-claude-com-docs-en-slash-commands \\
        --section "Skills vs slash commands"
    
    python get_subsection_content.py code-claude-com-docs-en-plugins \\
        --anchor "#add-skills-to-your-plugin"
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import argparse
import json

from utils.cli_utils import add_common_index_args
from utils.script_utils import configure_utf8_output, EXIT_SUCCESS, EXIT_NO_RESULTS, EXIT_BAD_ARGS, normalize_url_for_display
from utils.logging_utils import get_or_setup_logger

# Configure UTF-8 output for Windows console compatibility
configure_utf8_output()

# Script logger
logger = get_or_setup_logger(__file__, log_category="search")

try:
    from core.doc_resolver import DocResolver
except ImportError:
    print("❌ Error: Could not import doc_resolver")
    print("Make sure doc_resolver.py is available (core/doc_resolver.py).")
    sys.exit(1)

def anchor_to_heading(anchor: str) -> str:
    """
    Convert anchor (#section-heading) to heading text (Section Heading)
    
    Args:
        anchor: Anchor string (with or without leading #)
    
    Returns:
        Heading text with title case
    """
    # Remove leading #
    if anchor.startswith('#'):
        anchor = anchor[1:]
    
    # Replace hyphens with spaces and title case
    heading = anchor.replace('-', ' ').title()
    return heading

def get_subsection_content(resolver: DocResolver, doc_id: str, 
                          section: str | None = None, 
                          anchor: str | None = None) -> dict | None:
    """
    Get subsection content from a document
    
    Args:
        resolver: DocResolver instance
        doc_id: Document identifier
        section: Section heading (optional if anchor provided)
        anchor: Section anchor like #section-heading (optional if section provided)
    
    Returns:
        Dictionary with content and metadata, or None if not found
    """
    # Use doc_resolver's get_content method
    if anchor and not section:
        # Convert anchor to heading
        section = anchor_to_heading(anchor)
    
    content_result = resolver.get_content(doc_id, section)
    
    if not content_result:
        return None
    
    # Add token count estimate (rough: 1 token ≈ 4 characters)
    if content_result.get('content'):
        content_len = len(content_result['content'])
        content_result['token_estimate'] = content_len // 4
    else:
        content_result['token_estimate'] = 0
    
    return content_result

def print_content_result(result: dict, json_output: bool = False):
    """Print content result in CLI or JSON format"""
    if json_output:
        # Normalize URL in JSON output
        result_copy = result.copy()
        if 'url' in result_copy:
            result_copy['url'] = normalize_url_for_display(result_copy['url'])
        print(json.dumps(result_copy, indent=2))
        return
    
    # CLI output
    print(f"📄 Document: {result.get('title', 'Unknown')}")
    print(f"   doc_id: {result.get('doc_id', 'Unknown')}")
    
    if result.get('url'):
        print(f"   url: {normalize_url_for_display(result.get('url'))}")
    
    content_type = result.get('content_type', 'unknown')
    if content_type == 'partial':
        print(f"   section: {result.get('section_ref', 'Unknown')}")
        print(f"   type: Subsection (token-optimized)")
    elif content_type == 'full':
        print(f"   type: Full document")
    else:
        print(f"   type: Link only (content not extracted)")
    
    token_est = result.get('token_estimate', 0)
    if token_est > 0:
        print(f"   tokens: ~{token_est:,} tokens")
    
    print()
    
    if result.get('warning'):
        print(f"⚠️  {result['warning']}")
        print()
    
    if result.get('content'):
        content = result['content']
        # Show preview for long content
        if len(content) > 500 and not json_output:
            print("Content preview (first 500 chars):")
            print("-" * 70)
            print(content[:500])
            print(f"\n... ({len(content) - 500} more characters)")
            print("-" * 70)
            print()
            print(f"💡 Use --json flag to get full content")
        else:
            print("Content:")
            print("-" * 70)
            print(content)
            print("-" * 70)
    else:
        print("(Content not available - link only)")

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Get subsection content from documents (token-optimized)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get subsection by heading
  python get_subsection_content.py code-claude-com-docs-en-slash-commands \\
      --section "Skills vs slash commands"
  
  # Get subsection by anchor
  python get_subsection_content.py code-claude-com-docs-en-plugins \\
      --anchor "#add-skills-to-your-plugin"
  
  # Output JSON for tools/agents
  python get_subsection_content.py code-claude-com-docs-en-skills \\
      --section "Progressive disclosure" --json
  
  # Get full document (no section specified)
  python get_subsection_content.py code-claude-com-docs-en-overview
        """
    )
    
    add_common_index_args(parser, include_json=True)
    
    parser.add_argument('doc_id', help='Document ID')
    parser.add_argument('--section', help='Section heading to extract')
    parser.add_argument('--anchor', help='Section anchor (e.g., #section-heading)')
    
    args = parser.parse_args()
    
    if not args.doc_id:
        parser.print_help()
        sys.exit(EXIT_BAD_ARGS)
    
    # Log script start
    logger.start({
        'doc_id': args.doc_id,
        'section': args.section,
        'anchor': args.anchor,
        'json': args.json
    })
    
    exit_code = EXIT_SUCCESS
    try:
        # Resolve base directory
        from utils.cli_utils import resolve_base_dir_from_args
        base_dir = resolve_base_dir_from_args(args)
        
        # Initialize resolver
        resolver = DocResolver(base_dir)
        
        # Get subsection content
        result = get_subsection_content(resolver, args.doc_id, args.section, args.anchor)
        
        if result:
            print_content_result(result, args.json)
            
            # Exit with appropriate code based on content type
            if result.get('content_type') == 'link':
                exit_code = EXIT_NO_RESULTS
        else:
            print(f"❌ Document not found or section not available: {args.doc_id}")
            if args.section:
                print(f"   Section: {args.section}")
            if args.anchor:
                print(f"   Anchor: {args.anchor}")
            exit_code = EXIT_NO_RESULTS
        
        logger.end(exit_code=exit_code)
        sys.exit(exit_code)
        
    except SystemExit:
        raise
    except Exception as e:
        logger.log_error("Fatal error in get_subsection_content", error=e)
        exit_code = 1
        logger.end(exit_code=exit_code)
        sys.exit(exit_code)

if __name__ == '__main__':
    main()

