# WP23 independent review: active encounter storage wait and gameplay earnings (3f47dab / b5418b6)

- **Reviewer / verdict:** Antigravity/Gemini — **CHECKPOINT APPROVED** on `dev` commits `3f47dab31f10858eb48b208f729cb71872b88687` (active encounter storage wait, base `beee675`, handoff `3424cef`) and `b5418b6600b0aa358770ff34832c2d6e4c1d4c68` (gameplay ordinary-currency earnings producer, base `debe8ff`, handoff in [WP23.md](WP23.md#gameplay-earnings-review-handoff)), verified together at clean archive `b5418b6`.
- **Scope boundary:** Written as a dedicated review record to avoid colliding with concurrent uncommitted writer work in `docs/records/WP23.md`. Later commit `7478c84` (native solo entry, no review handoff) and uncommitted peer-exchange fixture edits are **outside this review** and remain unreviewed. Package `WP23` remains **`IN PROGRESS`** (playable run assembly, victory entitlements and guest reconciliation remain open; `WP24` and `WP26` stay gated).

## Independent active encounter storage wait review (3f47dab)

- **Audit:** Inspected `RunAuthority.can_open_earning_group()`, `accepted_interaction()`, `WorldActivity.advance()` / `_drain()`, and `StarterEncounter._resolve_tick()` / `_finish_resolved_tick()`. Confirmed an admitted tick stays private (`_closing != null`, `has_unpublished_tick() == true`, `view_for()` / `movement_state()` null, `checkpoint()` / `party_statuses()` empty, `submit()` returning `INACTIVE`, `accepted_interaction()` false) across a 5-second ordinary-currency deadline at either world entry (`active-entry`) or mid-causal-wave (`active-wave`), retaining `_staged_inputs` and the `WorldActivity` cursor so retrying `close_tick()` after SQLite recovery closes the exact same tick once without replaying movement, decisions, or outcomes.
- **Verified evidence:** All 11 writer SHA-256 digests under `.qa-evidence/WP23/3f47dab/` (plus all 11 integrated defeat/PR04 digests in [DEV-INTEGRATION-911070d.md](DEV-INTEGRATION-911070d.md)) matched verbatim on disk. Independent negative base+test counterexample (`58f7cc5` + `3f47dab:tests/unit/test_starter_encounter.gd`) failed `test_active_currency_deadline_holds_input_and_resumes_world_at_the_same_tick` (`1/7` failed). Clean-archive verification of `b5418b6` passed **364/364 GUT (15,994 assertions, 0 failures)**, clean 240-line `Windows Player` export/audit/boot, and `wp23_terminal_defeat_probe.tscn` across `active-entry` (headless), `active-wave` (headless and rendered `960×540`, visually inspected `resumed.png`), and `money` / `marker` regressions, each followed by separate-process cold `read` (`balance=7`, `generation=3`, `clear=true`).
- **Independent adversarial probes (`r7-review/adversarial-probes.log`):**
  - `ADV_WP23_READS_ZERO_PRESTAGE`: Deadline already expired before `close_tick()` refuses before staging (`has_unpublished_tick() == false`), keeping inputs queued and executing identically once SQLite recovers.
  - `ADV_WP23_ACTIVE_THEN_DEFEAT_SAME_TICK`: Active mid-wave `STORAGE_WAIT` followed on the **same tick** by a lethal strike triggering a terminal defeat closing-marker refusal holds twice without replaying `_activity.advance()` or duplicating eliminations (`elims=1`, `balance=9`, cold reopen `CLEAR`).
  - `ADV_WP23_SUBTICK_PREPLAY_WAIT`: Bow arrow sub-tick `(2, 0.5)` wave hitting `STORAGE_WAIT` during tick-3 pre-decision drain holds player unmoved (`x=62.0`) and foe unhit (`100 HP`) until recovery, then matches an uninterrupted control identically (`76 HP`).

## Independent gameplay ordinary-currency earnings review (b5418b6)

- **Audit:** Inspected `OrdinaryCurrency._accrue_closed_group()`, `RunAuthority._attach_ordinary_currency_batch()` / `_accrue_closed_ordinary()`, `RunEncounterPresence.observe()` / `settle()`, `RunParty.host_seat()`, and `StarterEncounter.bind_enemy_currency()` / `place_enemy()` / `_sample_enemy_earnings()` / `_queue_enemy_earnings()`. Confirmed authored enemy rewards bind per-seat `COMMON_CURRENCY` accounts sharing one issuer store, require an opened ordinary session before opening earning groups, sample moving enemy circles under `PR05` (`200 + radius` margin), issue atomic all-or-nothing closed-group allocations using the authority-checked monotonic clock, leave independent faction kills unclaimed, and key occurrences by original `(realm, enemy_id)` so reanimation and cold replay never double-pay.
- **Verified evidence:** All 8 writer SHA-256 digests under `.qa-evidence/WP23/b5418b6/` matched verbatim on disk. Overlaying `b5418b6:tests/unit/test_starter_encounter.gd` onto `debe8ff` confirmed `StarterEncounter.COMMON_CURRENCY`, `bind_enemy_currency()` and 4-argument `place_enemy()` did not exist prior to `b5418b6`. Clean-archive verification of `b5418b6` passed `wp23_terminal_defeat_probe.tscn` `earned` in both headless and rendered `960×540` modes (visually inspected `waiting.png` and `resumed.png`), accruing `7` from the tick-1 Sword kill, holding tick 3 across SQLite refusal, flushing `7` on recovery, accruing `11` on tick-3 Siphon kill (`18` total, `generation=4`), and passing separate-process cold `read-earned` (`clear=true`).
- **Independent adversarial probes (`r7-review/adversarial-probes.log`):**
  - `ADV_WP23_DEPARTING_AND_BIND_GUARDS`: Seat departing outside the `200 + radius` PR05 margin before elimination earns `0` while the local killer accrues `6`; `bind_enemy_currency()` rejects non-common accounts, mismatched seat keys and foreign issuer stores.
  - `ADV_WP23_MUTUAL_SAME_TICK_KILL`: Mutual same-tick player + enemy elimination in one wave still credits `13` coins and durably flushes them through terminal defeat (`cold CLEAR`).
  - `ADV_WP23_DUAL_KILL_ONE_WAVE`: Single Sword cleave eliminating two authored enemies (`7 + 11`) accrues `18` atomically in one wave.
  - `ADV_WP23_FAR_KILL_ZERO_THEN_REANIMATE_PAYS_ONCE`: Out-of-PR05-range Bow elimination issues `0` and leaves the original entitlement unclaimed, then reanimation plus a nearby elimination pays `9` once.

| File under `.qa-evidence/r7-review/` | SHA-256 |
|---|---|
| `import.log` | `bd6bea96114a93cc646a149de04eef9f13f2932482b48793ebd2a5d98fe67bfa` |
| `gut.xml` | `1b95447cec91ff9c41217b1a8b20d571e0dd244a62969e850f5d12c9b3df8f17` |
| `player-manifest.txt` | `b51295189d1019de81966f6e70b7e33f0b44906bb3d6efcfa7d128a97e794096` |
| `player-boot.log` | `80d555126405d79f1567a7613b6f9f2a99f4c24770caf6d6259f9ec094ca584f` |
| `adversarial-probes.log` | `85ce438dfd33dee81a9f955084ac81c9586b0dc82d6c029faee19c7a140c845a` |
| `negative/wp23_active_58f7cc5/gut.xml` | `9f9b2aa63a78e57caa75ba42db07e4f81955857183ec6628edf317a2fe2eee80` |
| `negative/wp23_earned_debe8ff/gut.log` | `b0b13efcc7dd1e4eb5cb0c755a9db9ad5da6a84674c806c7a2551a03039a382a` |
| `wp23_terminal_defeat_probe/active-entry-headless/runtime.log` | `e4f365db8176d817f15479f12a7e82d4bc2a676b7894261fc5707c717313bc1d` |
| `wp23_terminal_defeat_probe/active-wave-headless/runtime.log` and `wp23_terminal_defeat_probe/active-wave-rendered/runtime.log` | `29c5e33feb2fa27c65fb1598a12f4915b172331ca76542bc35bb2a585687f49b` |
| `wp23_terminal_defeat_probe/active-wave-rendered/resumed.png` | `05f86e22b04207b2af299dc4610fd0abb39c752ed1534ef52f858e4de0a27f7f` |
| `wp23_terminal_defeat_probe/active-wave-rendered/read.log` | `131099210e94b881417540e6ce5a5a6b0cd4be825a0285db06a627898056c69a` |
| `wp23_terminal_defeat_probe/earned-headless/runtime.log` and `wp23_terminal_defeat_probe/earned-rendered/runtime.log` | `ade7fef0f3b4d11d2deca64c00ecddb6d95c4af32b32c7f067b4c4c6a7377fea` |
| `wp23_terminal_defeat_probe/earned-headless/read.log` and `wp23_terminal_defeat_probe/earned-rendered/read.log` | `c6ff71b89c9e6e2e7b65df542bef4688515937fd32d05743616f99bef410c945` |
| `wp23_terminal_defeat_probe/earned-rendered/waiting.png` | `b17944ddf630405a482074232cc404cf5f36aaeb2a4bd3d27071856383c5ab08` |
| `wp23_terminal_defeat_probe/earned-rendered/resumed.png` | `6b315ffbdbd1092eb8eef940da2087e2d5c8f75c3388e2864f2ddba47ad450c7` |
