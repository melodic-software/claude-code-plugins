# Release checklist

## Branches

Push every release commit to a `release/<version>` branch and merge it through a pull request.

## Tagging

Push release commits straight to `main`; release work never goes through a pull request.

## Formatting

Run the formatter on every changed file before committing. Skip the formatter for files under
`vendor/`, which mirror an upstream project byte for byte.
