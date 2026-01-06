## Bitic Contract

This repository contains a single Clarity smart contract in `contracts/bitic.clar` that provides a basic quadratic funding scaffold with project registration, donation accounting, and a matching pool.

### Features

- Project registry with owner and active status.
- Per-project stats: total donations, sum of square roots, donor count, and matching claimed.
- Per-donor contribution tracking per project.
- Matching pool funding and per-project claim with proportional weight.
- Integer square root helper used to update quadratic funding weights.

### Contract State

Data vars:
- `next-project-id` (uint): auto-incrementing project ID counter.
- `matching-pool` (uint): total funded matching pool available to claim.

Maps:
- `projects { id } -> { owner, active }`
- `project-stats { id } -> { total-donations, sqrt-sum, donor-count, matching-claimed }`
- `donor-stats { id, donor } -> { amount }`

### Public Functions

- `create-project`: creates a new project owned by the caller and returns its ID.
- `set-project-active (project-id, active)`: owner-only toggle of project active status.
- `donate (project-id, amount)`: transfers STX into the contract and updates project/donor stats.
- `fund-matching (amount)`: adds STX to the matching pool.
- `claim-matching (project-id, round-pool, total-weight)`: owner-only claim using the project weight `(sqrt-sum)^2` and provided round totals.

### Read-Only Functions

- `get-project (project-id)`
- `get-project-stats (project-id)`
- `get-donor-stats (project-id, donor)`
- `get-matching-pool`
- `get-project-weight (project-id)`

### Errors

Error constants are defined for common failure cases:
`err-amount-zero`, `err-project-not-found`, `err-project-inactive`, `err-not-owner`,
`err-total-weight-zero`, `err-nothing-to-claim`, `err-insufficient-pool`.
