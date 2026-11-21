---
bump: patch
---

### Changed

- **The four `/code-tidying:tidy` lane templates no longer suggest one stack's tools.** The dependency-root, polyglot-services, apps and host-wiring templates drop their .NET, JavaScript, Python and Rust examples: the `.Tests` scope globs, the TypeScript and Python service examples, the `dotnet`, `npm`, `cargo`, biome, ruff and pytest command examples, the ruff and biome rule names, the Promise and `os.path` idiom examples, the `.razor` and `components` UI globs and the C#-flavored "extension method" wording. Each placeholder is still there for you to fill with your own repository's paths and commands ([#17760](https://github.com/melodic-software/claude-code-plugins/issues/17760)).
