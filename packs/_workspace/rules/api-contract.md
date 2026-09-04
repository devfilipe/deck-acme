---
paths:
  - "**/openapi.yaml"
  - "**/*.proto"
---

# API contract

The schema is a contract with every client already deployed. Before changing it,
resolve `api_compat` — `deck toggle explain api_compat` says what each value
commits you to.

- Additive changes need no ceremony: new optional fields, new endpoints.
- Renaming or narrowing a field breaks clients at run time. That is `breaking`,
  and it needs a migration note and a version bump.
- Removing something takes two releases: mark it `deprecated`, ship, then remove
  in a later one. Never both in the same change.

Regenerate the client after any schema edit. A schema change that does not reach
`web-client` in the same delivery leaves the two out of step, and the failure
shows up in the end-to-end suite rather than in review.
