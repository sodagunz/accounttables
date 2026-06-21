---
name: verify-work
description: Before committing or submitting your work, you should always verify it using the falke available methods
disable-model-invocation: false
---

Always verify your changes pass tests, lints and formatters.
Use the flake provided methods that are described in AGENTS.md.
For example, always run `nix run .#review` and `nix run .#format` to ensure formatting and best language practices pass.
