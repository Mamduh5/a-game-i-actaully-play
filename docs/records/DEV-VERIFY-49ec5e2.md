# Detached candidate composition

Codex verified detached commit `49ec5e2bf7c3137dc7bde15ea0f8aec6689a79eb` with tree `5e224322c630a49d2c62915f6db621be73c4d67c`. Start from `aa090423d878c48e7302398fa8f22831b8cdfd86` and apply `991448c`, `d4e537a`, `05df3d6`, `3d38731`, `ad3fd98`, `c12580e` and `23879b8` in that order. This covers C01 and WP18 corrections, the C24 object checkpoint, WP21 personal progression and purchases, and the WP23 clock and purchase cases. The separate WP25 native framing work is outside this composition.

- Cold import on pinned Windows Godot `4.7.stable.official.5b4e0cb0f` passed in a separate worktree with isolated profile and cache paths and `GODOT_MCP_RUNTIME=off`. `tools/run_gut.ps1` discovered and passed **280/280 tests, 8,076 assertions**.
- The first export exposed the lack of installed release templates in the isolated profile. Copying the two already installed pinned Windows x86-64 templates into that profile allowed export without changing a repository setting or the shared editor.
- The 225-file Windows Player pack contained the app entry, object catalog and profile scripts. Pack inspection excluded tests, fixtures, GUT and MCP and found no MCP autoload. Headless native boot returned `flavor=player` and `renderer=gl_compatibility` with test and development flags absent.
- This is a compatibility witness for the exact composition. The writer candidates remain in their original review branches, and each package retains its independent review and project-specific acceptance obligations. The export is a local verification artifact.

| File under `.qa-evidence/dev-composition/49ec5e2/` | SHA-256 |
|---|---|
| `import.log` | `38345d5c88a4ef4e82280bc08990830f224ed0d6875a2c5f14c63ecc18b37d74` |
| `gut.xml` | `47446898c007e70ee84e67c8883aecf38bf22b9b5da644ea2f3e79293675f967` |
| `player-pack.txt` | `c5de82e12d35c9caa3e5c11f006ec21c9278c6dc0d07fe5e0319cdc9bc15a249` |
| `export-final.log` | `fc23e52ce9f9571563582a64975649944fdf4ba25cde9f0f13bf00985de4e7e6` |
| `boot.log` | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
