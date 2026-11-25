# Repository operating guide

Applies to Codex and Google Antigravity throughout this repository. The owner designs the game. Agents operate, debug and verify it during authorized development.

<a id="agents-phase"></a>

## Current authorization

**Production implementation authorized.** The owner has authorized production implementation of the V42.6/R1 baseline. The final independent architectural review of the six-document snapshot at `f93725ca4d7ce9d3d1846639b5f613fad3ed5fc1` concluded **APPROVE WITH PACKAGE-SPECIFIC QUALIFICATION GATES**. Development follows the [implementation plan](docs/IMPLEMENTATION_PLAN.md#plan-workflow) under Bounded Autonomous Development. Every package-specific qualification gate remains mandatory, including WP04 numeric adoption, WP05 SQLite adoption, WP06 authenticated native transport and WP18 offscreen equivalence.

**Foundation assignment.** The owner assigned [WP01](docs/IMPLEMENTATION_PLAN.md#wp01) to Claude Opus as its primary writer. Antigravity independently reviews WP01 before any downstream package relies on it. After that foundation approval, Codex and Gemini become the normal implementation and review agents under the writer/reviewer rules below.

The mandate covers production setup, game code, tests, assets, pilot work and the approved pinned development dependencies on `dev` as scheduled by the plan. Remote publication, promotion to `main`, external services, spending, material new runtime dependencies and changes to confirmed mechanics or approved architecture keep their existing approval boundaries.

<a id="agents-branches"></a>

## Permanent branch responsibilities

- **Develop on `dev`.** Codex and Antigravity normally implement, refactor, debug, create assets, experiment, run automated and interactive checks, maintain documentation, review, correct findings and integrate internal milestones there. Claim the files or catalog IDs with one writer. Use a temporary branch or worktree only where a concurrent edit or high-risk change needs isolation. Return the verified change to `dev`.
- **Reserve `main` for owner access.** Develop fixes on `dev` first. The owner authorizes local promotion of a verified candidate for a requested demonstration, necessary inspection, playable test, ready prototype or verified response to owner feedback. Package completion, an internal milestone, passing checks, documentation and review by themselves stay on `dev`. Functional prototype art is acceptable for a stated owner-facing purpose.
- **Promote an identified revision.** Record why the owner needs it, the exact candidate and current `main`. Inspect everything the merge would include, including owner edits. If `dev` contains unfinished or incompatible work, continue on `dev` or isolate a suitable candidate and verify that candidate. Complete applicable QAS and required independent reviews, preserve existing `main` behavior and owner changes, merge locally, then build and verify the resulting revision. Record source and promoted SHAs, included changes, evidence, limitations and access instructions. Return to `dev`. [Promotion and handoff](docs/IMPLEMENTATION_PLAN.md#plan-promotion)
- **Publish under existing remote permissions.** A local merge grants no push, destructive operation, force-push or shared-history rewrite permission. If owner access requires a push beyond current permission, report the required remote/branch and local revision. Agents perform routine verification. Substantial owner gameplay evaluation remains primarily after the full-content readiness gate. [Readiness gate](docs/QAS.md#qas-gate)

## Authority and scope

| Question | Governing document |
|---|---|
| What experience and creative direction are intended? | [GDD](docs/GDD.md) |
| Which game rule, content identity, latest revision or unresolved detail applies? | [GDS](docs/GDS.md) |
| How should the approved system be structured? | [TDS and decision status](docs/TDS.md#tds-decisions) |
| What evidence is required and when is the prototype ready? | [QAS](docs/QAS.md) |
| Who acts, reviews, documents and requests approval? | This guide |
| What can run next, who owns it and what closes it? | [Implementation plan and handoff](docs/IMPLEMENTATION_PLAN.md#plan-workflow) |

Use V42.6/R1 with the recorded [owner decisions](docs/GDS.md#gds-owner). Apply the latest explicit owner decision within its stated scope, then the governing document in the table. Consult the [provisional rules](docs/GDS.md#gds-rules) for genuinely open details delegated by OWNER-T04. Record the source/open ID, choice, rationale, compatibility, adjustment point, verification and owner-playtest status. If two documents disagree, correct the derivative document and retest its references. If confirmed requirements themselves conflict, preserve both sources and bring the smallest product decision to the owner. The plan schedules work and the QAS tests it. Neither changes a mechanic, technical approval or authorization phase. [QA triage](docs/QAS.md#qas-triage)

## Who decides and who writes

- Use **Bounded Autonomous Development**. Codex normally writes and Antigravity independently reviews. When Antigravity writes, Codex independently reviews. Name one primary writer for a shared change, define its file/scope boundary and hand it over explicitly.
- Agents may choose routine internal techniques, refactor, construct tests, fix defects, improve performance within the rules and tune delegated values. They may register an OWNER-T04 provisional rule without polling the owner on every open coefficient.
- Obtain owner approval for changes to confirmed mechanics or approved architecture, product scope, material new third-party runtime dependencies, external services, recurring or additional spending, external network exposure, destructive operations or substantial new human maintenance. Consolidate genuine decisions with options and consequences. The named embedded SQLite candidate has conditional owner approval and a qualification gate. A failed gate sends affected work back to technical review. [Storage decision](docs/TDS.md#tds-storage)

## Approved environment

Use Godot **4.7 stable**, typed GDScript and the Compatibility renderer for native Windows, with practical browser compatibility. Keep one Git repository with selective Git LFS. The TDS records the pinned engine, MCP pair, GUT, art/media tools and the conditional SQLite release, including acquisition sources and player-build exclusions. Preserve layered masters, transparency, frame timing, provenance and reproducible imports. [Dependency register](docs/TDS.md#tds-dependencies) · [Asset handling](docs/TDS.md#tds-art)

Use the pinned installation and compatible add-ons. Qualify versions, provenance, license, binary/export compatibility and maintenance before a material runtime dependency is adopted. The owner reports both agents verified with disposable projects. Antigravity's `GODOT_MCP_PROJECT_PATH` points to that fixture. During separately authorized production integration use the application's supported configuration mechanism and existing permissions to target the production project. If required access is unavailable, request that specific access. Confirm the project identity and runtime before sending input. Keep MCP local and credentials outside the repository.

## Working on an authorized change

1. Inspect the working tree, relevant files and previous decisions. Read actual callers, scenes, resources, tests and existing behavior before editing. Reproduce a reported failure when feasible. Preserve the owner's uncommitted changes and unrelated functionality.
2. Identify the observable rule and consumers. Use clear typed code, stable IDs and explicit ownership. Reuse verified contact, payment, timing and progression logic. Preserve legitimate powerful combinations and unrelated behavior.
3. Verify proportionately with the pinned CLI, GUT, MCP, Debugger and Profiler. Use MCP for targeted input/inspection, the supervised development-only visible-input pilot for sustained normal play, and labeled fixtures for controlled states. Real-time rendered runs, independent peers and durable receipts support different claims. Reproduce an in-scope defect, correct it and retest the original and opposing cases. [QA evidence modes](docs/QAS.md#qas-modes)
4. Inspect the final diff and untracked files. Read-only status/diff and authorized focused changes are routine. Hard reset, cleaning untracked files, discarding unowned edits, destructive moves/deletions, force-pushing or rewriting shared history require explicit authorization. Preserve other writers' changes. Commit/push only within current authorization. Select Git LFS for justified large binary sources.

**Godot source control.** During authorized project work, version source scenes/resources/scripts/assets, appropriate `.uid` sidecars adjacent to scripts/shaders, source-adjacent `<asset>.import` settings and approved non-secret project/export settings. Preserve UID sidecars on moves. Ignore regenerable `.godot/` including `.godot/imported/`, export binaries, local profiles, credentials, signing material and transient captures. A blanket ignore for `*.uid` or `*.import` would discard source metadata. Verify a clean checkout reimports and resolves original references. [Godot 4.7 import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html) · [Godot UID guidance](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/) · [Godot version control](https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html)

## Review, continuity and reporting

**Shared handoff conventions for subsequent authorized work.** Use one tracked `docs/records/<change-id>.md` per significant change for scope, writer/reviewer, source IDs, decisions/approval, unresolved blockers, reproducible steps, expected/actual verdicts, independent findings and dispositions. Update the owning GDS, TDS or QAS register when its subject changes. Put raw screenshots, clips, logs, profiler captures and sanitized machine-local receipts in `.qa-evidence/<change-id>/`, with that root gitignored when the convention is activated. Record relative filenames, capture conditions and content hashes in the tracked record. Include enough small sanitized observations to understand a result after the raw capture is gone. On separate machines, use an authorized evidence transfer and verify hashes before recording review. See [branch, status and handoff procedure](docs/IMPLEMENTATION_PLAN.md#plan-workflow). These paths become active during authorized development.

**Independent review is required** for significant shared combat, spatial simulation, numerical correctness, networking/authority, persistence/reward integrity, content eligibility, architecture, security boundaries and prototype readiness claims. The non-writing agent inspects the identified base/head commits and retrievable evidence, challenges a counterexample or repeats a high-risk case and records findings. The writer addresses findings and links the retest. If independent review has not occurred, record it as pending and withhold the reviewed/ready claim. Antigravity/Gemini is the designated reviewer for the combined baseline and plan.

Agents own routine tests, interactive play, defect reproduction, tooling compatibility and repository maintenance. The owner primarily evaluates gameplay after the full-content prototype meets the [readiness gate](docs/QAS.md#qas-gate). Provide a playable build, concise controls and known limitations at that point. Reserve the owner's time for judgment that changes the product.
