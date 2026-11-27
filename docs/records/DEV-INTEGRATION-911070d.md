# Integrated live defeat and early Observatory entry

Codex integrated the independently approved live defeat and PR04 early Observatory checkpoints on `dev` from `c73ec738ef49d6ff42bd7d9c624bce8719e47f94`. [WP23 independent review](WP23-terminal-review.md#independent-live-defeat-terminal-settlement-review-381cce4) · [WP25 independent review](WP25-early-review.md#independent-early-observatory-gateway-review-e96da91)

- `03c5626da5f4e85ec40b4d70f0c338bd35f529e9` merged `work/wp23-terminal` at `4c2ee8b515ede716c76bd8d5076d959bbc7e0e48`, including approved `381cce4b5117733c43243ca184f0a8c2fb438ce6`. The WP23 record retains both the earlier integration pointer with its references and the complete writer evidence.
- `911070d686fe5e052ae94f10c583ca2927b9c038` merged `work/wp25-early` at `84e0ad57c08e608eedf96ee391733ad66d4739a9`, including approved `e96da916e46dbcdb51fccf8e5bee29463bf02fc2`. The one code conflict was `RunAuthority.accepted_interaction()`. The staged blob matched the independently reviewed composition's reconciled authority exactly. It retains the terminal earnings fence, public interaction method and payload validation. Both review branch tips remain available.

## Integrated verification

Exact archive `911070d` passed cold import and **351/351 GUT with 14,324 assertions** on Godot `4.7.stable.official.5b4e0cb0f`, the 239-file Windows Player exclusion audit and isolated boot. Use the pinned import and GUT scripts with isolated profile directories and MCP runtime off. In disposable Windows Dev exports, repeat the existing fixture instructions below.

- Both money and closing-marker fault arms in `wp23_terminal_defeat_probe.tscn` held tick 3 until durable settlement in headless and rendered play. Four separate native reads found balance 7, generation 3 and a clear marker. The orderly suspension fixture made its one refused write, preserved its frontier, and cold-reopened balance 17 at generation 1. [Live defeat reproduction](WP23.md#live-defeat-settlement-review-handoff)
- In the seed-3 `wp25_early_observatory_probe.tscn` run, 18 routed inputs and four conduit turns produced early entry on tick 169 in epoch 2. Headless and rendered receipts matched the approved route. The ordinary gateway and optional native passage receipts matched the existing digests. The approved WP32 peer presets also passed. [Early Observatory reproduction](WP25.md#early-observatory-review-handoff)
- WP23 remains open for active-group storage resumption, live victory entitlements, guest reconciliation and playable composition. WP25 remains open for authored arena outcomes and playable composition. WP24, WP26, WP28 and C26 remain gated by their respective prerequisites.

| File under `.qa-evidence/dev-integration/911070d/` | SHA-256 |
|---|---|
| `gut.xml` | `2d2ea289b651e7fbc21de787845b5e6fae68a1220681ae236b76523c6137dd2e` |
| `player-manifest.txt` | `d74e4b3c7a2e0ccd23185752f3d9d73b18aa11282b3b8d5a49c91d7195695e1f` |
| `player-boot.log` | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
| `wp23_terminal_defeat_probe/money-rendered/runtime.log` | `f76fbc4e05f0aea0cefa9ebb071f3abb932addbf847270eebe70c23432849784` |
| `wp23_terminal_defeat_probe/marker-rendered/runtime.log` | `0a73d6e6b78538ed8fbd46e686a67850cd633a042a6555f2cec49c7cd87fb94e` |
| `wp23_terminal_defeat_probe/money-rendered/readback.log` and `marker-rendered/readback.log` | `4892728cee1868fbcae5209f39fbaa6e95f903e1478aca5e4976889ae0a9a34b` |
| `wp23_orderly_quit/suspend.log` | `9a3e0c478fca25337a1d5b72b985204e1c80984fbe87a3d6ec16d27c693737c5` |
| `wp25_early_observatory_probe/headless/runtime.log` | `61dfaac0ca2293b52a2491618e186b5d6b357f3e93f8aabad3a1ace5f7356dcf` |
| `wp25_early_observatory_probe/rendered/runtime.log` | `2a742f3b021b2ce631c53d5374d469bb003f830bd3d92dd88a36fe1adca87e02` |
| `wp25_native_gateway_probe/verify/receipt.json` | `0b46c7d512d653d0d83c250048719aa0f55c34a3502c2126d8f29f226d42072c` |
| `wp25_native_passage_probe/verify/receipt.json` | `ce895413f234767016186fde8126aec474101fe4405d0eea925b77932beff586` |
| `wp32_peer_encounter/verify/receipt.json` | `7eac56fe5fe45eee0df1e9f5f86f8d911313ef2f65fd6ec7e3f6299d1a27557e` |
