# C24 · World objects, hazards and terrain interactions — Independent Checkpoint Review

- **Target:** Isolated branch `work/c24`, implementation commit `ffdf7c5f02e9b570ebabac47e0445221af2d3b4d`, writer handoff `2b2243d362a6df110f247693287d4af2ca7e46ac:docs/records/C24.md`. Stored in a dedicated review record on `dev` to avoid an add/add conflict when `work/c24` integrates.
- **Reviewer / verdict:** Antigravity/Gemini — **CHECKPOINT APPROVED** (`C24` remains **`IN PROGRESS`** on `work/c24`; `C25` and `C26` remain gated pending elongated/capsule footprints, authoritative creature damage/control consumers, finite pickup/shrine consumers, and integration onto `dev`).
- **Sources:** [C24](../IMPLEMENTATION_PLAN.md#c24), [GDS §16](../GDS.md#gds-environment), [TDS §§2, 4](../TDS.md#tds-world), [QAS QA24–25 and QA51](../QAS.md#qas-scenarios).

## Verification summary

- **Writer evidence check:** All 10 current `ffdf7c5` SHA-256 digests under `C24/ffdf7c5/` (in the isolated `agip-c24-development` worktree `.qa-evidence/`) verified verbatim on disk. Visual inspection of `collapse-5.png` and `collapse-40.png` confirmed clear Collapse visual progression and readable object silhouettes with zero errors.
- **Independent clean-archive verification (`work/c24` `ffdf7c5`):** Under pinned Godot `4.7.stable.official.5b4e0cb0f` (`GODOT_MCP_RUNTIME=off`, isolated `APPDATA`/`LOCALAPPDATA`), cold import and GUT passed **271/271 tests (7,880 assertions, 0 failures)**; disposable release `Windows Dev` export with `res://dev/fixtures/c24_object_probe.tscn` matched writer `runtime.log` (`a40eb3ec...`), `collapse-5.png` (`4cef2618...`), `collapse-33.png` (`3b21703e...`), and `collapse-40.png` (`35144d64...`) byte-for-byte.
- **Independent isolated overlay onto `dev` `4beafbb`:** Overlaying only `src/world/objects/` and `tests/unit/test_world_objects.gd{,.uid}` from `ffdf7c5` onto a clean archive of `dev` `4beafbb` passed cold import and **331/331 GUT tests (11,008 assertions, 0 failures)**, confirming forward compatibility with current `dev`.
- **Independent adversarial probe (`C24-review/adversarial-probe.log`, 76/76 checks passed, 0 failures):**
  - Verified all 12 base and 10 regional object profiles compile cleanly and enforce valid/invalid admission, immutability, finite pickup consumption, destructible thresholds, Collapse hazard progression, and route-blocking rollback.
  - Confirmed `WorldObjectField` compound reaction contact selection canonically selects the lowest unobstructed certified `(entity, shape)` across reversed shape registration (`[0, 1]` vs `[1, 0]`) and skips a cover-blocked slot `0` to select clear slot `1` in both registration orders.
  - Confirmed movable object collision credit, kinetic-energy bounds, and resting-contact separation latch.

## Non-blocking observations

- **`C24-O1` (Low — Historical digest transcription typo in `work/c24:docs/records/C24.md`):** The historical entry for `C24/ad3fd98/gut.xml` in `2b2243d:docs/records/C24.md` has 61 hex characters (`025eba707f2f045562d864066ac9fcd04f263343a7b79e8803cd5f2b752bd`); the actual 64-character SHA-256 on disk is `025eba707f72f045562d86b84066ac9fcd04f263343a7b79e8803cd5f2b752bd`. All 10 current `ffdf7c5` hashes match 100%. Correct the historical digest string on the next update to `work/c24:docs/records/C24.md`.
- **`C24-O2` (Low — Multi-shape compound creature impact deduplication):** `WorldObjectField._gather_collision()` (`src/world/objects/world_object_field.gd:290-310`) deduplicates kinetic impacts by `(mover, target.entity, target.shape)`. A movable object colliding simultaneously with two sub-shapes of a compound creature emits two `CreatureImpact` entries for the same creature in one sweep; deduplicate per `(mover, entity)` (keeping canonical earliest/strongest impact) when wiring authoritative creature damage and control consumers.

## Independent evidence

| File under `.qa-evidence/C24-review/` | SHA-256 |
|---|---|
| `import.log` | `15158b54ea63afc43dc9c750b5e7891424a9cd6a0d6174240f4ca83570c99fbd` |
| `gut.xml` | `97c52913386b94b3e49acac87689ac85a6daf2fca57342ff6a44e66f45b88a5d` |
| `adversarial-probe.log` | `8ca1da858b3b50b88f05399a49a5ed11d8f6ca73bb4b0a6881ea06592e6cf123` |
| `release/runtime.log` | `a40eb3ec48873718eae3c3b53202b9053a0bc13da25c358140b8b95f5c1a6648` |
| `release/collapse-5.png` | `4cef26181aff1a3c734d81eefc17b9ac582cc85dc04d0f141d5b86dc5e507f01` |
| `release/collapse-33.png` | `3b21703ed84dcd11965c941358bac0724db393e3bc6b16b51175292f996b8c12` |
| `release/collapse-40.png` | `35144d64d5358c5583fce5797cc737015694125e1cf28c9f17236a6dea99d84a` |
| `overlay-4beafbb-gut.xml` | `0404fe304f8a30898678078c1dd2c7b8d1e97ddc255523d621c4e60620d0e49d` |
