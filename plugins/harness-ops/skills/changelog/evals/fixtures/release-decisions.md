<Update label="2.1.284" description="September 28, 2026">
  * Added `/mcp reconnect all` in the interactive terminal to retry every MCP server that failed to connect or needs authentication at once
  * Fixed `{"decision":"block"}` returned by Elicitation and ElicitationResult hooks being ignored; it now declines the MCP elicitation, as exit code 2 does
  * Fixed the debug log dropping a failed hook's stderr when the hook also wrote to stdout, and logging nothing for a failed hook with no output; failed hooks now also log their status code
  * Fixed tab bars in dialogs such as `/config` and `/plugin` breaking the title and tab labels mid-word in a narrow terminal; a tab that doesn't fit now moves to the next line whole
</Update>
