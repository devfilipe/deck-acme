---
paths:
  - "**/services/**/*.ts"
---

# Service conventions

- Handlers validate input at the edge. Nothing below the handler re-checks
  shapes; it trusts them.
- Errors carry a stable code. The message is for humans and may change; the code
  is part of the contract and may not.
- Anything that touches the database goes through a migration. `migration_plan`
  decides whether it has to be reversible in phases — check it before writing
  the migration, not after.
