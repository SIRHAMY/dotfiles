# Change folder

Artifacts for one change from the **hamy-changes** workflow.
PRD → Design → SPEC (map) → tickets (optional) → build.

## Files you may see

**Anchors** *(root)*
- `PRD.md` — problem, jobs, success criteria. Human-owned.
- `L0_REQUIREMENTS.md` *(deep mode)* — engineering requirements spine; source-of-truth. Human-owned, ≤1 screen of bullets.
- `DESIGN.md` *(one-shot mode)* — single-doc design when L0/L1/L2 split is overkill.

**Design projections** *(`design/`, deep mode)*
- `L1_ARCHITECTURE.md` — boxes-and-seams projection of L0.
- `L2_<component>.md` — per-component projection of L0.

**Generated output** *(root, deep mode, on demand)*
- `RFC.md` — readable narrative for senior eng + leadership review, produced by `/publish-rfc`. Read-only by convention.

**Cross-phase spine** *(root, lazy-created)*
- `FINDINGS.md` — codebase research grounding decisions.
- `DECISIONS.md` — A-over-B records with rationale.
- `OPEN_QUESTIONS.md` — live unknowns and un-mitigated risks.

**Plan & build** *(root)*
- `SPEC.md` — the map: milestones, slices, ticket-checkbox refs, slice gates, commit plan.
- `tickets.md` *(optional, single-file mode)* — ticket atoms as sections per ticket.
- `tickets/T-NNN-<slug>.md` *(optional, folder mode)* — exploded per-ticket files for parallel work.
- `RETRO.md` — post-build reflection.

## Reading order
PRD → L0/DESIGN → (L1 → L2) → SPEC → tickets (optional). (RFC generated on demand from L0/L1/L2.)
Skipped phases mean skipped artifacts.

## Source
hamy-changes workflow — see the SKILL definition for full conventions.
