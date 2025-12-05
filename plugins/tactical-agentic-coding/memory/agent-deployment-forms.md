# Agent Deployment Forms

Deploy custom agents in scripts, terminals, UIs, and data streams.

## Deployment Forms

| Form | Use Case | Example |
| ------ | ---------- | --------- |
| **Script** | ADWs, automation | `adw_plan.py` |
| **Terminal REPL** | Interactive tools | Calculator agent |
| **Backend API** | UI integration | Web copywriter |
| **Data Stream** | Real-time processing | Social monitoring |
| **Multi-Agent** | Complex workflows | Micro SDLC |

## Script Deployment

Single execution, one-off tasks.

```python
async def main():
    options = ClaudeAgentOptions(
        system_prompt=load_system_prompt(),
        model="claude-sonnet-4-20250514",
    )

    async for message in query(prompt=task_prompt, options=options):
        if isinstance(message, ResultMessage):
            print(f"Cost: ${message.total_cost_usd:.6f}")

if __name__ == "__main__":
    asyncio.run(main())
```markdown

**Run**: `python agent.py "task description"`

## Terminal REPL Deployment

Interactive conversation with session continuity.

```python
async def run_repl():
    session_id = None
    total_cost = 0.0

    while True:
        user_input = input("Agent> ")
        if user_input.lower() in ["quit", "exit"]:
            break

        options = ClaudeAgentOptions(
            system_prompt=system_prompt,
            model="claude-sonnet-4-20250514",
            resume=session_id,  # Maintain conversation
        )

        async with ClaudeSDKClient(options=options) as client:
            await client.query(user_input)

            async for message in client.receive_response():
                if isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            print(block.text)

                elif isinstance(message, ResultMessage):
                    session_id = message.session_id  # Capture for next
                    total_cost += message.total_cost_usd

        print(f"[Session: {session_id[:8]}... | Cost: ${total_cost:.4f}]")
```markdown

## Backend API Deployment

Agent as API endpoint for UI integration.

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class AgentRequest(BaseModel):
    prompt: str
    session_id: Optional[str] = None

@app.post("/agent/query")
async def query_agent(request: AgentRequest):
    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        model="claude-sonnet-4-20250514",
        resume=request.session_id,
    )

    response_text = ""
    new_session_id = None

    async with ClaudeSDKClient(options=options) as client:
        await client.query(request.prompt)

        async for message in client.receive_response():
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        response_text += block.text

            elif isinstance(message, ResultMessage):
                new_session_id = message.session_id

    return {
        "response": response_text,
        "session_id": new_session_id,
    }
```markdown

## Data Stream Deployment

Real-time processing of incoming data.

```python
async def process_stream():
    options = ClaudeAgentOptions(
        system_prompt=stream_system_prompt,
        model="claude-3-5-haiku-20241022",  # Fast for real-time
    )

    async for data in data_stream():  # Your data source
        # Create analysis prompt
        prompt = f"Analyze this data: {data}"

        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        if "important" in block.text.lower():
                            await notify(block.text)
```markdown

## Multi-Agent Deployment

Orchestrating multiple specialized agents.

```python
async def run_workflow(task):
    # Stage 1: Planning
    planner_result = await run_planner_agent(task)

    # Stage 2: Execution
    builder_result = await run_builder_agent(planner_result.plan)

    # Stage 3: Review
    review_result = await run_reviewer_agent(
        planner_result.plan,
        builder_result.output
    )

    return WorkflowResult(
        plan=planner_result,
        build=builder_result,
        review=review_result,
    )

async def run_planner_agent(task):
    options = ClaudeAgentOptions(
        system_prompt=load_prompt("planner_system.md"),
        model="claude-sonnet-4-20250514",
        hooks={"PreToolUse": [planner_write_hook]},  # Constrain writes
    )
    # Execute and return

async def run_builder_agent(plan):
    options = ClaudeAgentOptions(
        system_prompt=load_prompt("builder_system.md"),
        model="claude-sonnet-4-20250514",
        permission_mode="auto",  # Let builder work
    )
    # Execute and return

async def run_reviewer_agent(plan, implementation):
    options = ClaudeAgentOptions(
        append_system_prompt=load_prompt("reviewer_append.md"),
        model="claude-sonnet-4-20250514",
    )
    # Execute and return
```markdown

## Session Management Pattern

```python
class AgentSession:
    def __init__(self, system_prompt: str, model: str):
        self.system_prompt = system_prompt
        self.model = model
        self.session_id = None
        self.total_cost = 0.0

    def _get_options(self):
        return ClaudeAgentOptions(
            system_prompt=self.system_prompt,
            model=self.model,
            resume=self.session_id,
        )

    async def query(self, prompt: str) -> str:
        response_text = ""

        async with ClaudeSDKClient(options=self._get_options()) as client:
            await client.query(prompt)

            async for message in client.receive_response():
                if isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            response_text += block.text

                elif isinstance(message, ResultMessage):
                    self.session_id = message.session_id
                    self.total_cost += message.total_cost_usd

        return response_text
```markdown

## Cost Tracking Pattern

```python
class CostTracker:
    def __init__(self):
        self.queries = []
        self.total_cost = 0.0

    def record(self, result_message: ResultMessage):
        self.queries.append({
            "session_id": result_message.session_id,
            "cost": result_message.total_cost_usd,
            "duration_ms": result_message.duration_ms,
            "timestamp": datetime.now().isoformat(),
        })
        self.total_cost += result_message.total_cost_usd

    def report(self):
        return {
            "total_queries": len(self.queries),
            "total_cost": self.total_cost,
            "average_cost": self.total_cost / len(self.queries) if self.queries else 0,
        }
```markdown

## Deployment Decision Framework

| Need | Deployment Form |
| ------ | ----------------- |
| One-off automation | Script |
| Interactive tool | Terminal REPL |
| Web application | Backend API |
| Real-time monitoring | Data Stream |
| Complex workflow | Multi-Agent |

## Key Insight

> "Deploy agents in scripts, data streams, terminals, and UIs. Think about repeat workflows that benefit from agents."

## Cross-References

- @agent-evolution-path.md - When to build custom agents
- @piter-framework.md - ADW automation patterns
- @custom-agent-design skill - Design workflow
