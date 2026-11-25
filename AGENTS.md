# Repository operating guide

Applies to Codex and Google Antigravity throughout this repository. The owner designs the game. Agents operate, debug and verify it during authorized development.

<a id="agents-phase"></a>

## Current authorization

**Technical documentation revision and review only.** The editable files are this guide, `docs/TDS.md` and `docs/QAS.md`. Antigravity's first review returned **REVISE AND REVIEW AGAIN**. The revised architecture requires targeted independent Antigravity review and explicit owner approval. Implementation or implementation planning needs separate authorization. Update this phase entry when the owner changes the mandate.

## Authority and scope

| Question | Governing document |
|---|---|
| What experience and creative direction are intended? | [GDD](docs/GDD.md) |
| Which game rule, content identity, latest revision or unresolved detail applies? | [GDS](docs/GDS.md) |
| How should the approved system be structured? | [TDS and decision status](docs/TDS.md#tds-decisions) |
| What evidence is required and when is the prototype ready? | [QAS](docs/QAS.md) |
| Who acts, reviews, documents and requests approval? | This guide |

Use V42.6/R1 plus the subsequent [owner supplement](docs/TDS.md#tds-owner). OWNER-T01–T03 fix host recovery, prototype network scope and reward durability. OWNER-T04 authorizes documented provisional decisions for genuinely unresolved details. Consult the [prototype register](docs/TDS.md#tds-rules) and [QA triage](docs/QAS.md#qas-triage). Write down the source/open ID, choice, rationale, compatibility, adjustment point, verification and owner-playtest status before relying on a provisional rule. Preserve confirmed mechanics. A private conversation, missing table or tool default cannot serve as the shared decision record.

## Who decides and who writes

- Use **Bounded Autonomous Development**. Codex normally writes and Antigravity independently reviews. When Antigravity writes, Codex independently reviews. Name one primary writer for a shared change, define its file/scope boundary and hand it over explicitly.
- Agents may choose routine internal techniques, refactor, construct tests, fix defects, improve performance within the rules and tune delegated values. They may register an OWNER-T04 provisional rule without polling the owner on every open coefficient.
- Obtain owner approval for changes to confirmed mechanics or approved architecture, product scope, material new third-party runtime dependencies, external services, recurring or additional spending, external network exposure, destructive operations or substantial new human maintenance. Consolidate only genuine decisions with options and consequences. Installing the proposed SQLite binding or exposing a public listener has no authorization in this phase.

## Approved environment

Use Godot **4.7 stable**, typed GDScript, native Windows PC primary, practical browser compatibility and one Git repository with selective Git LFS. Use Godot MCP Toolkit **1.1.2** and Server **1.1.2**, GUT **9.7.1**, and the Godot Debugger and Profiler. Art tools are Krita **5.3.4.1**, Aseprite **1.3.18.6**, ImageMagick **7.1.2-36**, and FFmpeg/FFprobe **8.1**. ChatGPT Images and Gemini are approved for visual references and artwork assistance. Preserve reviewable layered masters, transparency, frame timing, provenance and reproducible import settings. [TDS asset handling](docs/TDS.md#tds-art)

Use the pinned installation and compatible add-ons. Qualify versions, provenance, license, binary/export compatibility and maintenance before a material runtime dependency is adopted. The owner reports both agents verified with disposable projects. Antigravity's `GODOT_MCP_PROJECT_PATH` points to that fixture. During separately authorized production integration use the application's supported configuration mechanism and existing permissions to target the production project. If required access is unavailable, request that specific access. Confirm the project identity and runtime before sending input. Keep MCP local and credentials outside the repository.

## Working on an authorized change

1. Inspect the working tree, relevant files and previous decisions. Read actual callers, scenes, resources, tests and existing behavior before editing. Reproduce a reported failure when feasible. Preserve the owner's uncommitted changes and unrelated functionality.
2. Identify the observable rule and consumers. Use clear typed code, stable IDs and explicit ownership. Reuse verified contact, payment, timing and progression logic. Preserve legitimate powerful combinations and unrelated behavior.
3. Verify proportionately with the pinned CLI, GUT, MCP, Debugger and Profiler. Use MCP for targeted input/inspection, the supervised development-only visible-input pilot for sustained normal play, and labeled fixtures for controlled states. Real-time rendered runs, independent peers and durable receipts support different claims. Reproduce an in-scope defect, correct it and retest the original and opposing cases. [QA evidence modes](docs/QAS.md#qas-modes)
4. Inspect the final diff and untracked files. Read-only status/diff and authorized focused changes are routine. Hard reset, cleaning untracked files, discarding unowned edits, destructive moves/deletions, force-pushing or rewriting shared history require explicit authorization. Preserve other writers' changes. Commit/push only within current authorization. Select Git LFS for justified large binary sources.

**Godot source control.** During authorized project work, version source scenes/resources/scripts/assets, appropriate `.uid` sidecars adjacent to scripts/shaders, source-adjacent `<asset>.import` settings and approved non-secret project/export settings. Preserve UID sidecars on moves. Ignore regenerable `.godot/` including `.godot/imported/`, export binaries, local profiles, credentials, signing material and transient captures. A blanket ignore for `*.uid` or `*.import` would discard source metadata. Verify a clean checkout reimports and resolves original references. [Godot 4.7 import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html) · [Godot UID guidance](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/) · [Godot version control](https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html)

## Review, continuity and reporting

**Shared handoff conventions for subsequent authorized work.** Use one tracked `docs/records/<change-id>.md` per significant change for scope, writer/reviewer, source IDs, decisions/approval, unresolved blockers, reproducible steps, expected/actual verdicts, independent findings and dispositions. Update the owning TDS/QAS register for architectural or provisional-rule changes. Put raw screenshots, clips, logs, profiler captures and sanitized machine-local receipts in `.qa-evidence/<change-id>/`, with that root gitignored when the convention is activated. Record relative filenames, capture conditions and content hashes in the tracked record; include enough small sanitized observations to understand a result after the raw capture is gone. On separate machines, use an authorized evidence transfer and verify hashes. Never assume shared chat history or an absolute path. These are path conventions only in this phase.

**Independent review is required** for significant shared combat, networking/authority, persistence/reward integrity, content eligibility, architecture, security boundaries and prototype readiness claims. The non-writing agent inspects the actual change and evidence, challenges a counterexample or repeats a high-risk case and records findings. The writer addresses findings and links the retest. If independent review has not occurred, record it as pending and withhold the reviewed/ready claim. For the present architecture revision the designated second reviewer is Antigravity.

Agents own routine tests, interactive play, defect reproduction, tooling compatibility and repository maintenance. The owner primarily evaluates gameplay after the full-content prototype meets the [readiness gate](docs/QAS.md#qas-gate). Provide a playable build, concise controls and known limitations at that point. Reserve the owner's time for judgment that changes the product.
