# Quality requirement prompts

Quality requirements, often called non-functional requirements (NFRs), say how well the system
must do what it does. These seven are prompts, not a taxonomy, and the list is `Basis: judgment`:
no primary defines it. Ask only the prompts the task touches, at the depth the quality bar sets
([`loop.md`](loop.md) "Engineering defaults"). A consumer standard that names its own list or
targets wins over this one.

| Prompt | Ask about |
|---|---|
| Performance | response time, throughput and resource use under the expected load |
| Reliability / availability | uptime, what happens when a dependency fails, recovery |
| Security | who may do what, which data is sensitive, what must be audited |
| Maintainability | who changes it next, and what must stay easy to change and test |
| Usability (ISO/IEC 25010:2023 name: interaction capability) | who uses it, how, and with what accessibility needs |
| Scalability (ISO/IEC 25010:2023: part of flexibility) | the growth in users, data or tenants the design must absorb |
| Observability (not an ISO/IEC 25010 characteristic; included by judgment) | what an operator must see to tell it works: logs, metrics, traces, alerts |

Ask for a measurable target (a number, a unit and a condition) only where a wrong guess would
change the design or a check will grade it. Otherwise record the requirement in words; "no target
needed" counts as captured. Stumble: with no slot for quality requirements, agents either skipped
them or invented targets.

Record each answer under the Brief's `### Constraints`, one line per requirement, starting
`Quality requirement:` so it reads apart from true constraints, which are decisions already made
(a mandated language, an untouchable module):

```text
- Quality requirement: <prompt>: <requirement>[; target: <measurable target>]
```

Stumble: the Brief, PRD and plan had no slot for quality requirements, so agents skipped them.

Unattended, a measurable target nobody stated is not `blocked`: record the requirement as above
and the target under `### Captured assumptions` as
`- <prompt> target assumed: <value>: revisit if <trigger>`. Stumble: with no slot for an assumed
target, an unattended agent invented one silently.

- **Pointer**: ISO/IEC 25010:2023, Foreword, "The main changes are as follows"
  (<https://www.iso.org/standard/78176.html>; the Foreword is readable in the preview at
  <https://cdn.standards.iteh.ai/samples/78176/13ff8ea97048443f99318920757df124/ISO-IEC-25010-2023.pdf>).
- **As of**: 2026-10-18
- **Recheck trigger**: ISO publishes an amendment or a new edition of ISO/IEC 25010.
