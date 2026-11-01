---
description: "A bare paste of code with no context, where several code-shape forms fit about equally, gets one question listing the forms with the recommended one first, and nothing is rendered yet"
tags: [visualization, visualize, outcome, ambiguity]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A single question offering two to four code-shape forms (such as a call tree, types and signatures, a file tree or pseudocode) with the recommended form listed first, and no rendered tree, diagram or table in the reply."
---

/visualization:visualize

```python
# shipping/rates.py
from dataclasses import dataclass

@dataclass(frozen=True)
class Parcel:
    weight_g: int
    dims_cm: tuple[int, int, int]
    dest_country: str

class RateTable:
    def price(self, parcel: Parcel, service: str) -> int: ...
    def services_for(self, country: str) -> list[str]: ...

# shipping/carriers/base.py
from typing import Protocol

class Carrier(Protocol):
    name: str
    def quote(self, parcel: Parcel) -> int: ...
    def book(self, parcel: Parcel, service: str) -> str: ...

# shipping/carriers/postal.py
class PostalCarrier:
    name = "postal"

    def __init__(self, table: RateTable):
        self.table = table

    def quote(self, parcel: Parcel) -> int:
        return min(self.table.price(parcel, s) for s in self.table.services_for(parcel.dest_country))

    def book(self, parcel: Parcel, service: str) -> str: ...
```
