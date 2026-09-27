# Technical Debt Tracker

> Zero-tolerance project: this file should normally be near-empty. It exists to make any
> accepted deferral **visible and costed**, not to make debt routine. Core/foundation
> work is never deferred — it compounds 4–7× to fix later. `/start` reads this file and
> halts new feature work if any critical item is open.

## Active debt

| ID | Item | Deferred | Est. cost to fix | Impact | Critical path? |
|----|------|----------|------------------|--------|----------------|
| TD-001 | none — keep it that way | — | — | — | — |

## Deferral decision (fill in before accepting any deferral)

- **Item:** <what>
- **Is it core / user-facing / a foundation others build on?** If yes → **do not defer.**
- **Features that will be built on top:** <0–1 low risk · 2–5 document · 5+ high risk>
- **Cost now vs later:** <Nh now> vs <~Nh × (1 + 0.5 × phases_on_top) later>
- **Justification & mitigation:** <why, and how the risk is contained>

## Resolved debt (evidence required — never "tests pass" alone)

| ID | Resolved | Evidence (fix + verified-working check + no TODO left) |
|----|----------|--------------------------------------------------------|
| | | |
