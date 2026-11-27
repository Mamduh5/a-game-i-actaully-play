# WP25 PR04 Early Observatory Gateway — Independent Review

Tracked separately on `dev` so isolated `work/wp25-early` can integrate without conflicts in [WP25.md](WP25.md).

## Independent early Observatory gateway review (e96da91)

- **Reviewer / verdict:** Antigravity/Gemini — **CHECKPOINT APPROVED** on isolated `work/wp25-early` commit `e96da91902612b17ffbc3ba4e1735a6856736333` (base `eed905e`, handoff `84e0ad5:docs/records/WP25.md`). Package `WP25` remains **`IN PROGRESS`** pending authored final-arena outcomes and playable run composition (`WP28` and `C26` remain gated).
- **Verified writer & clean-archive evidence:**
  - All 10 writer SHA-256 digests under `.qa-evidence/WP25/` referenced in `84e0ad5:docs/records/WP25.md` verified verbatim on disk.
  - Independent clean-archive verification of `e96da91` under pinned Godot `4.7.stable.official.5b4e0cb0f` (`GODOT_MCP_RUNTIME=off`, isolated `APPDATA`/`LOCALAPPDATA`) passed cold import, **331/331 GUT tests (11,397 assertions, 0 failures/errors)**, and clean 238-file `Windows Player` export/boot (`AGIP_BOOT` clean, zero dev/test/MCP leaks).
  - Independent negative counterexample (`eed905e` base + `e96da91:tests/unit/test_run_final_gateway.gd`) rejected loading the new test suite on the unpatched base (`Parse Error` / missing `RunObservatoryGateway`).
  - Disposable `Windows Dev` export of `dev/fixtures/wp25_early_observatory_probe.tscn` with seed `3` passed both headless and rendered `960×540` runs identically (`aligned = true`, `clue = true`, `crossed = true`, `entry_tick = 169`, `epoch = 2`, `turns = 4`, `input_sequence = 18`). Visually inspected our rendered `clue.png` (inscription and two north-facing conduits), `aligned.png` (conduits facing each other with purple gateway ring revealed), and `arena.png` (`Unfinished Canvas` final arena arrival).
  - Independent coexistence composition with `dev` `35b156f` and `work/wp23-terminal` `381cce4` (using reconciled `.qa-evidence/WP23/live-defeat-composition/run_authority.gd`) passed cold import and **351/351 GUT tests (14,322 assertions, 0 failures/errors)**.
- **Independent adversarial probe (`WP25-early-review-r6/adversarial-probe.json`):**
  - 1,000-seed PR04 distribution scan (`0..999`): `496` overworld layouts contained `silent_observatory`, `70` of those qualified for early access (`0.1411`, consistent with 1-in-8 independent stream `pr04_observatory_gateway`), and `0` layouts lacking `silent_observatory` qualified.
  - Refusal & security boundaries: duplicate exclusive `RunObservatoryGateway.register()` refused; misaligned gate entry refused; duplicate same-tick conduit turn receipt refused; post-alignment turn refused; dynamic line-of-sight wall hides `GATE` from `view_for()` and refuses `enter()`; blocked arena arrival refuses `enter()` without mutating epoch or realms.
  - Crossed-checkpoint tamper resistance (`gw_res = ENTERED`, `early_tick = 5`): `RunAuthority.restore()` rejected `early_gateway_tick = 0`, `early_gateway_tick = COLLAPSE_TICK`, string-typed `early_gateway_tick`, epoch-1 checkpoint carrying `early_gateway_tick`, and `RunObservatoryGateway.valid_early_tick()` rejected non-early seeds.

| File under `.qa-evidence/` | SHA-256 |
|---|---|
| `WP25-early-review-r6/import.log` | `6c9f942680e5e92d04da8fbd32c48ffb1448bd7c13ea5fcee77738f77caabf2c` |
| `WP25-early-review-r6/gut.xml` | `4539169ea3251a7e881d57c9751ebaf5816b9ec4dc928fc02411612d4806e6cc` |
| `WP25-early-review-r6/player-manifest.txt` | `8de93fce1fba5b1f6c6fa21b2b5b9e303a958c2febeb6315ddcc25cb89f60477` |
| `WP25-early-review-r6/player-boot.log` | `80d555126405d79f1567a7613b6f9f2a99f4c24770caf6d6259f9ec094ca584f` |
| `WP25-early-review-r6/headless/runtime.log` and `rendered/runtime.log` | `6e23b6b26ab70dbae4900190ab6c994bc039068144b567ddcef9edb96969abed` |
| `WP25-early-review-r6/rendered/clue.png` | `c859a4e843cf4bfb8b6ee9956246bfa772445f6bffb2ccfd1866b351e7006909` |
| `WP25-early-review-r6/rendered/aligned.png` | `d1539aec83671f045fbc5ea8dda3fa7bfedbc99ea18519a5dbc6f4945d580641` |
| `WP25-early-review-r6/rendered/arena.png` | `d684fffb4e3a5e7df5c2bba198fb57dbcc922c25ef6b4467c6dadb55e8d5febe` |
| `WP25-early-review-r6/adversarial-probe.json` | `154c431ed8e39ee2aa81c1eedc60c4e80bdf633f7a219c6f16e561d7650d7933` |
| `coexist-review-r6/gut.xml` | `f73c084d2cdd45faccd077f52df204b55673a0b99b1323c47e387a141d819afb` |
