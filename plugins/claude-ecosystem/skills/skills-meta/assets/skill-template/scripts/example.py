#!/usr/bin/env python3
"""
Example Script for Skill Template

This demonstrates how to organize scripts within a skill.
Scripts can be executed without loading into context, making them
ideal for automation and data processing tasks.

Usage:
    python scripts/example.py <input>

Example:
    python scripts/example.py "Hello, World!"
"""

import sys


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 2:
        print("Usage: python example.py <input>")
        print("Example: python example.py 'Hello, World!'")
        sys.exit(1)

    input_text = sys.argv[1]
    result = process(input_text)
    print(f"Result: {result}")


def process(text: str) -> str:
    """
    Process the input text.

    Args:
        text: Input string to process

    Returns:
        Processed result string
    """
    # Replace this with your actual processing logic
    return f"Processed: {text}"


if __name__ == "__main__":
    main()
