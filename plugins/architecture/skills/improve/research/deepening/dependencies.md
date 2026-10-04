# Dependencies and Seams

A deepening candidate is only safe to merge once its dependencies are known, because they decide how
the merged module will be tested. Terms follow [vocabulary.md](vocabulary.md).

## Dependency categories

Each dependency of a candidate gets one of four labels, and each label settles a single question:
how does a test reach the deepened module? The labels in code font are the values the scan return
and the candidate artifact use.

### In-process (`in-process`)

The test calls the merged module directly. The dependency is logic or state held in memory with no
I/O, so nothing has to be substituted and the candidate can always be deepened, with no adapter.

### Local-substitutable (`local-substitutable`)

The test runs the module against a stand-in the suite starts locally: MinIO for S3, an SMTP catcher
for the mail relay, an embedded copy of the database. A candidate whose dependency has no such
stand-in cannot be deepened this way. The seam stays inside the module, and its external interface
gains no port.

### Remote but owned (`ports-and-adapters`)

The test plugs an in-memory adapter into a **port** the module declares, at the same **seam** where
production plugs in the HTTP, gRPC or queue client for a service your organization runs elsewhere,
such as an internal API or another microservice. All the logic stays in a single deep module, although
part of the work happens over the network. A recommendation in this category names the port
and both adapters, for example: "Declare a `ShippingQuotes` port; tests use a fake held in memory,
production plugs in the HTTP client for the quotes service."

### True external (`mock`)

The test passes the module a mock adapter through an injected port, because the dependency is a
third-party service no one here controls, such as a shipping-rate API or a geocoding provider.

## Rules for seams

- **Count adapters before adding a port.** Production plus test makes two, which justifies the
  port. A port that only production ever uses adds a hop and nothing else.
- **Internal seams stay internal.** Seams that only the module's own tests use, inside the module,
  are never exposed through its external interface.

## Replace, don't layer

When shallow modules are merged behind one deep interface, the test suite moves rather than grows.
The new tests call the deepened interface and check only what a caller could see. Because nothing
they assert depends on internal state, an internal refactor leaves them passing; one that fails on
a refactor is testing behind the interface. With those tests in place, the old unit tests on each
shallow module only repeat that coverage, and are **deleted**.

The rule is not limited to this lens: it applies to any consolidation that moves the test surface
onto a deeper interface. The test doubles at the new seam follow the dependency category above.
