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

## Independent compound-impact and momentum review (3f7a224 / e9963cc)

- **Target:** Isolated branch `work/c24`, commits `3f7a224df9fe055182829134a231dde46c01f308` (single kinetic debit per mover and compound creature, base `2b2243d`) and `e9963ccc7eefc33f62ed2511000428200ad94129` (single isolated-pair normal impulse transfer into a compound receiver, base `2d05b52`), writer handoff `85a87064deeec57a1092835879a9470e3d5a1104:docs/records/C24.md`.
- **Reviewer / verdict:** Antigravity/Gemini — **CHECKPOINT APPROVED** (**`C24-O2` CLOSED**; **`C24-O1` RETRACTED / CLOSED** — direct inspection of `2b2243d:docs/records/C24.md` confirmed the branch record already carried the intact 64-character SHA-256 `025eba707f72f045562d86b84066ac9fcd04f263343a7b79e8803cd5f2b752bd`; the 61-character string in the prior review note was a reviewer transcription error). Package `C24` remains **`IN PROGRESS`** on `work/c24` pending elongated Fallen Pillar footprints, authoritative creature damage/control consumers, finite pickup/shrine consumers, and integration onto `dev` (`C25` and `C26` remain gated).
- **Verified evidence:** All 10 writer SHA-256 digests under `.qa-evidence/C24/{kinetic-draft,3f7a224,composition-1071e6b-3f7a224,compound-momentum-before,e9963cc,composition-f621356-e9963cc}/` verified verbatim on disk. Independent negative counterexample (`2b2243d` + `e9963cc:tests/unit/test_world_objects.gd`) reproduced 2 failing test cases before the fixes. Clean-archive verification at `work/c24` `e9963cc` under pinned Godot `4.7.stable.official.5b4e0cb0f` (`GODOT_MCP_RUNTIME=off`, isolated `APPDATA`/`LOCALAPPDATA`) passed cold import, **273/273 GUT tests (7,909 assertions, 0 failures)**, and headless `c24_object_probe.tscn` (`warning` tick 2 / neutral `contact` tick 38). Overlaying `src/world/objects/` and `tests/unit/test_world_objects.gd{,.uid}` from `e9963cc` onto a clean archive of `dev` `eed905e` passed cold import and **342/342 GUT tests (11,469 assertions, 0 failures)**.
- **Independent adversarial probe (`C24-review-r2/adversarial-probe.log`, 59/59 checks passed, 0 failures):**
  - Confirmed unequal-strength contacts at an exact common instant (glancing slot `0` vs head-on slot `1`) select stronger slot `1` for BOTH isolated-pair momentum transfer (`pure +x` velocity) and single `CreatureImpact` debit across both shape registration orders (`[0, 1]` / `[1, 0]`) and both collision submission orders.
  - Confirmed two distinct movers (`boulder_a`, `boulder_b`) hitting one creature at the same instant emit 2 `CreatureImpact` entries in canonical sorted mover order regardless of submission order.
  - Confirmed simultaneous structure (`loose_crate`) + compound creature contact blocks isolated-pair momentum transfer (`transferred=false`, `vel=0`) while still posting 1 creature kinetic debit (`shape=0`).
  - Confirmed resting-contact latch suppresses repeat impact without separation and re-enables single debit + momentum transfer after separation and genuine re-strike.

| File under `.qa-evidence/C24-review-r2/` | SHA-256 |
|---|---|
| `import.log` | `b3c8614856450da253e50a81ac0b80644a6dff9043b6bb683f4ab6155584a093` |
| `gut.xml` | `99161c542cc418b6f3efe3a07c6f968dca9b09b6ad02bf1089ab30d6ede0d01f` |
| `headless/runtime.log` | `c11e6a6b8e373c04ef1eb52a1c610b4134e8f9ba2f029e9439ef73972d3c50d1` |
| `overlay-eed905e-gut.xml` | `ee3e4248b57dc6a96264e9f5ce6858c803507a3779319b8467fc01383a8c38c8` |
| `adversarial-probe.log` | `ef61beb6c6ced6172eaaf4cbdf88c60f2a379ec6c571bb4b57ffe25884034672` |

## Writer compatibility retest on af6052f

Codex overlaid the approved C24 object scope from `85a87064deeec57a1092835879a9470e3d5a1104` on a disposable clean `dev` archive of `af6052f523da4b6351bcd7d227b6d369f456b414`. The overlay contained `src/world/objects/`, `tests/unit/test_world_objects.gd` with its UID, and `dev/fixtures/c24_object_probe.{gd,gd.uid,tscn}`. The check covers compatibility with the newer settlement, realm and capsule changes. C24 stays isolated on `work/c24` pending an elongated footprint, authoritative creature impacts and finite pickup consumers.

- Pinned Godot `4.7.stable.official.5b4e0cb0f` with isolated storage and MCP off passed cold import and **375/375 GUT with 16,077 assertions**, including all 14 C24 tests. The 249-file Windows Player pack included the object catalog and field script, passed development-file exclusions and booted in an isolated profile.
- The disposable Windows Dev collapse fixture preserved the tick 2 warning and the single neutral `collapse_fault` contact on the arriving creature at tick 38. The two modes matched logical receipts. The rendered `960×540` captures are byte-identical to the reviewed C24 capture references. The capture command uses `c24_object_probe.tscn` as the disposable entry scene, `--fixed-fps 60`, and `-- <existing-capture-directory>` in both modes. The verdict line starts `C24_COLLAPSE`.
- A reviewer can reproduce from the two exact sources with the scoped overlay and repeat the collapse and momentum checks. The original compound-impact verdict remains recorded above. Production integration, C25 and C26 retain their package prerequisites.

| File under `.qa-evidence/C24/composition-af6052f-85a8706/` | SHA-256 |
|---|---|
| `c24.tar` | `a531056f3889acf82c3ca055e8307e6e9a50fa422bbee480ef1df5cdb2616e00` |
| `gut.xml` | `8fc432b297eb838586b842e38eeba3efcc0dda7c1bac09f701dc48d6ccea7dd8` |
| `player-manifest.txt` | `6506db2848339a94cd699a9b2742413c37f7944926b00b4b7c6baa6904147146` |
| `player-boot.log` | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
| `headless/runtime.log` | `a5d6af0c37f010c24889d2fabc44c1cc92b7e452b3ed2a5162c93abe349ddd14` |
| `rendered/runtime.log` | `a40eb3ec48873718eae3c3b53202b9053a0bc13da25c358140b8b95f5c1a6648` |
| `rendered/collapse-5.png` | `4cef26181aff1a3c734d81eefc17b9ac582cc85dc04d0f141d5b86dc5e507f01` |
| `rendered/collapse-33.png` | `3b21703ed84dcd11965c941358bac0724db393e3bc6b16b51175292f996b8c12` |
| `rendered/collapse-40.png` | `35144d64d5358c5583fce5797cc737015694125e1cf28c9f17236a6dea99d84a` |
