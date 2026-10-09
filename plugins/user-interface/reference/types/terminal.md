# Terminal: CLI output, TUIs, prompt themes, PowerShell, banners

Covers anything drawn in a terminal: command output, interactive TUIs, shell prompt themes,
PowerShell formatting, banners and ASCII art. Claude Code mods build on this file
(`mods.md`). `principles.md` applies first.

## Establish the target first

Before designing, find out which operating systems, shells and terminals the output must work in.
Ask when the project does not say. Default to cross-platform: Windows (Windows Terminal, conhost,
PowerShell and cmd), macOS (Terminal, iTerm2), Linux, and WSL. Design for the weakest target in the
set, then add richer output only where the program can detect support.

## Output that degrades safely

Check these in order at run time; the first that applies decides.

1. **Not a TTY.** When stdout is not a terminal (piped, redirected, captured by CI or an agent),
   emit no color, no styling, no cursor movement, no spinner and no animation. Print plain lines
   a script can parse. Progress goes to stderr, or nowhere.
2. **`NO_COLOR` set.** When `NO_COLOR` is present and not empty, add no ANSI color, whatever its
   value. Bold and underline may stay; meaning must not depend on color. Offer a `--no-color` flag
   as well, and let an explicit `--color` flag override both.
3. **`TERM=dumb`, or an unknown terminal.** Fall back to plain ASCII text: no color, no cursor
   movement, no box drawing, no emoji.
4. **No Nerd Font.** Never assume one. Use a Nerd Font or Powerline glyph only behind an option or
   a detected font, with a plain-text fallback such as `[ok]`, `[!]` or `>` in its place. Without
   that, stay with ASCII and common Unicode punctuation.

- **Pointer**: NO_COLOR, <https://no-color.org/>; Nerd Fonts, <https://www.nerdfonts.com/>
- **As of**: 2026-10-04
- **Recheck trigger**: no-color.org changes the rule's condition.

## Color

- Use the terminal's named ANSI colors (the 16 the user's theme defines), not fixed 24-bit values,
  so light and dark themes both stay readable. Never set a background color for body text.
- Keep the default foreground for most text. Reserve color for status: one color for errors, one for
  warnings, one for success, each paired with a word or glyph (`error:`, `warning:`) per the floor.
- Test against a light background as well as a dark one. Yellow and bright white often vanish on
  light themes; dim gray often vanishes on dark ones.

## Width and layout

- Read the terminal width at run time and wrap or truncate to it. Without a width (not a TTY),
  do not truncate: the reader is a program.
- Truncate in the middle of paths and identifiers, the end of prose, and say so with an ellipsis.
- Measure text in display columns, not characters. Emoji and East Asian wide characters take two
  columns, and terminals disagree on some emoji, so keep emoji out of aligned columns and tables.

- **Pointer**: Unicode East Asian Width, <https://www.unicode.org/reports/tr11/>
- **As of**: 2026-10-04
- **Recheck trigger**: a new Unicode version changes the width property for emoji.

## Messages, errors and `--help`

The project's developer-experience guidance decides what an error, a hook notice or `--help` must
contain (cause, fix, exit code, machine-readable form, which flags `--help` documents). This file
owns the wording and the look, except that a hook notice's phrasing follows `mods.md` "Wording":

- Lead with what happened, in the user's words, then what to do. One line when one line will do.
- Name the input that failed and the value received.
- Put the error label and color on the label only (`error:`), not the whole line.
- `--help`: usage line first, then the few options most people need, then the rest; align option
  descriptions; keep examples copy-pasteable.

For CLI conventions beyond presentation, the Command Line Interface Guidelines are a good shared
reference.

- **Pointer**: <https://clig.dev/>
- **As of**: 2026-10-04
- **Recheck trigger**: the guide's output or error sections change.

## TUIs

- Use the project's TUI library and its components before drawing your own.
- Every screen shows where the user is, what the keys do (a footer line), and how to quit.
- Redraw only what changed; never flicker the whole screen on a timer.
- Restore the terminal (cursor, alternate screen, echo) on exit, including on Ctrl+C and crashes.

## Prompt themes

- A prompt shows only what the user acts on at the prompt: location, branch state, last exit code.
- Every segment has a glyph-free fallback (see "No Nerd Font").
- The prompt must render in well under the time it takes to type; slow segments run async or go.

## PowerShell

- Emit objects, not formatted strings; format only at the end of the pipeline, so piped output
  stays usable by the next command.
- Use `$PSStyle` for ANSI styling, and respect its output-rendering setting, which by default
  removes styling from redirected or piped output. It does not cover native executables, so a
  native tool checks for a TTY itself.
- Use format files or `Format-Table` properties for default views rather than `Write-Host` art.

- **Pointer**: <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_ansi_terminals>
- **As of**: 2026-10-04
- **Recheck trigger**: the page changes `$PSStyle.OutputRendering` behavior.

## Banners and ASCII art

- A banner is optional decoration: print it only on an interactive start, never in piped output,
  and give a flag to suppress it.
- Keep it within the narrowest supported width (80 columns unless the target says otherwise), in
  plain ASCII unless Unicode support is detected, and no taller than the information it frames.
- The program's name and version appear as plain text near the art, so a screen reader and a log
  carry them.
