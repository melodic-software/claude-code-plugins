# Gateway Script Patterns

## What is a Gateway Script?

A gateway script is the entry point into agentic coding. It's the minimal code needed to invoke an agent programmatically - distinctly different from any other type of code because it calls an agent.

> "This script is the gateway into agentic coding. It's distinctly different from any other type of code - it's calling an agent."

## Pattern 1: Direct Prompt Execution

The simplest gateway - execute an ad-hoc prompt:

```python
# adw_prompt.py
import click
from adw_modules.agent import prompt_claude_code, AgentPromptRequest

@click.command()
@click.argument("prompt")
@click.option("--model", default="sonnet")
def main(prompt: str, model: str):
    adw_id = generate_short_id()  # 8-character UUID

    request = AgentPromptRequest(
        prompt=prompt,
        adw_id=adw_id,
        model=model,
        agent_name="oneoff",
        output_file=f"agents/{adw_id}/oneoff/cc_raw_output.jsonl"
    )

    response = prompt_claude_code(request)
    display_results(response)
```markdown

**Use when:**

- Quick one-off tasks
- Testing agent behavior
- Exploring capabilities
- Ad-hoc automation

## Pattern 2: Slash Command Execution

Execute any slash command through a gateway:

```python
# adw_slash_command.py
from adw_modules.agent import execute_template, AgentTemplateRequest

@click.command()
@click.argument("command")
@click.argument("args", nargs=-1)
def main(command: str, args: tuple):
    # Prefix with slash if needed
    prompt = f"/{command}" if not command.startswith("/") else command

    request = AgentTemplateRequest(
        slash_command=prompt,
        args=list(args),
        agent_name="executor"
    )

    response = execute_template(request)
```markdown

**Use when:**

- Programmatic template execution
- Scheduled slash commands
- Workflow composition
- External triggers

## Pattern 3: Composed Workflow

Chain multiple agents together:

```python
# adw_chore_implement.py
def main(chore_description: str):
    adw_id = generate_short_id()

    # Phase 1: Planning
    chore_response = execute_template(AgentTemplateRequest(
        slash_command="/chore",
        args=[adw_id, chore_description],
        agent_name="planner"
    ))

    # Extract plan path from output
    plan_path = extract_plan_path(chore_response.output)

    # Phase 2: Implementation
    implement_response = execute_template(AgentTemplateRequest(
        slash_command="/implement",
        args=[plan_path],
        agent_name="implementer"
    ))

    return implement_response
```markdown

**Use when:**

- Multi-step workflows
- Plan-then-implement patterns
- Complex automation
- Full SDLC execution

## Output File Organization

Every gateway script should organize outputs consistently:

```text
agents/
└── {adw_id}/               # Unique 8-char ID
    └── {agent_name}/       # Role of the agent
        ├── cc_raw_output.jsonl     # Streaming messages
        ├── cc_raw_output.json      # Parsed array
        ├── cc_final_object.json    # Last message (result)
        └── custom_summary_output.json  # Metadata
```markdown

## Safe Environment Handling

Filter environment variables when calling agents:

```python
def get_safe_subprocess_env() -> dict:
    """Only pass required environment variables."""
    safe_vars = {
        "ANTHROPIC_API_KEY": os.getenv("ANTHROPIC_API_KEY"),
        "CLAUDE_CODE_PATH": os.getenv("CLAUDE_CODE_PATH", "claude"),
        "PATH": os.getenv("PATH"),
        # Essential system vars only
    }
    return {k: v for k, v in safe_vars.items() if v is not None}
```markdown

## Retry Logic Pattern

Add resilience to gateway scripts:

```python
def prompt_with_retry(request, max_retries=3, delays=[1, 3, 5]):
    for attempt in range(max_retries):
        try:
            return prompt_claude_code(request)
        except (TimeoutError, ExecutionError) as e:
            if attempt < max_retries - 1:
                time.sleep(delays[attempt])
            else:
                raise
```markdown

## Rich Console Output

Use rich for readable output:

```python
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()

# Display results
console.print(Panel(
    response.output,
    title=f"[bold green]Agent: {agent_name}[/]",
    border_style="green"
))
```markdown

## Moving Out of the Loop

Gateway scripts move you out of the loop:

| Without Gateway | With Gateway |
| ----------------- | -------------- |
| Type prompt | Run script |
| Wait for response | Script handles response |
| Type next prompt | Script chains to next step |
| Manual process | Automated process |

> "By creating a script that can surround the application, that can surround any unit of code, we are slowly moving out the loop."

## Cross-References

- @agentic-layer-structure.md - Where gateway scripts live
- @adw-anatomy.md - Full ADW patterns
- @programmable-claude-patterns.md - Claude Code invocation
- @inloop-vs-outloop.md - Why moving out matters
