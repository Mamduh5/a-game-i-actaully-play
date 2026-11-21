# NEW GAME — COMPLETE DESIGN DISCUSSION & MASTER SOURCE OF TRUTH

**Document edition:** V15.1 consolidation  
**Discussion covered:** earliest recorded design / V0.1–V10.x foundations, then each recorded choice from V10.7 through V15.1  
**Last discussion decision:** disconnected living characters count toward party survival only for a limited reconnection grace period  
**Date of consolidation:** 2026-11-22  
**Status:** **DESIGN ONLY — NOT AN IMPLEMENTATION ORDER**  
**Product name:** not finalized; this is the **new game**, distinct from the existing *Jangan Lari* reference project.

> **Why this document exists.** Preserve as much of the accumulated design conversation as available in a durable Markdown file, including the early V0.1–V10 discussion, the detailed V10.7–V15.1 sequence, examples, constraints, and unresolved questions. This is intended to be useful for continuing the conversation without having to reconstruct game rules from many previous messages.
>
> **Reconstruction limitation.** The surviving V0.10 source-of-truth handoff and Combat Foundation V3 handoff document early decisions, and the available conversation summary documents additional V1–V10 developments. A verbatim, turn-by-turn record assigning every early decision to each individual version number V0.1, V0.2, …, V10.6 is **not available**. Consequently the early chapters below reconstruct the **substance** in detail but do **not invent** exact early turn labels, quotes or approval dates. Starting at **V10.7**, the recorded choices can be traced version by version. This is a faithful consolidation, **not a verbatim chat export**.

## Reading rules and precedence

**Status vocabulary:**

- **CONFIRMED** — user explicitly selected this rule, or it is reliably preserved as selected in the early handoffs.
- **DIRECTION** — established design goal or desired feature whose implementation details are still open.
- **PROPOSED / RECOMMENDED** — an assistant example, recommendation, architecture idea or balance suggestion, **not user approval**.
- **ILLUSTRATIVE** — a working name, sample effect, quantity or scenario, not final game content or tuning.
- **OPEN** — not resolved by the discussion; cannot silently be treated as decided.
- **SUPERSEDED** — an old sketch replaced or narrowed by a more recent choice.

**Conflict precedence:** (1) the user's latest explicit decision, (2) earlier explicit decisions, (3) the detailed source-of-truth handoff, (4) the older combat foundation handoff, (5) assistant interpretations and examples. If conflict remains, retain both facts and mark it OPEN rather than choosing without approval.

**Source materials used for early discussion:**

1. `new-game-design-source-of-truth-v0.10.md` — early new-game discussion, dated 2026-11-20. This is the closest written source for the V0.1–V0.10 era.
2. `Jangan-Lari_Combat-Foundation-V3_Design-Handoff.md` — older Combat Foundation V3 study, version 0.3, dated through 2026-11-20. Useful historical context, but some proposals were later superseded.
3. The available conversation's summarized pre-V10.7 decisions and explicit V10.7–V15.1 dialogue.
4. Other provided legacy material (`Project-note.txt`, `io-mobile-alpha-branch-plan.md`, `deep-research-report (1).md`) relates mainly to the **old** Diep.io/Jangan Lari direction. It is **not** treated as current approval for the new game's scope, platform, networking, content or implementation.

---

# PART I — PRODUCT VISION, HISTORY, AND EARLY DISCUSSION (V0.1–V10.x)

## 1. Project identity and history

### 1.1 New product, not a patch to Jangan Lari — CONFIRMED

The owner wants to design a **new game** as its own product and eventually use a **new repository**. The existing *Jangan Lari* repository may offer learning, prototypes, assets, practical lessons or intentionally selected reusable code, but it should remain intact as a reference/experimental project. The new game is not just a branch that quietly replaces existing gameplay. No repository creation, branch operations, implementation, refactoring or Codex task has been authorized by this design conversation.

This distinction arose after experiments with an earlier Phaser/TypeScript mobile-browser game. The accepted recovery work had useful movement and visual improvements, but its projectile-centric weapons and tank-like classes did not produce the desired identity. A manual MOBA-like attack-control experiment proved familiar but tiring when applied to several independently firing weapons. A separate `newsystem/v2` branch had ideas about chassis, ability systems, triggers and build-aware rewards, but its diverged implementation was not suitable for wholesale merging. Those technical observations are **historical**, not proof of the state of any repository today.

Historical pointers, as reported in the old handoff and **not reverified in this session**:

- `io/mobile-assets-recovery` at approximately `f49d2c5`: accepted recovery/mobile improvements.
- `io/moba-attack-controls-prototype` at approximately `ab14381`: experimental manual attack mode; tested as too demanding for the current multiweapon design.
- `newsystem/v2` at approximately `28d1aad`: conceptual ability/chassis/synergy architecture, but diverged and still limited by projectile-heavy execution.

### 1.2 Design method and authority — CONFIRMED

The owner controls the vision and decisions. The conversation is an iterative design interview, not a command to implement each chosen rule. The assistant can propose options, challenge assumptions, expose edge cases, and maintain documentation. Later Codex or other implementation work would need a separate instruction, bounded tasks, test plans, architecture review, and explicit approval.

The game should be treated as one coherent product, not a stack of disconnected AI-made features. Human playtesting, instrumentation, deliberate performance measurement, and periodic architecture audits will be essential when development begins. Do not commit to a particular engine, networking protocol or server topology merely because it is familiar from the previous game.

### 1.3 Why change from the original game direction — CONFIRMED INTENT

The earlier project produced functional arena survival elements but too many attacks looked and behaved like projectile emitters. The owner wants **genuine melee, distinct heroes, distinct weapons, mechanically surprising builds, readable movement-based dodging and memorable encounters**. A weapon should not merely receive more damage/rate/range; it can change geometry, behavior, costs, state interactions and how other powers operate.

The former Diep.io-inspired browser PvP / tank-class concept described in old project notes is **not** the controlling specification for this new PvE/co-op roguelite direction.

## 2. Experience and product fantasy

### 2.1 North star — CONFIRMED

The player should be able to **discover, engineer and play extremely powerful, surprising combat combinations**. The game should feel complex through interacting systems, not difficult because it demands continuous tapping or elaborate manual rune placement. A satisfying run can evolve from humble attacks into huge cleaves, repeated lightning discharges, enormous orbiting blades, resource-fueled spells, high-tempo weapons, shields, sustain loops and spectacular chain reactions.

Desired experiences include:

- "That combat felt amazing; I want another run."
- "That was difficult, but I finally mastered it."
- "I found an interaction I didn't expect, and my build became absurdly powerful."
- "The risk was caused by how I constructed or played my build."

The game may let players create builds that hurt themselves through resource costs. Not every difficult or risky combination should be automatically normalized into safe play. The player should understand the rules and be responsible for deliberate choices.

### 2.2 Creative reference points — INSPIRATION, NOT CONTENT APPROVAL

- **League of Legends: Swarm:** scale of power fantasy; heroes with noticeably different builds; active/passive interplay; maps, enemies, quests and meaningful weapon evolution. Inspirations include speed-to-damage, mobility-to-defense, large appendage/tentacle attacks, major sustain/invisibility/cooldown loops. These are *reference illustrations*, not approved copied mechanics or characters.
- **Jotunnslayer: Hordes of Hel:** hordes, chosen weapons, objectives, events, combat/support variety, and distinctive character traits.
- **Mages of Mystralia:** composition of effects, triggers, conversions and resource loops. **Do not copy** its rune-book, tile/board placement, spell-connection interface or complex manual editing UI.
- **General ARPG / MOBA skill expression:** readable enemy tells, movement-driven survival, true melee positioning, strategic resource use, avoidable dangerous attacks.

### 2.3 Explicit anti-goals — CONFIRMED DIRECTION

1. No new game that is simply a tank with ten different bullets.
2. No mandatory main weapon assigned to a hero.
3. No melee attacks faked as sword-shaped ranged projectiles.
4. No universal dodge button or roll compulsory for everyone.
5. No forced micromanagement of all weapons with separate fire inputs.
6. No rune placement board or manual wiring UI.
7. No generic rune attached separately to each weapon by hand.
8. No rewards that secretly override a fully prepared power pool to force discovery.
9. No automatic acquisition of prepared powers merely because the pool contains them.
10. No replacing acquired powers mid-run as a convenient respec.
11. No indiscriminate proc inheritance that makes all chains fire every possible effect.
12. No artificial prohibition on powerful designed chains merely because they are spectacular.
13. No intentional unavoidable boss attacks, particularly in Hard mode.
14. No MMO or indefinite persistent large-scale shared world as the current co-op scope.
15. No premature implementation decisions disguised as game-design selections.

## 3. Presentation, camera, platforms, and control scheme

### 3.1 Visual identity — CONFIRMED DIRECTION

- **Top-down / oblique top-down**, similar in readability to League of Legends.
- A **2.5D visual impression** built from sprites or related lightweight artwork. Knock-up and stun are mechanically distinct: a launched/airborne character is not merely a stunned character drawn differently.
- Attractive, expressive **hand-drawn pencil/graphite-on-white-paper** art: character sprites, monsters, attacks, environments and UI should feel as though they belong to the same visual language.
- Strong visual separation of players, enemies, hazards, safe zones, melee arcs, status effects and evolving weapon forms, despite the light-on-white style.
- Large VFX should read clearly in chaotic scenes. The style should support high-density enemies and oversized attacks rather than obscuring threats.
- Exact rendering architecture, palette and asset production pipeline are **OPEN**; “2.5D” does not mandate a true 3D engine.

### 3.2 Platforms — DIRECTION

PC is currently the stronger first priority. Browser delivery is acceptable, particularly PC browser. Mobile support is desirable, but the older mobile-browser control experience was uncomfortable. Do not freeze specific PC distribution, Android packaging, engine, browser runtime or frame rate solely on these design discussions. Performance on constrained devices remains an important future test concern.

### 3.3 Player input and movement — CONFIRMED

- **Auto-aim / automatic target acquisition** handles routine offensive targeting.
- Players concentrate on movement, positioning, reading patterns and choosing a build.
- Each hero has **one distinct, fixed, manually triggered hero ability**; that ability does not evolve directly, though cooldowns and interacting traits may alter its use.
- Other weapon attacks and combat abilities can auto-activate when their conditions are satisfied.
- No universal dash/roll button is required. A particular hero's active ability may itself be mobility, a shield, a dash or another tool.
- Dodging relies chiefly on moving out of attack geometry, recognizing telegraphs and exploiting timing/space.
- Precise targeting of certain puzzle/interactable mechanisms can use a **contextual interaction** that directs the *next eligible auto-attack* at the object, after which normal enemy targeting resumes.

### 3.4 Combat readability — CONFIRMED DIRECTION

Different enemy attacks need understandable tells, commitment windows and sensible hit geometry. Knock-up, stun, slow, root, pushback, vulnerability and ordinary damage should remain distinct where designed. A dense battle should feel intense but not random or impossible to parse. Movement should be able to avoid even Hard-mode attacks, though their windows can be demanding.

## 4. Player identity, heroes, weapons, and abilities

### 4.1 Hero / main weapon separation — CONFIRMED

- A hero is chosen before the run; hero identity comes mainly from an innate passive and **one fixed manual active ability**.
- The **main weapon is chosen independently** of the hero. A sword can be used by different heroes; a hero is not locked to a signature weapon.
- Main weapon is build-defining and should have a recognizable cadence, hit geometry, range, sound and eventual transformation.
- Additional universal/secondary weapons or abilities can coexist; they may be melee, orbiting, ranged, area or other formats. A melee-focused hero is not forbidden from ranged supplementary attacks.
- The exact inventory taxonomy of every possible secondary action is still being specified, but acquired Abilities, Traits and Augments count against a unified power capacity (see Part II).

### 4.2 True melee and delivery variety — CONFIRMED

A sword arc should trace an actual short-range sweep/hit area; a spear thrust should have narrow forward reach; a hammer strike should have its own spatial footprint and timing. Melee must not default to a sword icon attached to a distant projectile. Other delivery geometries can include projectiles, arcs, thrusts, orbiting objects, expanding zones, rays, pulses, persistent fields and summons, when designed.

### 4.3 Power classes and their conceptual responsibilities

These labels are useful design responsibilities and **not a fully frozen software class hierarchy**:

| Concept | Gameplay responsibility | Example (illustrative) |
|---|---|---|
| Hero passive | Permanent per-hero rule twist | Mana-paid attack effects consume HP instead |
| Hero fixed manual ability | One hero-specific triggered action | A shield, knock-up or mobility burst |
| Main weapon | Core attack delivery and transformations | Real sword arc with every-third-activation bonus |
| Secondary / universal weapon | Additional attack source | Spinning Blade, electrical coil, orbital blade |
| Ability | Distinct action or combat effect, potentially auto-activated | A spinning strike that inherits main sword properties |
| Global rune | A pre-equipped modifier for all compatible attacks | Bleed application for eligible hits, with mana cost |
| Trait | Persistent conditional behavior | Heal when hitting an already-bleeding enemy |
| Augment | Higher-order mechanical change | Increase ability radius but not ordinary main-weapon sweep |
| Status / combat state | Information carried by an entity | Bleed stacks, Frost intensity, a Mark |
| Reaction | Explicit interaction rule combining states and effects | Frost + Electricity discharge |
| Evolution | Major transformation of an owned active combat power | Sword gains a fundamentally new fighting pattern |
| Reward director | Selects eligible opportunities | Prepared pool, wildcards, ranks and Evolution bonus |

## 5. Attack model, identity, inheritance, and snapshot semantics

### 5.1 Four functional layers — CONFIRMED DESIGN MODEL

1. **Action:** an activation / cast / attack instance, identifying who committed the action and when.
2. **Delivery:** how/where it travels and hits, such as melee arc, thrust, orbit, projectile or area.
3. **Payload:** damage, status, knock-up, costs, healing, secondary effects and similar consequences.
4. **Triggers:** conditions that cause follow-ups, periodic responses, on-hit, on-kill, on-assist, reactions or other responses.

A spawned attack is not automatically the same thing as the attack that produced it. The game's design must differentiate **activation**, **individual hit**, **damage instance**, **status application**, **reaction**, **kill**, and **generated follow-up**. This prevents misleading assumptions such as “per cast” meaning “per target” or “a DoT tick” counting as an ordinary weapon swing.

### 5.2 Inheritance is explicit, not unconditional — CONFIRMED

- An ability can fully inherit the main weapon's damage and relevant effects, **including negative effects and resource costs**, while keeping its own delivery, base attack behavior and native effects.
- Another ability can inherit only specified aspects, or nothing.
- Generated attacks may inherit designated tags, attributes, rune eligibility or status behavior, but they **do not receive the entire original action automatically**.
- A global rune's effect is applied **once to each qualifying attack instance**. Multiple inheritance paths cannot duplicate the same rune on that same instance.
- Pre-existing or generated effects are allowed to interact through deliberate chains; that does not grant unbounded or implicit recursion.

### 5.3 Flagship illustrative build — Blood Spiral / Bleed Sword

This is the recurring **design validation example**, not an approved final hero/weapon/power list:

1. The player chooses a normal melee sword main weapon. The sword has no inherent mana cost.
2. Before the run, they equip a **global Bleed rune** that makes compatible attacks apply Bleed but demands mana **per attack activation**.
3. Their hero's innate passive **converts applicable mana costs into HP costs**. A sword attack now spends HP because it inherits the rune's price, not because every sword globally costs HP.
4. A Trait **heals on hitting a target that was already bleeding before the hit**. Bleed applied by that very same hit does **not** qualify for healing on that hit.
5. They acquire **Spinning Blade**, an ability that explicitly takes on main-weapon damage/properties/effects/costs in addition to its own native attack/delivery. Every Spinning Blade activation therefore pays the appropriate inherited price.
6. Another Augment increases **ability size**, not the ordinary sword main-attack geometry.
7. A conditional main-sword bonus slash occurs after a certain number of qualifying weapon activations; qualifying Spinning Blade activations advance the shared main-sword counter. The **generated bonus slash itself does not increment the same counter or recursively trigger itself**.
8. The result can become self-sustaining against a dense horde or dangerously self-harming when there are no valid healing opportunities. That tension is intentional.

### 5.4 Runes, duplicated effects and instance identity — CONFIRMED

One actual attack instance must carry a consistent identity and source. The rune modifier is applied once if compatible. For example, Spinning Blade's full inheritance cannot accidentally pay the same Bleed rune twice just because the ability also has a reference to the main weapon. It must, however, pay its **own qualifying activation cost** when it starts. A later independent activation of another generated attack may have its own valid cost if defined as a separately priced attack.

### 5.5 Activation snapshots — CONFIRMED

An attack takes a snapshot of the relevant offensive properties **when activated**. If a temporary buff expires during the swing, projectile flight or ongoing committed sequence, that same committed attack retains its snapshotted enhancement until its own completion. A subsequent new activation uses the player's current build state.

Fully inheriting abilities can inherit a currently active temporary main-weapon transformation, including any drawbacks and costs. Partially inheriting abilities only receive the exact explicitly designated components.

### 5.6 Attack eligibility and targets — CONFIRMED

An automatic attack normally **waits for a valid target** before initiating, instead of endlessly spending resources into empty space. Once a valid target causes activation, the activation's cost is committed even if it subsequently **misses** or hits no enemy. Interaction targets (puzzle objects) can be valid for explicitly targeted auto-attacks when the contextual mechanism is used.

## 6. HP / mana costs and cast semantics

### 6.1 Cost scopes — CONFIRMED

The system needs explicit scopes, at least:

- **Per activation / per cast:** paid once for each committed attack; **not once per enemy hit**.
- **Per pulse / channel interval:** paid at the explicitly specified intervals for a maintained effect.
- **Per target:** allowed only when a particular effect explicitly calls for it.
- **Follow-up activation:** a separate child action checks/pays its own applicable cost when launched.

### 6.2 Commitment and insufficient resources — CONFIRMED

1. The engine finds a valid target/activation condition.
2. It checks the applicable initial costs, conversions and affordability according to the attack's current properties.
3. The initial attack is committed, and the applicable activation price is paid.
4. A normal mana shortage that occurs **after** the cast started does not retroactively cancel the committed cast.
5. A later independently triggered attack checks its own affordability when it attempts to begin.
6. Failure to pay for a child attack does **not** cancel its already successful parent attack.
7. **Critical HP-cost exception:** if an HP payment kills the caster, the caster dies and the affected ability/cast ends; ordinary healing cannot retroactively undo that death. Any future explicit death-prevention power must intercept before death.

### 6.3 Important edge-case examples

- **Sword hits 10 enemies:** one per-activation Bleed-rune mana/HP cost, not ten.
- **Sword misses after activation:** its once-committed activation cost is still paid.
- **No target:** ordinary automatic sword activation does not drain HP in a loop.
- **Spinning Blade is activated:** it pays its own activation costs, including inherited rune costs and native costs as specified.
- **Spinning Blade creates a bonus strike:** the new child follows its own stated price/eligibility; it does not automatically consume the main sword's counter again.
- **Mana is restored after the initial cast:** follow-up actions can use the updated resource state, but the original cast's commitment was already determined.
- **HP spending is fatal:** death happens; that attack does not receive an implicit “finish even if caster is dead” privilege from generic cast commitment. This is distinct from attacks validly committed before a later unrelated death.

### 6.4 Specific cost-aggregation ambiguities — OPEN

Exact ordering when multiple independently priced inherited effects, HP conversions, mana restoration, cost reduction, refunds and lethal payment collide is not fully fixed. The high-level scopes and lethal-HP rule are confirmed; a precise transactional ordering specification remains a future design task.

## 7. Global pre-run rune system

### 7.1 Core rules — CONFIRMED

- Global runes are **equipped before the run** from the preparation/training interface.
- They are separate from the unified in-run acquired-power capacity.
- An equipped rune applies automatically to **every compatible player-owned attack source** that meets its tags/capabilities, including compatible secondary weapons acquired later.
- Compatibility is **capability-driven**, not a hardcoded list of weapon names.
- Runes can add advantages, constraints, HP or mana expenses, status effects, conversions, delivery adjustments, or conditional proc rules.
- Runes do not universally copy themselves onto every secondary reaction, DoT tick, and spawned attack; eligibility must be explicit.
- Compatible runes are deduplicated **once per attack instance**, even when a complex ability inherits the same rune through multiple paths.

### 7.2 Example rune families — PROPOSED, NOT LOCKED

- *Imprint:* apply a compatible status, such as Frost on physical direct strikes.
- *Form:* change delivery, such as piercing or attack shape.
- *Tempo:* change cadence or count activations toward an empowered follow-up.
- *Conversion:* convert damage/resource output into another form.

These categories help explain mechanics but are not approved inventories or exact UI groupings.

### 7.3 Rune capacity and progression — PARTLY CONFIRMED, DETAILS OPEN

A player can unlock more rune capacity through permanent progression as part of expanding build possibilities. Exact starting/max capacity and economy are not locked. The earliest V3 notes also floated **in-run** capacity expansion and values such as `2 → 3 → 4`, but these were historical sketches, and a later handoff explicitly left permanent-versus-in-run timing unresolved. **Do not treat a numerical slot count or in-run acquisition flow as confirmed.** The current confirmed player-facing rule is that the actual runes used in combat are equipped **before** the run, separately from ordinary power cards.

## 8. Combat, enemy pressure and skill expression

### 8.1 Pressure pacing — CONFIRMED

- Begin with modest opposition and escalate toward large hordes and dangerous events.
- Use **continuous ambient spawning**, map-bound enemies, scheduled events and optional activated encounters.
- Include **breathing periods** that lower pressure without making the world entirely empty or inert.
- Let enemies and events pressure different builds differently; no guarantee that every build solves every optional objective equally well.
- Build strength should grow spectacularly, but the player still needs movement judgment and the ability to read hazards.

### 8.2 Enemy collision and contact damage — CONFIRMED

- Enemies do **not physically block player movement** like an impenetrable crowd of bodies.
- Enemies can deal **contact damage**.
- A **shared contact-damage interval** keeps multiple ordinary enemies overlapping at once from applying an uncontrolled number of contact hits instantaneously.
- That contact interval is **not universal invulnerability** against projectiles, AoE, persistent fields, environmental hazards or other independent legitimate threats.

### 8.3 Enemy archetypes — CONFIRMED DIRECTION

Provide varied roles: ambient fodder/swarm members, skirmishers, ranged artillery, controllers, dangerous elites/regional bosses and final boss mechanisms. AI should use purposeful pressure, flanks, retreats/commits or attack geometry rather than endlessly orbiting the player without meaningful engagement. Pursuit and transition behavior depend on enemy type and region/portal rules.

### 8.4 Boss attacks — CONFIRMED DIRECTION

Boss actions should have legible **telegraph → tracking or preparation → commitment → active danger → recovery** style phases as appropriate, allowing players to predict and outmaneuver them. Hard mode can raise difficulty and complexity; it should not intentionally use unavoidable damage as a shortcut.

## 9. World shape and procedural exploration

### 9.1 Large interconnected world — CONFIRMED

One generated run contains **more places and content than a player can ordinarily see**. The game is not one fixed little arena or a single corridor of locked maps. Its geography is a **network of interconnected regions** with loops, backtracking, physical travel and multiple possible routes. Some transitions may be seamless, while special dungeons or realms use explicit portals.

Procedural generation is **hybrid**: authored landmarks, puzzle modules, special set pieces and boss arenas appear within variable region connections, event locations, enemy populations and routes. There is no requirement for full arbitrary geometry synthesis, and procedural variation must preserve reachability and playable escape routes.

### 9.2 No routine fast travel — CONFIRMED

Players traverse the world physically, exposing themselves to combat along paths and making discovered shortcuts valuable. The party-wide teleport through the final gateway is a deliberate exception. A run may include loop routes, side paths, revisitable landmarks and hidden passages.

### 9.3 Enemy pursuit across region transitions — CONFIRMED

Not all enemies follow across every transition:

- Ordinary regional hordes have limited pursuit scope.
- Some special hunter enemies can pursue across regions or explicit transitions.
- World Collapse may include relentless boss-tier pursuers as part of the catastrophe.
- Exact chase boundaries depend on the specific enemy and entrance/portal type.
- Despawning enemies or unloading distant simulations **is not a kill**: it never grants XP, lifesteal, kill credit, on-kill procs or healing.

### 9.4 Regional difficulty — CONFIRMED

Danger escalates globally over run time, while particular regions maintain their own enemy families, hazards and baseline threats. Escalation is not simply inflated HP and damage; it can include hostile roles, new attacks, dangerous terrain and evolving encounters. A heavily prepared player should sometimes feel overwhelmingly strong, but not because all monsters behave identically.

### 9.5 World simulation scope — DESIGN CONSTRAINT

Co-op players can be in entirely different regions. The engine must not drop gameplay-critical outcomes because it cannot render or simulate every distant region at full fidelity. Nonessential offscreen regions should not run full expensive simulation without need; actual streaming, deterministic simulation, ownership and networking models remain **engineering OPEN**.

## 10. Exploration, map knowledge, secrets and mechanisms

### 10.1 Fog-of-war — CONFIRMED

- Map geometry is revealed primarily by **physical exploration**.
- Once revealed within the run, discovered geometry remains available on the map.
- In co-op, map discovery is **shared**: one player's exploration reveals passages and shortcuts for all teammates.
- At World Collapse, the precise gateway marker and **major regional connections** become visible to the party, even if not previously explored.
- Minor unexplored local geometry and optional secrets remain fogged.
- A directional compass can point toward the gateway, but the game does **not automatically draw a solved escape route**.

### 10.2 Secrets — CONFIRMED

Hidden passages, puzzle rooms, combat challenges, lore, unusual objects, meaningful shortcuts and rare rewards can be discovered through **environmental clues**: art, sound, suspicious layouts, physical interactions or contextual behaviors. Avoid a routine HUD announcement that simply says “secret nearby” and removes discovery.

Some optional secrets can favor particular build tags or effects (Frost/Electricity/impact), but the mandatory route and most fundamental puzzles must not become impossible for heroes who lack one specific power. Build specializations can reveal shortcuts or alternative solutions.

### 10.3 Puzzle design — CONFIRMED

Puzzles may be calm or reduced-pressure, under active combat pressure, or brief quick mechanisms. They can use environment-reactive combat effects and interactable targeting. The game should distinguish:

- **Natural reactive objects:** respond to compatible attacks or effects through physics/capability rules.
- **Precision mechanisms:** a contextual interact action instructs the next eligible automatic attack to target the object, then ordinary combat targeting resumes.

Precision interaction must respect the real attack timing, range, hitbox and resource costs. It is not a free invisible switch press disguised as combat.

### 10.4 Interacting with mechanisms is not farming enemy procs — CONFIRMED

Valid object hits can count as qualifying **weapon activations** when the relevant counter is activation-based. For example, triggering a mechanism with a sword may advance its every-third-attack counter if that activation is eligible. But a door is not a bleeding enemy: it must not trigger enemy-only healing, lifesteal, on-kill rewards or other effects requiring a valid enemy target.

### 10.5 Puzzle progress and departure — PARTLY CONFIRMED / OPEN

- **Completed permanent mechanisms and unlocked shortcuts persist for the rest of that run.**
- Incomplete puzzle state resets if the area is abandoned; the precise co-op rule for when the *last* teammate leaves was proposed, not separately ratified in the available summary.
- Temporary environmental effects may expire normally.
- At World Collapse, previously started optional puzzles may continue, but new optional puzzle activation is blocked; **required escape-related mechanisms remain usable**.

### 10.6 Exploration rewards — CONFIRMED

Ordinary exploration secrets may provide HP/MP, currency, lore, permanent discoveries or extra power selections. Ordinary secret power choices use the **player's prepared pool/wildcard logic**, just like ordinary level-up or event power rewards. They do not silently grant a special outside-pool power. Separately and explicitly designated special events may have outside-pool unique powers.

For ordinary secret power rewards in co-op, teammates **physically present at the secret location before claim** receive their own individually generated choices from their respective pools. Remote teammates still gain shared map knowledge and shared XP where applicable, but not the local claimed reward. The precise claim-action UI was proposed and not finalized.

---
# PART II — RUN, REWARD, EVOLUTION, WORLD EVENTS, AND ENDGAME RULES

## 11. Core run structure and modes

### 11.1 Run length and the actual meaning of “25 minutes” — CONFIRMED

An early design sketch entertained much shorter mobile sessions. This was **superseded** by a more substantial normal run. The current precise rule is:

- At approximately **25:00 on the normal run timer**, the **final gateway becomes available** in a reachable world location and **World Collapse** starts, unless players have already intentionally entered an available early boss route.
- The gateway is not necessarily close to the players. The party must find and **physically travel** to it while the world becomes increasingly dangerous.
- The gateway sends the party to a **separate final boss arena**.
- A short preparation sanctuary precedes the final boss; the boss fight can push total elapsed time **past 30 minutes**. “25 minutes” is **not** an automatic game-over timer or an exact boss appearance time.
- Exact final total duration, sanctuary length and boss phase durations are **OPEN**.

### 11.2 Difficulty modes — DIRECTION

Normal mode is the baseline. Hard mode should offer greater threat, stronger/more diverse enemy behaviors and more complex danger, not untelegraphed unavoidable damage. An eventual Endless mode may support high scores and escalating build experiments. Neither Hard/Endless balancing nor their unlock requirements have been finalized.

### 11.3 Movement and combat remain relevant throughout

A strong build can erase hordes quickly, but geometry, map travel, catastrophe navigation, enemy roles and boss attacks still matter. High pressure should test build synergy **and** player positioning. Continuous ambient enemies and activated encounters can overlap without necessarily leaving the world permanently at maximum intensity.

## 12. Events and encounter framework

### 12.1 Hybrid encounter director — CONFIRMED

The world combines:

1. **Ambient roaming/spawned hordes** for continual action.
2. **Map-bound threats** tied to places and regions.
3. **Scheduled events** occurring as part of the run timeline/world state.
4. **Optional events** activated when a player decides to take on extra risk.
5. **Breathing periods** that reduce pressure instead of fully turning off combat.

### 12.2 Ordinary objective-based events — CONFIRMED

Illustrative objective families:

- Survive or defend within a zone for a period.
- Endure a severe environmental condition.
- Hunt and kill an unusually strong enemy.
- Secure/hold a location under pressure.
- Retrieve an item through dangerous terrain.
- Complete a timed or combat-linked location objective.

Not every build must be equally well matched to every optional event. Some tests favor mobility, boss damage, sustain, crowd clear, burst, control or resilience. The challenge and potential penalty should be communicated rather than being a hidden trap.

### 12.3 Event stakes and scope — CONFIRMED

Ordinary challenge events can have success rewards and, where specified, failure penalties. **Risk tiers vary** between events: low-risk events may have minor consequences while high-risk ones may have significant stakes. The game communicates the expected risk before the player begins.

A reward or failure consequence must declare whether it affects:

- The activating individual.
- Any teammate physically participating in the event.
- The entire party/world.

These scopes are independent: an event may have a participant-specific personal reward and a world-wide failure consequence, but both must be stated. An event cannot quietly punish remote teammates with an unannounced party penalty.

### 12.4 Support events are different — CONFIRMED

Certain events **help the player directly** and do not use a completion objective. Examples include temporary protection/safe zones, buffs or a temporary “super weapon.” Such a support event has **no completion reward and no failure penalty** because its purpose is immediate temporary assistance, not a scored challenge.

A temporary super weapon **transforms/enhances the player's existing main weapon**, rather than introducing a completely independent AI gun. Its properties may pass to a fully inheriting secondary ability according to the attack snapshot, including beneficial changes **and negative costs**. When the buff ends, subsequent attacks return to the current normal/evolved main weapon, not necessarily the weapon's original unevolved state.

### 12.5 Participation boundary and event scaling — CONFIRMED

For a local optional event, a **participant** is a player who enters the clearly marked **active event area before completion**; no separate damage/contribution threshold is required. A teammate may join while the event is underway. The area boundary must be readable so a player can understand that entering may count them as a participant and increase difficulty.

Difficulty is calculated at activation from nearby participants. If additional **unique** players enter later, future waves/phases may grow harder. Existing enemies are not retroactively inflated, upgraded or replaced merely because someone arrived.

Critically:

- **Difficulty never scales down** because someone dies, leaves the region or disconnects.
- The event retains the maximum set/count of unique participants reached for its scaling.
- A player leaving and reentering is **not counted twice**.
- Local optional events may be activated by just one party member; designated major/scheduled events may use broader participation or world scope.
- Multiple independent events may happen simultaneously in different regions while co-op players split up.

### 12.6 Events at World Collapse — CONFIRMED

Once World Collapse begins at the normal 25:00 transition:

- **No new optional challenge event** may be started.
- **Already-active challenge events may continue** according to their own conditions.
- Whether abandoning an existing event or entering the final gateway causes failure/penalties is **event-specific and disclosed beforehand**.
- No new support event starts.
- Temporary support effects already granted expire according to their normal lifetimes.
- Already-started optional puzzles may continue; new optional puzzles cannot start, while mandatory escape mechanisms continue operating.

### 12.7 Ordinary vs designated unique power rewards — CONFIRMED

Ordinary event power-selection rewards use the recipient's prepared power pool and wildcard choices. **Explicitly designated special events** can grant unique outside-pool powers. These special cases must be communicated, not silently substituted for an ordinary prepared-pool offer. Non-power rewards (currency, permanent unlock milestones, heals) remain separate.

## 13. Pre-run preparation, knowledge and the power pool

### 13.1 Things prepared before entering — CONFIRMED

The player chooses:

- A **hero**, with one fixed manual active ability and innate passive.
- A **main weapon**, independently of hero.
- A set of globally equipped **runes** within the available capacity.
- A **candidate power reward pool** containing previously encountered/known Abilities, Traits and Augments, possibly with wildcard spaces left open.

**Distinction:** being in the prepared power pool does **not** mean the player starts the run already owning that power. It only controls what can be **offered** through ordinary in-run selections.

### 13.2 How ordinary power discovery works — CONFIRMED

When the player **encounters/sees** a new ordinary power in a run, that power becomes permanently known in the collection/Codex and can be considered for future prepared pools. The player does **not** need to acquire it to discover it. This is **different from Evolution recipe discovery**, which requires actual acquisition (see §16.7).

Unknown powers can be drawn through wildcard reward generation when appropriate. Future preparation can use any now-known power subject to run eligibility and current constraints.

### 13.3 Prepared powers vs wildcards — CONFIRMED

- Preparation spaces filled with known powers reserve opportunities for those powers.
- Preparation spaces left blank are true **wildcards**, generated from eligible broader content **when a reward is generated**.
- Wildcard content is **not** pre-rolled as a secret static list at run start.
- A fully filled prepared pool has **no forced wildcards**. The director may not insert an unknown discovery card merely because discovery is considered healthy.
- Rejected prepared powers may appear again in future rewards.
- Prepared powers should receive **eventual offer opportunities** over sufficient normal progression when eligible, but are never automatically acquired and a player who dies early has no promise of seeing everything.
- There is an unresolved mathematical/scheduling problem for enormous prepared pools, rare conditions and limited reward cadence. “Guaranteed chance to be offered” is not “guaranteed acquisition.”

Early illustrations such as **20** pool spaces or **50** spaces were **not confirmed capacity figures**.

### 13.4 Pool capacity vs actual equipped/acquired capacity — CONFIRMED

There are two separate numbers:

1. **Candidate power pool**: everything the player allows the reward system to propose, plus wildcards.
2. **Unified acquired-power capacity**: the maximum number of **distinct** Abilities, Traits and Augments actually owned during a run.

The unified acquired-power capacity is **fixed during a run**, with an initial testing target of **approximately 10–12 distinct powers**. The precise number requires playtesting. **Every acquired distinct power takes exactly one slot**; no category-based half slots or differing sizes. Main weapon, fixed hero ability and pre-equipped global runes are **outside** this capacity. Generated child attacks, reactions and other outcomes do not themselves occupy acquired-power slots.

A rank upgrade of an owned power or Evolution of an owned combat power **does not consume an additional slot**. There is no extra slot unlock during the run. The candidate reward pool can be much larger than the actual 10–12 owned powers.

### 13.5 Commitment / no respec — CONFIRMED

An acquired power cannot be removed, replaced or swapped out for another power during that run. It may be ranked up, transformed or evolved in accordance with its definition, but that does not erase its capacity commitment. Fusion also preserves the original occupied slots; see §17.

## 14. Rank upgrades, branches and full capacity

### 14.1 Individual rank rules — CONFIRMED

Each acquired power may have its **own maximum rank** or may not rank up at all. Rank improvements may be numeric, geometric, conditional or behavioral. Most powers have a fixed authored progression; selected powers have branches.

Branch exclusivity is **power-specific**: some paths are mutually exclusive, some branches may eventually coexist, and the content definition must say which. Do not invent one global rule that every branch excludes every other or that all branches always stack.

### 14.2 Reoffering owned powers — CONFIRMED

If a generated option names a power the player already owns and that power can advance, it is an offer for its **next rank**. If the power is already at maximum rank, has no rank progression or is otherwise ineligible, the option is unavailable. A power offered previously and declined may return later.

### 14.3 When slots are full — CONFIRMED

When the unified capacity is full:

- The player cannot acquire a **new distinct** Abilities/Traits/Augments power beyond the cap.
- The player **can rank up or evolve** powers already owned.
- Normal rewards can include **non-power alternatives** such as HP/MP recovery or currency.
- If **every option in a previously generated, locked reward** later becomes unusable (full capacity, max rank, branch conflict, etc.), convert the whole reward into **non-power compensation**. Do **not** reroll its original options.

The exact mix/value of healing and currencies is OPEN.

## 15. Reward timing, deferred choices and co-op synchronization

### 15.1 Shared leveling with individual build choices — CONFIRMED

Co-op party XP is shared and the group levels together, even if friends are in separate regions. **Each player independently receives/chooses their own reward options and build**. Sharing a level-up does not mean everyone must select the same power.

### 15.2 Deferred rewards — CONFIRMED

A player may defer more than one earned power selection. **World simulation and co-op continue**; reward menus do not imply a global pause or immunity. The player can decide later, including when spectating while dead.

**Crucial timing rule:** the reward options are **generated and snapshotted when the reward is earned**, not when the UI opens. They never reroll merely because the player's build, capacity, Evolution eligibility or location changed while waiting. Later selections can make saved choices unavailable. If all choices become invalid, apply the compensation rule in §14.3.

### 15.3 Deferred Evolution rotation — CONFIRMED

Evolution bonus options are likewise fixed at **reward generation time**. If the player's eligible Evolution queue contains several transformations, its rotation **advances when each eligible reward is generated**, not when the player opens the pending selection. Thus opening older rewards in an unusual order cannot reroll or manipulate the offer sequence.

### 15.4 Dead players may choose — CONFIRMED, V12.8

Dead players continue sharing XP and receiving earned group-level rewards. They may inspect, defer, rank up and acquire powers or Evolutions while spectating. The selected power is immediately recorded as owned for their build and Evolution/Codex logic, but **cannot create active combat behavior until they are revived**. A newly earned reward never retroactively changes previously locked options.

## 16. Evolutions: prerequisites, offers, discovery, and permanence

### 16.1 Purpose — CONFIRMED

An Evolution is a major, distinctive transformation of an acquired active combat power, not a generic +damage rank or a separate acquired-power slot. It should transform fighting behavior, geometry, triggers, resource properties, area, chaining or other mechanics in a recognizable way.

### 16.2 Combination recipes — CONFIRMED

Evolution eligibility comes from **specific combinations of actually acquired weapons/powers** (and potentially their transformation state), not kill counts, damage achievements or activity milestones standing in for the recipe. Such milestones can be separate quests/permanent unlocks.

For recipe components:

- An **active combat ingredient** (main weapon, secondary weapon, offensive ability) must meet that recipe's **specified rank**. This rank may be below the ingredient's own maximum.
- A **supporting Trait, Augment or other passive** usually only needs to be owned/selected; it does not require ranking unless a future recipe explicitly changes its classification/requirement.
- The hero's **fixed manual active ability does not itself evolve**.
- Higher-level recipes may explicitly include an already acquired ordinary Evolution as an ingredient.

### 16.3 Eligibility does not auto-acquire — CONFIRMED

Completing the recipe only marks an Evolution as **eligible**. It does not forcibly transform the weapon. At the **next eligible power-selection reward**, the unlocked Evolution appears as an **additional bonus option**, alongside the ordinary prepared-pool or wildcard choices. The player still takes **one** choice total.

If the player declines the Evolution, it **remains eligible** and returns through the queue until acquired, provided no later mutually exclusive choice makes it invalid.

### 16.4 Exactly one bonus Evolution per reward — CONFIRMED

Even if five Evolutions are eligible, a single eligible reward presents **exactly one Evolution bonus candidate**, not five. Eligible Evolutions rotate through a per-player queue, advancing on **reward generation**. Once acquired, that Evolution leaves rotation. Saved rewards preserve whichever specific Evolution was originally offered.

### 16.5 All ordinary power-selection rewards are eligible — CONFIRMED, V10.9

Level-ups, ordinary challenge-event power rewards and secret-location power choices **all** use the same per-player Evolution bonus system. If they present an ordinary power selection, they can offer the rotating unlocked Evolution. Non-power rewards are not retroactively converted into Evolution choices. Fixed unusual rewards from designated special events retain their explicit rules.

### 16.6 Exclusivity and compatibility — CONFIRMED

Some Evolutions for the same weapon are mutually exclusive, while others are explicitly compatible. The specific recipe defines these relationships. An acquired incompatible Evolution prevents the conflicting option from being chosen, including if that option was saved in an older deferred reward; it **does not cause the saved reward to reroll**. Compatible Evolutions can combine their authored behaviors.

### 16.7 Evolution Codex discovery is different from ordinary power discovery — CONFIRMED, V10.7

An Evolution's **complete recipe is permanently discovered only when the player actually selects and acquires that Evolution**.

| Player action | Full Evolution recipe recorded permanently? |
|---|---|
| Sees environmental/Codex hints | No |
| Acquires all recipe ingredients | No |
| Evolution becomes eligible | No |
| Evolution offered in reward selection | No |
| Evolution declined | No |
| Player dies after seeing offer, without acquiring | No |
| Player selects/acquires Evolution, then dies | **Yes** |
| Player acquires Evolution while dead via pending reward | **Yes**, even if the party later loses |

Unknown Evolutions can show **partial hints**, but full ingredient/rank detail stays locked until acquisition. Knowing a recipe permanently does not give the player the Evolution for free on subsequent runs: all ingredients must be assembled again each run.

### 16.8 Evolution knowledge is individual in co-op — CONFIRMED, V10.8

Only the player **who acquires** the Evolution unlocks its full recipe in their personal Codex. Seeing a teammate transform, helping them prepare, sharing map knowledge or winning together does **not** confer that recipe unlock to the observer. Friends can discuss recipes outside the Codex system, but mechanical permanence remains personal.

### 16.9 Evolution cannot be reversed or disabled — CONFIRMED, V11.3

An Evolution, once acquired, remains active for that run and **cannot be toggled off, reverted, or replaced with its pre-evolved form**. This applies to ordinary, Advanced and Fusion Evolutions. Negative HP/mana costs and dangerous interactions remain binding unless another legitimate future power changes their behavior. Run end resets the temporary combat transformation while preserving the acquired personal Codex record.

## 17. Advanced Evolutions and Fusion Evolutions

### 17.1 Most Evolutions finish there; a few go further — CONFIRMED, V11.0

Most ordinary Evolutions are final transformations. **Selected** recipes can use an already-evolved power to unlock:

- **Advanced Evolution:** a further transformation of an existing evolved combat power, after additional specific ingredients/ranks.
- **Fusion Evolution:** an exceptional recipe involving two or more compatible evolved powers (and possibly other supporting ingredients), producing an authored high-level transformation or interaction.

This is **not** a requirement that every weapon have a lengthy multi-stage tree. Well-designed ordinary builds must remain strong and worthwhile.

### 17.2 Fusion's actual result is recipe-defined — CONFIRMED, V11.1

Fusion does not use one fixed “merge into one attack” rule. A recipe can explicitly specify:

1. **Primary transformation:** one combat power changes; other ingredients remain functionally separate.
2. **Mutual transformation:** two or more participating combat powers all change.
3. **Linked interaction:** ingredients retain much of their identity but gain a new shared trigger, dependency, marked target or cooperative mechanism.

For each Fusion, explicitly define transformation targets, unaffected ingredients, attack snapshot, inheritance, native mechanics, negative costs, trigger ownership, branch exclusivity and permitted recursion.

### 17.3 Fusion does not alter capacity — CONFIRMED, V11.2

**Every original acquired power keeps its occupied slot after Fusion.** The Fusion selection itself adds **no new slot**, and it never refunds an old one. Two acquired abilities occupying two slots still occupy two slots even if a Fusion makes them feel like one giant combined attack. The exact same fixed 10–12 target cap remains in force.

### 17.4 No reversal — CONFIRMED

Advanced and Fusion Evolutions follow ordinary Evolution permanence: no toggling, undoing, selling, removing or converting them back within the run. If a player chooses a high-damage but dangerous HP-cost transformation, adapting the rest of the build is the intended consequence.

### 17.5 Illustrative working names — NOT APPROVED CONTENT

Names used during discussion included **Blood Cleaver**, **Eternal Spiral**, **Crimson Tempest**, **Crimson Devourer** and **Storm Cyclone**. Their effects, component assignments, damage values and appearances are examples only. The confirmed feature is the *system*, not these items.

## 18. World Collapse, gateway, early access, and final boss

### 18.1 Collapse starts around 25:00 — CONFIRMED

When the normal gateway phase begins, the overworld enters **World Collapse**:

- Catastrophic region-specific threats escalate rapidly.
- Boss-tier pursuers can appear repeatedly and may be as dangerous as—or stronger than—the actual final boss in the overworld.
- Killing pursuers cannot turn off the catastrophe or prevent replacements/escalation.
- Safe-room/retreat exploits should not allow indefinite survival while ignoring the gateway.
- The game reveals the **gateway's exact position**, the main regional connections and a directional compass, but not every unexplored local route.
- The gateway must be **physically reachable** based on traversable world distance and the generated region graph. It is not necessarily adjacent to current players.

### 18.2 Regional catastrophe identity — CONFIRMED DIRECTION

Examples: a forest unleashes powerful hunters; caves threaten collapses and emergency passages; volcanic regions fill with rising hazards; magical realms destabilize. Catastrophe should feel geographically coherent, not merely “all monsters gain 200% HP.” Some areas may require dangerous backtracking, alternate shortcuts or newly opened emergency paths.

Mandatory traversal remains possible for ordinary movement-capable characters. New attacks should remain readable and dodgeable; terrain may raise route difficulty without permanently sealing the only accessible route or trapping fallen allies beyond rescue.

### 18.3 Optional early boss access — CONFIRMED

Some runs may contain a special event / objective chain / discovery / dangerous guardians that let players **intentionally enter the final boss earlier**. This content is not guaranteed to exist or be accessible in every procedural world. Using early boss access **skips the World Collapse escape phase** and enters the boss sequence directly. The player must choose to activate it; normal runs otherwise reach the 25-minute collapse.

### 18.4 Final gateway group behavior — CONFIRMED

**Any one living co-op player** entering the final gateway initiates the transition for the **entire party**, including dead teammate bodies. Dead teammates arrive **still dead**; the gateway is not an automatic resurrection.

The final transition intentionally clears the overworld:

- All overworld enemy AI, regional hordes, special pursuers and event spawns stop.
- Existing overworld hazards/projectiles and pending catastrophe simulation terminate/clean up.
- The cleanup is **not kill credit** and does not grant XP, lifesteal, HP gain, on-kill triggers or reaction chains.
- Player builds, resources and legitimate remaining timed effects persist according to their own established rules, unless an explicit exception is later designed.
- Unfinished events resolve according to **pre-disclosed event-specific gateway-entry/failure rules**.

### 18.5 Final boss sanctuary — CONFIRMED

The party arrives in a distinct readable boss arena, initially with a **short safe preparation interval**. The boss activates after a defined fixed preparation period **even if one or more teammates remain dead**. Living teammates can channel those dead teammates' revivals once their eligibility waiting times and physical requirements permit. Existing death counters and penalties carry over into the boss arena; they do not reset at the gateway.

The dedicated boss fight does **not** include overworld pursuers or continuing World Collapse hazards. The boss has its own attacks, phases and cutscene/presentation. An intentional run climax should replace runaway overworld simulation with a focused fight.

---
# PART III — CO-OP, REVIVAL, DISCONNECTIONS, AND COMBAT OWNERSHIP

## 19. Cooperative play and shared versus individual state

### 19.1 Intended co-op model — CONFIRMED DIRECTION

The game supports solo play and friend-hosted co-op in a self-contained run/session. This is **not** an MMO and not automatically a persistent multiplayer world. Exact transport, host migration, authority, save persistence, reconnect handshake and online service architecture remain OPEN.

### 19.2 Party-shared state — CONFIRMED

- Shared earned XP and group levels; friends do not need to stay in the same region to benefit.
- Shared exploration map and discoveries of passages/shortcuts **within that run**.
- A common procedurally generated world and escalating timeline.
- Major global events and designated party-wide rewards/failures.
- World Collapse and the final gateway transition.
- Victory as a **party outcome**.

### 19.3 Personal state — CONFIRMED

- Hero and independently selected main weapon.
- Equipped global runes and individual prepared/wildcard pool.
- Actual acquired Abilities, Traits, Augments and ranks.
- Owned ordinary/advanced/fusion Evolutions.
- Reward options, deferred selections, eligibility rotation and full-capacity compensation.
- Permanently acquired Evolution recipe Codex knowledge.
- Local event/secret rewards when explicitly participant- or claimant-scoped.
- Each person's cumulative death count, revival timer and status.
- Each person's accrued unsecured special currency before successful team victory.

### 19.4 Physical separation is allowed — CONFIRMED

Players may be in distinct regions, start different local events, discover independent secrets and still level together. Remote teammates are not automatically considered local event participants or local secret claimants. Shared map knowledge is **not** universal entitlement to every discovered physical reward.

### 19.5 Event participant definition — CONFIRMED

A player enters a clearly indicated **active event area before the event ends**. That alone is sufficient to count them as a participant for eligible participant-scoped rewards; they need not have landed a hit. Event scaling uses the maximum unique participants, as detailed in §12.5.

## 20. Personal death, revival, and party wipe

### 20.1 Basic team survival rule — CONFIRMED

A run continues as long as at least one **eligible surviving party member** remains, subject to the later disconnected-player grace-period exception (§21). If everyone is dead, the party **immediately loses**; there is no automatic post-wipe countdown, emergency revive or extra resurrection window. Solo death likewise ends a solo run absent an explicit effect that **prevents** entry to the dead state beforehand.

### 20.2 Individual death has no inventory/build penalty — CONFIRMED, V12.0

An individually dead player retains:

- All owned weapons, abilities, traits, augments, ranks and Evolutions.
- Ordinary/common currency and accrued unsecured special currency.
- Pending reward selections with their original locked options.
- Permanent discoveries, Codex knowledge and completed qualifying objectives.

Dying does **not** impose another damage reduction, stat loss, weakness debuff or loss of gear. Cost is instead **time, rescue exposure, temporary inability to act, and cumulative revival waiting escalation**. Temporary buff timers continue normally while dead rather than freezing as an extra advantage.

### 20.3 Death counters and linear waiting time — CONFIRMED, V12.2–V12.3

Each player tracks cumulative deaths **during the current run**. The mandatory time until other players may start reviving them grows **linearly** after each death and is capped at a hard maximum. The penalty **does not decay** with survival and **does not reset** when the party enters the boss arena. It resets **only at the start of a new run**.

Mathematically:

```text
revival_wait(n) = min(initial_wait + (n - 1) * per_death_increment, hard_cap)
```

where `n` is that player's cumulative death count. **Exact initial, incremental and capped seconds are OPEN.** Example values `5s, 10s, 15s, 20s, 25s, 30s` were shown to illustrate a linear progression only; they are **not approved tuning**.

The mandatory waiting period starts at death. **Revival channel time is separate**. Faster channeling does not shorten the mandatory death wait.

### 20.4 How physical revival works — CONFIRMED

1. A player dies and a fallen body remains at its death location.
2. That player's cumulative revival eligibility timer runs.
3. After the wait expires, at least one **living connected or otherwise eligible controlled teammate** must physically approach the body and **channel** revival. This “connected/controlled” phrasing describes a practical action requirement; exact disconnected-channel behavior remains OPEN.
4. A rescuer who moves away or takes interrupting enemy damage stops channeling, but **already accumulated progress is preserved**.
5. Multiple simultaneous rescuers advance one **shared** revival meter.
6. Additional rescuers increase the speed with **diminishing returns**; each extra rescuer contributes less than the previous one.
7. When the shared progress completes, the teammate revives with **partial HP** and **brief revival protection**.

No exact base channel duration, multipliers or partial-HP amount is finalized. The example 1.0× / 1.6× / 2.0× for one/two/three rescuers was illustrative only. A four-player party can have at most three other living teammates simultaneously channeling the fourth's revival.

### 20.5 Revived-player protection — CONFIRMED, V12.1

During the short post-revival protection window:

- Incoming **external enemy and environmental damage** is blocked.
- Automatic attacks with affordable HP costs can still activate and **must pay their full HP cost**.
- If an automatic attack's HP cost would reduce the revived player's current HP to **zero or below**, that attack **does not activate** during the protected window.
- If the player heals enough to afford it, the blocked automatic attack can activate normally.
- Once protection expires, the ordinary rule returns: HP costs may be lethal.
- **No free HP-cost casting** is granted; the safety rule suppresses the dangerous automatic activation, it does not waive the price.
- The decision did **not** create special immunity for manually activated self-harming abilities; their existing rules remain.

Example: revived at 20 HP, automatic sword costs 25 HP. During protection, the sword does not auto-activate. At 30 HP it can activate and pay 25 HP. Once protection ends, the normal lethal-cost logic is back.

### 20.6 Body stays where it fell — CONFIRMED, V12.5

Other players **cannot drag, carry, push, teleport or reposition** a fallen player's body for convenience. Rescue must happen at that spot. The sole explicitly established movement exception is the **party-wide final gateway teleport** transporting fallen bodies into the boss arena.

### 20.7 Physical rescue route must always exist — CONFIRMED, V12.6

Procedural geography and dynamic collapses must preserve **at least one physically traversable route from surviving teammates to every fallen body**. A cave entrance may collapse if an alternative tunnel, route or available mechanism preserves access. A body may be surrounded by extraordinary danger or require a long detour, but the terrain cannot make rescue structurally impossible. This is a **route existence** guarantee, not a guarantee the team will survive the attempt.

This must remain compatible with the gateway's separate party teleport and with mandatory World Collapse traversability. No fast-travel system is introduced.

### 20.8 Dead-player spectator mode — CONFIRMED, V12.7

A dead player can:

- View their own fallen-body location.
- Switch to spectating any living teammate, even in a distant region.
- Continue voice/text communication and permitted party map pings.
- View their own revival waiting timer and shared channel progress.
- View and choose their own earned power rewards, including pending Evolution options.

They **cannot** move their character, attack, interact, physically scout unexplored territory, reveal new map geometry independently, or receive offscreen information beyond what the selected teammate normally perceives and the party's already shared fog-of-war allows. A complete wipe ends the run; there is no extended spectator-only game afterward.

### 20.9 Power selections made while dead — CONFIRMED, V12.8

Shared XP and levels continue accruing for dead teammates. Each new reward is generated and locked immediately. Dead players can acquire a Trait, increase a rank or take an Evolution while spectating. This updates ownership and can complete a recipe for **future** reward offers; it does **not** reroll old saved offers or activate the newly owned power's combat behavior while dead. Acquiring an Evolution while dead permanently records its recipe to that particular player's Codex.

### 20.10 Previously committed attacks after death — CONFIRMED, V12.9

A committed attack already begun before the player's death can finish its **existing committed sequence**, using its activation snapshot. For example, a launched projectile continues and a committed Spinning Blade rotation can finish.

By contrast:

- No new automatic weapon/ability activations start for the dead player.
- No new manual ability activations start.
- **Maintained effects** requiring a live owner, such as an ongoing aura or active autonomous summon, stop/deactivate.
- A continuing committed attack cannot treat death as permission to keep starting new attack cycles.
- Already applied DoTs/statuses follow the separate persistence rule in §22.
- Full party wipe immediately terminates the simulation, even if a dying player's projectile would otherwise travel further.

This rule is not an excuse to keep a lethal HP-cost attack alive if that **cost itself** killed the caster during activation; §6.2's special lethal-cost rule still applies.

### 20.11 Existing statuses after source-player death — CONFIRMED, V13.0

Bleed, Poison, Burn, Frost and other already applied statuses continue for their remaining normal durations after their owner dies. Damage-over-time continues according to the status's **snapshotted offensive potency and live target defenses**, described in §24. The original source remains attributed for damage and kill credit.

However, new **owner-dependent attack activations** such as a reaction-generated sword or an on-kill explosion cannot begin on behalf of that dead player. Another **living** teammate may still exploit the status to trigger their own compatible reaction. A status newly applied by an already committed projectile that lands after the owner dies also follows its normal application rules, with the same limitation on new owner-dependent attacks.

## 21. Disconnections, dormancy, and party-survival grace period

### 21.1 Co-op-exclusive powers and connection — CONFIRMED, V14.8–V14.9

Most on-assist powers should have useful solo behavior, but some powers may be **explicitly co-op-specialized** and unavailable to deliberately started solo runs. A co-op-exclusive power is filtered out of solo preparation and ordinary solo reward generation.

If a player already owns a co-op-exclusive power in a cooperative run and **no qualifying teammate remains connected**, the power becomes **dormant**:

- It stays owned and continues occupying its original acquired-power slot.
- It has no newly activatable co-op-specific effect during dormancy.
- It has **no temporary solo fallback**, because the user chose option A.
- It automatically works again when a qualifying teammate reconnects.
- Attacks already committed before dormancy follow their established snapshot rules; the exact boundaries of any maintained effect are governed by its rules.

The question of **what counts as a qualifying connected teammate for particular power conditions** (including alive/dead players) is not fully specified and must be explicit per power when authored.

### 21.2 Disconnected character physically remains in world — CONFIRMED, V15.0

When a player loses connection:

- Their character stays at the **last valid world position** and does not move under player control.
- The character is **fully vulnerable to enemy and environmental damage**.
- There is **no invulnerability**, suspension, disappearance, AI survival pilot or relocation to a safe zone.
- If the character dies while disconnected, normal corpse location, timer, status and teammate revive mechanics apply.
- If the player reconnects while their character is alive, they resume control at its existing location.
- If they reconnect while dead, they return to the normal dead-player spectator/reward-selection experience.
- An attack already committed before the disconnection continues according to the usual snapshot/commitment rules.

**Still OPEN:** whether ordinary automatic attacks continue to begin while the character is connected-but-idle/disconnected, and whether a reconnecting client regains old pending input state. The discussion explicitly left ongoing automatic attack activation unresolved.

### 21.3 Survival grace period for disconnected living characters — CONFIRMED, NEW V15.1

The user's newest choice was **C**:

> **A disconnected living character counts as a survivor for a limited reconnection grace period. After the grace expires, that disconnected character no longer prevents a party wipe. They remain physically present and vulnerable in the world. If some other connected player is alive, the run continues normally.**

This is a separate eligibility test from physical HP. A character can remain physically alive yet stop qualifying as the player keeping the whole party alive after its grace period expires.

#### Operational reading of this choice

- If **all characters are actually dead**, the run ends immediately under the ordinary party-wipe rule, even if some disconnected player has time left on a reconnect grace period.
- If **at least one connected living player** exists, the run continues. A different disconnected teammate can remain stationary/vulnerable; their grace expiration does not end a healthy party's run.
- If **no connected living player** remains but **at least one living disconnected player has an unexpired grace period**, the party is temporarily not wiped on this eligibility rule.
- If **no connected living player remains and no living disconnected player remains inside a valid grace period**, the run is lost—even if an expired-grace disconnected character has positive HP.
- Reconnecting restores ordinary player control and connected-survivor eligibility if the character remains alive and the run has not ended.

The grace period is **not** invulnerability, extra resurrection, pause, safe AFK mode or world teleport. Its duration and exact start/reconnect treatment are **OPEN**.

#### Illustrative timeline — no durations approved

1. A four-player party has one connected living member, two dead members, and one disconnected character still alive.
2. The connected living member dies. All actually living characters are now disconnected, so the party can persist only while at least one applicable grace period remains.
3. If the disconnected player reconnects alive **before** grace expires, the party regains a connected survivor and may attempt rescues.
4. If the character dies before reconnection, the normal all-dead condition can end the run immediately.
5. If the grace period expires without any other connected living player, the run ends even if that disconnected character technically still has HP.

#### Important unresolved edge cases

- Exact grace duration; whether different disconnect reasons affect it.
- Multiple disconnected living teammates with overlapping independent grace timers.
- What happens when **the host** disconnects and who continues the authoritative world simulation.
- Reconnect at the exact deadline boundary, packet timing and race resolution.
- How pause/alt-tab/client sleep/voluntary disconnect are distinguished from genuine network failure, if at all.
- Whether the host can end a session while all players are disconnected, independent of gameplay wipe conditions.
- Whether disconnected characters continue automatic attacks, resource spending or autonomous effects.
- How to communicate grace eligibility visibly without exposing a network exploit.

None of these details is solved merely by choosing option C.

## 22. Statuses in cooperative combat

### 22.1 Status conditions are shared for interactions — CONFIRMED, V13.1

An enemy's active Bleed, Poison, Burn, Frost, Mark or other status may satisfy the conditions of **any compatible teammate's power**. The player who applied the status does **not** exclusively own the right to exploit it.

Illustrative example:

- Player A applies Bleed to a boss.
- Player B hits the boss with a sword that heals on hitting an **already-bleeding enemy**.
- Player B qualifies for and receives that healing, despite Player A originating Bleed.
- Player B's sword does not automatically inherit Player A's unrelated offensive bonuses, paid rune costs, damage multipliers or personal effects.

This remains true if Player A has died and their existing Bleed is still ticking. Only living Player B may initiate the new healing attack. A hit's *newly applied* Bleed cannot satisfy an explicitly **pre-existing** Bleed requirement on that same hit.

### 22.2 Every status defines its own stacking model — CONFIRMED, V13.2

There is **no universal “all players share one stack pool”** rule and no universal “everyone maintains fully separate stacks” rule. Each status type defines:

- Whether application is independent per source or contributes to a shared target state.
- Number/intensity limits, if any.
- Reapplication behavior: refresh, extend, add stacks, replace, preserve strongest, etc.
- Individual versus shared damage potency.
- Source attribution needed for damage/kill/assist credit.
- Whether and how consumption removes stacks belonging to different sources.
- Status duration and what happens on owner death.

**Examples only, not locked:** Bleed might preserve separate source potency; Poison might add stacks; Frost might share buildup; Stun might have resistance/refresh control to prevent permanent boss lockdown; a unique curse might use exclusivity. The user selected **status-specific behavior**, not these exact mechanics.

### 22.3 Status-at-death is real state, not history — CONFIRMED FROM EARLY HANDOFF

Earlier co-op discussion established a useful exact-state principle:

- Player A applied Bleed.
- Player B **fully consumes** the Bleed to explode and kill that enemy.
- If Player A has a trait reading **“when a target I am bleeding dies,”** that effect does **not** activate when the enemy dies *after all Bleed was consumed*.
- Player B owns the lethal explosion and its eligible on-kill benefits.
- If Bleed still exists at death, a specifically worded condition may still qualify.

A remembered historical contribution does not count as currently active status unless the power explicitly says it checks history. Assist credit is a separate mechanic and can depend on earlier contributions within its source-defined window.

## 23. Elemental reaction ownership and chaining

### 23.1 Reaction owner is the triggering player — CONFIRMED, V13.3

If Player A applies Frost and Player B strikes with Electricity to cause a Frost + Electricity reaction, **Player B owns the reaction**. That means:

- Player B provides the reaction's base triggering source and applicable offensive scaling as defined by that reaction.
- Player B gets the reaction's damage/kill attribution.
- Player A retains ownership of the original Frost and may qualify for assist effects if their contribution remains valid.
- Merely providing Frost does **not** duplicate the reaction or activate Player A's on-hit/on-cast/rune powers as if Player A had struck again.

### 23.2 Status consumption is reaction-specific — CONFIRMED, V13.4

Each reaction explicitly says whether it:

- **Consumes** all or a specified number of enabling stacks.
- **Reduces** intensity or duration but leaves the state active.
- **Preserves** the enabling status unchanged, permitting further triggers under the reaction's retrigger rules.

Examples such as consuming five Burn stacks for a detonation, reducing Frost intensity, or preserving Frost for frequent electrical pulses were conceptual demonstrations. They were not content approvals.

### 23.3 Curated reaction-to-reaction chains — CONFIRMED, V13.5

An elemental reaction can cause another reaction **only if the producing reaction definition explicitly grants that permission**. It is not an automatic systemic privilege of any area damage that happens to have elemental tags.

An exceptional Evolution may make a Frost+Electricity discharge capable of triggering a follow-up reaction on Burning enemies. Another secondary explosion might lack permission to continue further. Exact chain stages, allowed source tags and recursion safeguards are defined per reaction/effect.

### 23.4 Multiple reactions from a single hit — CONFIRMED, V13.6

A hit may activate **all compatible different elemental reactions**, not just the single highest-priority reaction, if the target has the requisite states and the reactions can pay any status-consumption costs without double-spending.

For example, an Electricity hit on a target carrying both Frost and Burn can initiate both Frost+Electricity and Burn+Electricity reactions where the two do not conflict. This is a deliberate support for complex multi-element builds.

### 23.5 Same-hit state application is not normally eligible — CONFIRMED, V13.7

Default rule: a hit's reaction checks enabling statuses that **already existed before that hit**. If an Electricity sword first applies Burn to a previously unburned enemy, it does not automatically get a Burn+Electricity reaction on that same hit.

**Exception:** specifically authored powers, Augments or Evolutions may give designated attacks/reactions **same-hit eligibility** for newly applied statuses. Such permission must be explicit and does **not** silently alter unrelated triggers; especially, it does not change the Bleed Sword's required **pre-existing** Bleed for healing.

### 23.6 Authored priority for competing reactions — CONFIRMED, V13.8

All reaction candidates for a hit are evaluated, then ordered with **explicit designer-authored priority** and a **stable deterministic tie-breaker**. If multiple eligible reactions require more of the same finite state stack than exists:

1. Check candidate eligibility against the appropriate status state.
2. Sort by authored priority.
3. Give higher-priority reactions the chance to consume the required stacks first.
4. Resolve lower-priority candidates only if their conditions and remaining stacks still permit it.
5. Do not spend a stack twice.
6. Process permitted secondary chains under the same core ownership/eligibility/priority discipline.

Illustration: three Burn stacks available; Reaction X has higher priority and costs three, Reaction Y costs two. X activates and consumes all three, Y is skipped. With five available stacks both might run. The specific reaction names/priorities are **not finalized**.

Priority order is **not user-configurable** in the current selected design.

### 23.7 Per-reaction retrigger rules; no global reaction cooldown — CONFIRMED, V13.9

Every reaction defines its own eligibility frequency, including possible:

- Every qualifying hit with **no reaction cooldown**.
- Per-target cooldown.
- Stack/buildup threshold.
- Required consumption/reapplication.
- Special conditions modified by a power/Evolution.

There is **no universal reaction cooldown** across all reactions or all players. A weapon hitting 20 times per second can legitimately cause an every-hit reaction 20 times per second if conditions permit. A different powerful reaction may have a 0.25-second per-target cooldown and therefore trigger at most about four times per second under continuous hits. Those exact numbers were **illustrative**, not balancing decisions.

### 23.8 Determinism and computational limits — DESIGN CONSTRAINT

The same authoritative sequence of attack and status events must produce the same reaction selection, stack spending and ownership. Game simulation and networking should not silently drop legitimate effects when overloaded. Cosmetic VFX may be combined or reduced for readability/performance without changing combat outcomes. Actual engine choice, simulation budgets and algorithms remain OPEN.

## 24. Damage-over-time and damage snapshots

### 24.1 DoT ticks do not normally initiate reactions — CONFIRMED, V14.0

An ordinary Poison/Burn/Bleed/Electricity damage tick does **not automatically** count as a reaction-triggering direct attack. A particular source power, status, rune permission or Evolution may **explicitly authorize** its DoT ticks to trigger designated elemental reactions. That permission still respects the reaction's status, ownership, cooldown, same-hit and chain rules.

Granting DoT reaction eligibility does **not** universally grant ordinary on-hit, on-cast, attack-counter advancement, mana recovery or all other proc capabilities.

### 24.2 DoT offensive potency snapshots at application — CONFIRMED, V14.1

When a DoT is **applied**, its offensive potency is snapshotted from the applicable source properties: power rank, hero modifiers, eligible temporary buffs, attack-snapshot inheritance and other offensive terms. That application's potency **does not retroactively change** just because the source later loses the buff, gains damage or acquires an Evolution.

However, the target's **current** defense/resistance/vulnerability is evaluated on **each tick**. Actual tick damage can therefore vary over time due to target-side changes, even while the offensive snapshot is constant.

Example:

- With a temporary weapon buff active, the sword applies Bleed with an illustrative offensive base of 200 DPS.
- The weapon buff expires.
- The Bleed already applied **keeps the 200 offensive base** until that application ends or changes under its explicit stacking rules.
- If the target gains resistance, later ticks deal less actual damage; if it becomes vulnerable, they deal more.
- A new Bleed applied after the buff expires uses the new lower current offensive potency.

If a projectile was validly **activated during the buff** but lands after the buff expires, its committed attack snapshot still influences the Bleed applied at impact. Independently sourced status applications may retain different potency values according to the status's stacking model.

### 24.3 DoT status persists beyond owner death — CONFIRMED

Already-applied DoTs keep ticking after the player dies. They preserve source attribution and the snapshotted offense, while target-side defenses remain dynamic. However, owner death suppresses **new owner-dependent generated attacks** such as an explosion spawned by an on-kill effect; direct status damage continues and may legitimately finish an enemy.

## 25. Kills, on-kill recursion, and on-assist systems

### 25.1 A DoT kill is a real kill, not always a proc trigger — CONFIRMED, V14.2

If Poison's damage tick actually kills an enemy, the kill is attributed to the **Poison owner**, and shared XP/eligible progression behave normally. But an on-kill combat power activates from that DoT kill **only if the power explicitly accepts DoT kill sources**.

Examples:

- Ordinary on-kill explosion that excludes DoTs: no explosion from Poison kill.
- Specialized “Plague Detonation” Augment explicitly accepting DoT sources: Poison kill may cause an explosion.
- DoT kill after owner death: kill remains credited, but the dead owner cannot start a fresh on-kill attack.

### 25.2 On-kill generated attack chains — CONFIRMED, V14.3

An explosion caused by an enemy death may kill several others. Those kills can start more on-kill explosions **only if the receiving on-kill power explicitly allows that generated-kill source**. The same power can trigger recursively if intentionally enabled; different on-kill powers may also participate according to their individual accepted source types.

A spawned explosion does **not automatically inherit all runes, on-hit events or proc permissions** from the parent. Generated attacks have explicit tags, ancestry, owner attribution, cost/trigger eligibility and recursion safeguards. The design permits spectacular cascading effects **when intentional**; the simulation must avoid accidental unbounded loops.

### 25.3 Killing blow versus contributing players — CONFIRMED, V14.4

- The player **owning the lethal damage source** gets ordinary kill ownership and eligible **on-kill** triggers.
- Other players who contributed can qualify for **on-assist** triggers, but do not duplicate the killer's on-kill effects.
- Shared XP is unchanged by which teammate delivered the killing damage.
- Poison's source owner can get the kill if Poison tick is lethal; a teammate gets the kill if their sword lands the lethal strike, even when someone else applied Bleed first.

### 25.4 Ordinary assist eligibility and support exceptions — CONFIRMED, V14.5

A recent **offensive contribution** ordinarily qualifies for assist consideration. This may include legitimate direct damage or an effective damaging/defensive-weakening/control status under that source's rules. Healing, shielding, buffing or passive party auras **do not automatically count**.

A **specific support power may explicitly grant support-based assist eligibility** for its own meaningful support activity. For instance, a shield designed to credit the ally who protected the killer may qualify, while an unrelated always-on minor aura may not.

### 25.5 Assist windows depend on source — CONFIRMED, V14.6

The time during which a contribution remains eligible is **source-specific**, not one global stopwatch:

- Direct attack hits may have a short eligibility window.
- Bleed/Poison/Burn may maintain eligibility for an explicitly defined active-status duration or other status window.
- Control/debuff effects have their own contribution window.
- Assist-enabled healing/shielding/buffs use the exact support power's eligibility timing.

A long-lasting status is not assumed to grant credit forever; the source's exact rules determine expiration. Precise durations remain OPEN.

### 25.6 No minimum offensive damage — CONFIRMED, V14.7

**Any actual, valid offensive contribution qualifies**, if it is still inside its appropriate assist window. There is **no universal damage threshold** or “must deal at least 5% HP” requirement. One point of real damage can count just as a much larger hit can. A miss, entirely negated hit with no effective status, or expired contribution does not qualify.

A player receives **at most one assist credit per enemy death**, regardless of having inflicted multiple eligible statuses/hits or qualifying through multiple categories. Receiving assist credit still does **not** make them the owner of the lethal attack.

### 25.7 Solo and co-op on-assist compatibility — CONFIRMED, V14.8

Most on-assist-oriented powers should have useful **solo-compatible gameplay**. For example, a power might heal on the player's own kills when solo and provide additional on-assist functionality in co-op, if explicitly designed that way.

A **limited set of co-op-exclusive powers** may require another connected teammate by design. These powers are excluded from deliberately solo reward pools and pre-run selection. Their lack of a solo alternative is intentional, with the dormancy-on-disconnect rule in §21.1.

### 25.8 Historical exact-state example: consumed Bleed at death

The source-of-truth's older case remains important:

1. Player A applied Bleed to an enemy.
2. Player B consumed **all** Bleed stacks to trigger an explosion.
3. The explosion kills the enemy.
4. Player B owns the kill and relevant on-kill effects.
5. Player A's condition **“a target I am bleeding dies”** does not pass because the enemy is no longer bleeding at the death moment.
6. Player A might still receive **assist credit** if the earlier offensive contribution remains eligible, but this is a different trigger path.

### 25.9 Permission and attribution matrix

| Event/source | Damage/kill owner | Possible triggers | By default excluded |
|---|---|---|---|
| Direct sword strike | Sword user's player | Compatible on-hit, lethal on-kill, reactions | Unrelated other players' on-kill |
| DoT tick | Original status owner | Normal damage/kill; special permitted reaction/on-kill | All direct-hit procs unless specifically allowed |
| Reaction from Player B exploiting Player A's Frost | Player B | Reaction-defined effects, accepted kill sources | Duplicating Player A's attacking effects |
| On-kill explosion | Explosion's attributed player | Defined explosion damage; explicitly allowed recursion | Automatic full parent rune/proc package |
| Assist contribution | Non-killer contributor | Eligible on-assist power | Ordinary on-kill powers |
| Owner-dead continuing status | Deceased source retains attribution | Status damage and credit; living allies' allowed interactions | New combat attacks activated by the dead owner |
| Despawn/unloaded enemy | No killer | No kill/XP/proc rewards | All kill-like effects |

## 26. Shared persistent progression, currencies, and outcome rewards

### 26.1 Failure does not erase all progress — CONFIRMED, V11.4

Different permanent-progression rewards follow **different retention rules**. The game should never treat a failed run as automatically erasing every useful accomplishment. In particular:

- Permanently discovered ordinary powers, acquired Evolution recipes, and completed valid unlocks stay unlocked.
- Cumulative quests retain applicable progress if their own objective rules allow across-run completion.
- Temporary acquired in-run powers/ranks/Evolutions reset at run end.
- Ordinary/common currency is retained even when the party loses.
- Certain designated special currency is **not banked unless the party wins**.
- Some quests and unique rewards are explicitly victory-only; dying cannot satisfy a quest that requires defeating the final boss.

Retention conditions should be made understandable **before** a high-risk event, not revealed only after failure. The post-run summary should distinguish retained, unsecured/lost and victory-exclusive rewards.

### 26.2 Common currency — CONFIRMED, V11.5

**Common currency is fully retained after defeat.** It provides steady progression over many hard runs. Potential uses include unlocking heroes, weapons, rune options, capacity upgrades or other preparedness; the exact shop/cost economy is OPEN.

This is **not** the older option “retain only a percentage of common currency”; the user selected full common-currency retention.

### 26.3 Special currency — CONFIRMED, V11.5–V11.6

A designated high-value special currency is **unsecured while the run is ongoing**. It can be earned through:

1. **High-risk exploration:** rare secrets, hard optional encounters or regional threats when their rewards specify this.
2. **Final-boss victory:** an additional party victory payout, independent of collected exploration currency.

The exploration-earned special currency is permanently secured **only if the run ends in victory**. On defeat, unsecured special currency is lost. The final-boss payout exists even when the party pursued a less exhaustive exploration route; exact amounts and special-currency names/purchases are OPEN.

Illustrations such as collecting 1,200 common / 40 special currency were teaching examples, **not balance decisions**.

### 26.4 Co-op distribution depends on source — CONFIRMED, V11.7

- A local optional event can reward **its eligible participants**, not every teammate elsewhere in the map.
- A claimed rare secret can reward **eligible physically present players** under its claim rules.
- A designated world-scale/party event may award the entire party.
- A regional boss has its explicitly specified reward scope.
- The final boss grants its **team-wide victory reward** to all eligible party members.

Distribution must be disclosed by the reward source. Local rewards do not retroactively become party-wide just because the run was won.

### 26.5 Dead teammates receive full party victory rewards — CONFIRMED, V11.8

When the party beats the final boss, **every member of the party receives the ordinary team victory payout and banks their own previously earned unsecured special currency**, even if their character is dead or mid-revival at the moment the boss dies.

A dead teammate does **not** suddenly receive earlier local event/secret rewards they did not qualify for. Personal Evolution Codex discovery likewise remains personal; a teammate's evolved sword does not become everyone's permanent recipe unlock just because they won together.

The discussion has not separately resolved **disconnected party-member reward eligibility at victory**, especially players absent for prolonged periods; do not silently conflate “dead” with “disconnected.”

### 26.6 Quest/unlock philosophy — CONFIRMED DIRECTION

Permanent progression should preferentially expand **choice and knowledge**, not simply grant overwhelming meta-stat damage. Candidate unlock categories include new heroes, weapons, runes, prepared-power knowledge, rune capacity, quest milestones, unusual permanent discoveries and new build opportunities. Example quests such as “deal 100,000 damage in three seconds to unlock a rune” were **illustrative**, not approved objectives or numbers.

### 26.7 Victory vs defeat summary — RECOMMENDED UI, NOT YET APPROVED

A useful eventual post-run report would show:

- Final outcome: victory / world-collapse defeat / boss defeat.
- Common currency banked.
- Unsecured special currency lost or banked.
- Final-boss special currency payout.
- New ordinary power discoveries.
- New *acquired* Evolution recipe discoveries per player.
- Quest milestones and permanent unlocks legitimately earned.
- Warnings about local rewards not claimed or events failed, where relevant.

The exact screen layout is not approved, but the retention meanings above are fixed.

---
# PART IV — HISTORICAL DECISION LOG AND CURRENT DESIGN BASELINE

## 27. Early-era history: V0.1 through V10.6

The following is a **topic-based reconstruction** of the early discussion. The original individual V0.1–V10.6 turns are not all available as verbatim transcripts. The source-of-truth file labeled **V0.10** consolidates early preferences; a later conversation summary consolidates many subsequent choices up to **V10.6**. This log preserves meaningful developments **without inventing version numbers for them**.

### Stage E1 — The old project reveals a combat-identity problem

- Legacy *Jangan Lari* is a Phaser/TypeScript mobile-browser game with movement, enemies, projectiles, bosses, progression and UI.
- Visual/mobile recovery work was acceptable as a previous development milestone but did not resolve systemic combat variety.
- An optional manual/MOBA attack mode felt familiar yet overburdened the player when several weapon systems needed control.
- The earlier branch `newsystem/v2` offered useful chassis/ability/trigger concepts, but still lacked genuine varied melee runtime and could not safely be imported wholesale.
- Decision direction: design **a different, cohesive new game** rather than attempting to mechanically patch every old assumption. No coding now.

### Stage E2 — The new game fantasy is chosen

- Hordes, dangerous mobility-oriented encounters and increasingly extraordinary combinatorial builds.
- LoL Swarm, Jotunnslayer and Mages of Mystralia used as inspiration for *mechanical direction*, not copied code/content/UI.
- Players should form surprising attack/resource/defense loops rather than only stack damage percentages.
- A player can deliberately construct dangerous HP-consuming or unstable combinations.
- Memorable victories require both build mastery and skilled movement.

### Stage E3 — Controls, heroes and real weapons

- Top-down, 2.5D-feeling art direction with graphite/pencil drawing on white paper.
- PC priority with desirable mobile option; engine/release platforms not locked.
- Auto-aim/auto-use ordinary attacks so player can focus on movement.
- One fixed manual active ability per hero; this ability does **not** evolve directly.
- Hero/passive and separately selected main weapon; true melee arc/thrust/impact delivery, not sword-looking projectiles.
- No universal dodge roll; individual hero ability may provide movement.

### Stage E4 — Global rune and combat composition rules

- Global runes are equipped before a run, separate from ordinary in-run power rewards.
- Runes apply to all tagged/capable player-owned attacks, including suitable new weapons.
- Different abilities may fully, partially or not at all inherit main-weapon properties; full inheritance includes resource costs and drawbacks.
- Once per attack-instance rune deduplication; generated attacks do not indiscriminately copy every effect.
- Attack conceptual layers: action, delivery, payload, triggers.
- The Bleed Sword + global rune + mana-to-HP hero passive + Spinning Blade + heal on pre-existing Bleed becomes a recurring design-validation example.
- Per-activation resource costs are paid once even if many targets are hit or the attack misses after commitment. No valid target generally means no automatic draining.
- A separate child/follow-up checks its own affordability; initial mana commitment remains valid; lethal HP costs end the affected ability and kill the caster.
- Existing already committed attacks keep their temporary properties until finished.

### Stage E5 — Preparation pools, power discovery and fixed acquired capacity

- Ordinary powers become known through being encountered in runs.
- Known powers may fill the prepared opportunity pool; blank wildcard spaces draw dynamically when rewards are generated.
- A fully prepared pool receives no compulsory wildcard discovery.
- Prepared powers should eventually be offered in sufficiently long progression, subject to eligibility, but are not automatically owned.
- Rejected powers may reappear. Acquired powers are permanent commitments for that run.
- Prepared pool capacity is **not** owned power capacity.
- Unified acquired cap around **10–12 distinct Abilities, Traits and Augments** for testing; one slot per distinct power; hero active/main weapon/pre-equipped runes excluded.
- Owned powers can rank up without new slots; ranks/caps/branch exclusivity defined individually.
- At full capacity, upgrades/Evolutions remain possible; otherwise rewards can provide non-power compensation.
- Deferred reward choices retain options fixed at reward-generation time; world/co-op do not pause for selection.

### Stage E6 — The world becomes a real journey

- Hybrid procedural interconnected regions rather than a tiny flat arena or strictly fixed level chain.
- Handcrafted landmarks and boss arenas embedded in variable networks with loops/backtracking.
- Ambient and regional enemies, optional and scheduled events, reduced-pressure breathing windows.
- No normal fast travel; discovered shortcuts matter.
- Region-specific enemies/hazards and some cross-region pursuit.
- Shared physical exploration fog-of-war in co-op; permanent map revelation during the run.
- Secrets discovered through environment, not explicit “secret nearby” HUD markers.
- Calm and pressured puzzles, contextual attack targeting for mechanisms, meaningful build-dependent alternative routes.
- Ordinary secret/event power rewards obey prepared pools; designated special events may break that rule when explicitly labeled.

### Stage E7 — Events acquire real scopes and meaningful stakes

- Challenge events include area survival, defense, powerful enemy defeat, retrieval and extreme environment objectives.
- Risk tiers and failure consequences vary by event, communicated before activation.
- Participant-scoped versus party-wide rewards/failures are separately declared.
- A player physically entering an active event area before its completion counts as participant without contribution threshold.
- Difficulty scales upward when unique late participants join future phases, never retroactively alters existing monsters and **never decreases** when players depart/die.
- Support events have no objective, completion prize or failure penalty, instead granting temporary buffs/safe zones or a temporary transformation of the **existing** main weapon.
- Multiple independent events can coexist in different regions.

### Stage E8 — Normal 25-minute gateway, collapse and final boss

- Approximately 25 minutes marks the normal **gateway + World Collapse** phase, not the instant final battle.
- Gateway location is physically reachable, based on current player positions and traversable graph distance, but not trivially nearby.
- Escape combines dangerous travel, regional catastrophes, repeated elite/boss-tier pursuit, map marker and regional connection reveal, and directional compass.
- Only the gateway or intentionally triggered optional early boss-access route reaches the dedicated final boss. Early route may not exist in a particular run.
- Any one living player crossing the gateway teleports **everyone**, including still-dead bodies.
- Overworld simulation/AI/projectiles/hazards are cleaned up without kill/XP/proc rewards.
- Short sanctuary then boss fight, regardless of remaining dead teammates.
- World Collapse stops new optional events/support events/puzzles as defined, preserves already active ones and required escape mechanisms.

### Stage E9 — Evolution recipes and rotation mature

- Eligibility requires specific acquired power combinations and combat-power rank thresholds; supporting passives need ownership.
- Satisfying a recipe does not auto-evolve; Evolution appears as an **additional reward option**.
- Exactly one eligible Evolution bonus candidate per ordinary power-selection reward.
- Multiple Evolutions rotate when reward options are generated, not opened; rejected ones keep returning while eligible.
- Exclusive/compatible Evolutions are defined by recipe; deferred selections don't reroll.
- Partial unknown-recipe hints in Codex, with the exact permanent recipe-discovery trigger left as the next explicit question at **V10.6**.

**Boundary between reconstructed and individually traceable chronology:** At V10.6, the outstanding question was whether completing a recipe, seeing an Evolution offered, or **actually acquiring** the Evolution permanently discovers its full Codex recipe. The user chose **actual acquisition** at V10.7.

## 28. Exact decision ledger: V10.7–V15.1

This ledger follows the visible user choices and subsequent discussion closely. The examples accompanying each original choice remain illustrations; only the rule selected is confirmed.

| Version | User-selected decision | Meaning and consequence |
|---|---|---|
| **V10.7** | **C — Evolution permanently discovered only after acquisition.** | Meeting recipe and seeing/rejecting offer are insufficient; acquiring it records the complete recipe even if run later fails. |
| **V10.8** | **A — Personal Evolution Codex.** | Only actual acquirer gets the permanent full recipe, not other party members who witness it. |
| **V10.9** | **A — All ordinary power-selection rewards can offer eligible Evolutions.** | Level-ups, ordinary event powers and secret power selections use the single bonus Evolution rotation. |
| **V11.0** | **C — Select advanced/fusion Evolutions.** | Most Evolutions are final; exceptional evolved powers are ingredients in higher-tier recipes. |
| **V11.1** | **C — Fusion behavior defined by recipe.** | Can transform one contributor, multiple contributors or create linked interactions. |
| **V11.2** | **A — Fusion preserves original occupied slots.** | No refund, no extra slot, no implicit combination into a cheaper power. |
| **V11.3** | **A — Evolutions irreversible during run.** | Ordinary, Advanced and Fusion forms cannot be disabled, reverted or switched off. |
| **V11.4** | **C — Permanent rewards use different defeat-retention rules.** | Discoveries/unlocks can persist, some resources retained, victory-only rewards require success. |
| **V11.5** | **C — Two-tier currency risk.** | Common currency always retained; designated special currency requires victory to bank. |
| **V11.6** | **C — Special currency from exploration and boss victory.** | High-risk optional content creates unsecured currency; final boss adds separate payout. |
| **V11.7** | **C — Co-op special currency scopes depend on source.** | Local participant/claim rewards vs designated party-wide/world-scale payouts. |
| **V11.8** | **A — All party members get victory rewards, including dead.** | Dead members bank personally earned unsecured currency and receive party boss payout when party wins. |
| **V11.9** | **A — Immediate all-dead wipe.** | If no character remains alive, defeat occurs immediately; no post-wipe grace revive. |
| **V12.0** | **A — Individual deaths do not lose build/resources.** | Revived players keep powers, ranks, Evolutions, currencies and pending rewards. |
| **V12.1** | **B — Revival protection also blocks fatal auto HP-cost attacks.** | External damage blocked; affordable HP costs paid; lethal automatic activation suppressed only during protection. |
| **V12.2** | **A — Cumulative revival wait with hard cap.** | Individual death count increases wait; no decay/reset until next run. |
| **V12.3** | **A — Linear waiting-time escalation.** | Fixed additive delay per cumulative death, capped; exact tuning open. |
| **V12.4** | **B — Cooperative revival speed has diminishing returns.** | Each rescuer accelerates shared channel, later rescuers contribute less. |
| **V12.5** | **A — Fallen bodies stay at death location.** | No carrying/dragging; final gateway teleport remains exception. |
| **V12.6** | **A — Rescue path always physically reachable.** | Procedural terrain and collapse cannot permanently isolate a fallen teammate. |
| **V12.7** | **B — Corpse view or teammate spectating while dead.** | Communication/pings allowed; no new scouting, interactions or independent fog reveal. |
| **V12.8** | **A — Dead players select shared level-up powers.** | Options lock when generated; dead players can acquire/rank/evolve, but combat effects stay inactive. |
| **V12.9** | **B — Committed attacks finish; maintained effects stop.** | Valid projectiles/swings complete after owner death; no new activation, active auras/summons stop. |
| **V13.0** | **A — Applied statuses outlive owner.** | DoT/debuff duration continues; no new owner-dependent attacks during death. |
| **V13.1** | **A — Teammates exploit each other's statuses.** | Status conditions are shared for compatible interactions; source-specific ownership/modifiers stay separate. |
| **V13.2** | **C — Stacking defined by status type.** | Bleed, Poison, Burn, Frost, control and curses each specify cross-owner stacking/reapplication. |
| **V13.3** | **A — Triggering player owns cross-player reaction.** | Frost applicator enables but Electricity triggerer owns/scales reaction. |
| **V13.4** | **C — Each reaction defines consume/reduce/preserve.** | No universal rule about losing status on reaction. |
| **V13.5** | **B — Reaction chains explicitly authorized.** | Some elemental reactions may generate further reactions; not automatic for all. |
| **V13.6** | **A — One hit may activate all compatible reactions.** | Resolve each available reaction deterministically without double-spending finite stacks. |
| **V13.7** | **C — Same-hit reaction use requires explicit permission.** | Pre-existing statuses default; special powers can opt in to newly applied statuses. |
| **V13.8** | **A — Authored reaction priority and stable ties.** | Competing consumers resolve predictably; no player priority configurator. |
| **V13.9** | **B — Per-reaction retrigger rules.** | Every-hit reactions possible; other reactions may have per-target cooldown/threshold. |
| **V14.0** | **B — DoT ticks trigger reactions only with explicit capability.** | Ordinary ticks are not universal reactions/on-hit generators. |
| **V14.1** | **A — DoT offensive snapshot at application.** | Source buffs frozen in DoT application; target-side defenses/vulnerabilities recalculated each tick. |
| **V14.2** | **B — DoT kills on-kill only with opt-in.** | DoT kills count as legitimate kills; individual on-kill powers must accept source. |
| **V14.3** | **B — On-kill recursive explosions explicitly authorized.** | Generated explosion kills can chain when power definitions allow; no unconditional recursion. |
| **V14.4** | **B — Killer owns on-kill; contributors can on-assist.** | Ordinary kill-triggers exclusive to lethal damage owner; assists get separately authored effects. |
| **V14.5** | **C — Assist support eligibility opt-in.** | Offensive contributions count normally; selected healing/shield/buff powers can enable assist credit. |
| **V14.6** | **C — Assist windows source-specific.** | Hits, statuses, CC and qualifying support effects define their own credit windows. |
| **V14.7** | **A — Any valid offensive contribution counts.** | No minimum damage amount/percentage; each contributor gets max one assist credit per enemy death. |
| **V14.8** | **C — Mostly solo-compatible assist powers, some co-op-only.** | Co-op-only powers filtered out of deliberately solo prep/reward pools. |
| **V14.9** | **A — Co-op powers dormant without qualifying connected ally.** | Occupy slot, no free fallback, reactivate upon teammate reconnection. |
| **V15.0** | **A — Disconnected character stays stationary and vulnerable.** | No AI/suspension/invulnerability; normal damage/death/reconnect location. |
| **V15.1** | **C — Disconnected living character counts only during grace.** | Temporary wipe eligibility; after expiry does not prevent wipe; physically alive/vulnerable body remains if other connected survivors keep run active. |

### V15.1 detailed decision record (the latest user turn)

The preceding question contrasted:

- A: disconnected living character always counts as survivor until its physical death;
- B: only connected living characters count;
- **C: disconnected living character counts temporarily during a limited reconnect grace period, then stops counting**, unless connected living players independently keep the run alive.

**User chose C.** No duration was chosen. The choice does not revoke the earlier **V15.0** decision to leave disconnected characters stationary and vulnerable. Both rules must hold simultaneously.

**This is the current discussion stopping point. Do not proceed with a new design question in this document.**

---

# PART V — CROSS-SYSTEM INVARIANTS, VALIDATION CASES, OPEN DECISIONS

## 29. Core invariants that future design must not accidentally violate

These are game-design acceptance rules to preserve; they are **not code or a specific software architecture**.

### 29.1 Attack/source invariants

1. Per-activation costs never multiply by count of enemies hit unless the priced effect explicitly states a per-target scope.
2. Automatic attack activations normally wait for a valid target before committing resource costs.
3. Every committed attack keeps its relevant activation snapshot, including negative effects, through completion.
4. A globally equipped rune is applied no more than once per eligible attack instance.
5. A generated child does not automatically inherit unrestricted procs, runes or counters.
6. A valid cost payment that kills a caster can terminate that ability; a mana shortage after an already successful cast does not retroactively cancel it.
7. Enemy-only effects require a legitimate enemy, not merely any hitbox or mechanism.
8. Despawning/unloading an enemy does not count as a kill.

### 29.2 Reward/progression invariants

1. A prepared power is an **opportunity**, not an owned power.
2. Fully filled prepared pool means **zero forced wildcard content**.
3. Unknown ordinary powers are discovered by encountering them; unknown **Evolution recipes** are fully discovered by **actual acquisition only**.
4. Unified actual acquired-power capacity is fixed; power ranks/Evolutions do not take new slots.
5. Fusion preserves all original occupied slots.
6. Earned reward options are immutable snapshots generated when earned.
7. Evolution eligibility does not automatically force transformation; it creates a rotating bonus reward candidate.
8. No rerolls when a saved choice later becomes invalid; convert completely unusable rewards to non-power compensation.
9. Ordinary event and secret power selections use prepared pool/wildcards, unless explicitly designated as a special unique reward.
10. Permanent Codex recipes stay personal in co-op.

### 29.3 World/endgame invariants

1. The normal 25:00 threshold starts collapse/gateway escape, not immediate final victory/defeat.
2. Gateway is physically reachable, but may require dangerous travel; no automatic solved escape path.
3. Every fallen body remains accessible by some physical route despite procedural terrain changes.
4. At World Collapse, mandatory escape mechanisms remain available; no new optional events/puzzles start as specified.
5. One living gateway entrant teleports all teammates (including dead bodies) to the boss arena.
6. Overworld cleanup never grants kills/XP/healing/procs.
7. Final boss arena is not continually invaded by collapse pursuers/hazards.
8. Unavoidable damage must not be a deliberate Hard-mode difficulty substitute.

### 29.4 Status/trigger invariants

1. A teammate can exploit a valid status applied by another player.
2. Source modifiers/kill attribution are not indiscriminately transferred with status visibility.
3. The triggering player owns cross-player elemental reactions.
4. A single hit may activate several compatible reactions; contested finite stacks are not double-spent.
5. Same-hit use of newly applied statuses is an explicit privilege, not default.
6. A reaction or on-kill explosion may start secondary chains only when authorized by its definition.
7. DoT ticks do not inherit all direct-hit/on-cast proc permissions by default.
8. DoT offensive potency is snapshotted on application while target defenses stay live.
9. Statuses applied before owner death remain until normal expiration; owner-dependent **new attacks** are suppressed while dead.
10. Kill ownership belongs to the lethal damage source; non-killers can instead have on-assist effects.
11. Any valid small offensive contribution can qualify for assist within its source-defined window; no damage threshold.
12. A player gets at most one assist credit per enemy death.

### 29.5 Co-op/death/disconnect invariants

1. Shared XP does not mean shared builds, choices or Evolution Codex discoveries.
2. Personal death does not delete powers/currency or add a stat penalty.
3. Waiting-to-be-revived duration grows **linearly** per cumulative death up to cap; reset only at new run.
4. Revival requires nearby channeling after eligibility wait; preserved progress, diminishing returns for several rescuers.
5. Body stays at death location except for final gateway teleport.
6. During revival protection, external damage is blocked and fatal **automatic HP-cost activations** are suppressed, not made free.
7. Dead players may spectate and make reward choices, but cannot fight or independently scout terrain.
8. All dead party members at once means immediate defeat.
9. Winning the final boss pays dead party members as well as surviving ones.
10. Disconnected characters remain vulnerable and stationary, not protected by network-loss immunity.
11. A disconnected living character prevents eligible-survivor wipe **only for its limited grace period**.
12. Grace expiration does not kill the character or end a run that still has another connected living survivor.

## 30. Edge-case validation scenarios for later playtesting/specification

The following are **recommended validation cases**, not an approved test implementation plan. They are deliberately concrete to expose conflicts among the chosen rules.

| ID | Scenario | Expected design behavior |
|---|---|---|
| ATT-01 | Sword with paid Bleed rune hits 100 enemies in one activation | Pays per-activation rune price once; each eligible hit can apply Bleed under status rules. |
| ATT-02 | Auto-sword equipped with fatal HP-cost rune has no enemies nearby | Does not repeatedly spend HP without a valid target. |
| ATT-03 | Attack activated on valid target misses after target moves | Activation cost remains paid; no refund merely for missing. |
| ATT-04 | Spinning Blade fully inherits sword while temporary super weapon is active | Inherits explicitly defined offensive transformation and negative costs at activation; retains snapshot after buff expires. |
| ATT-05 | Main-sword bonus slash counter needs third qualifying activation; Spinning Blade is third | Spinning Blade can advance counter; generated bonus slash does not recursively advance itself. |
| ATT-06 | Child proc cannot pay cost after parent hits | Parent attack still resolves; child does not activate. |
| ATT-07 | HP payment kills caster at activation | Caster dies and affected ability ends under lethal cost exception. |
| ATT-08 | Rune reaches ability from two inheritance paths | Rune applies at most once on same attack instance. |
| ENV-01 | Contextual auto-attack hits ancient mechanism | Can activate mechanism and count relevant activation; no enemy-only lifesteal/bleed healing or kill XP. |
| WORLD-01 | Cave bridge collapses while a dead player is inside | Alternative physically traversable rescue route still exists, even if dangerous. |
| WORLD-02 | World Collapse begins with one optional event underway and another unstarted | Started event continues per policy; new optional event cannot start. |
| WORLD-03 | Single living player enters gateway with two teammates dead elsewhere | All travel to boss room, dead stay dead; no overworld pursuer remains. |
| WORLD-04 | Many enemies despawn at gateway transition | No kill/XP, DoT-on-kill, healing or reaction rewards arise from despawn. |
| REW-01 | Prepared pool is fully filled, character levels | No wildcard discovery card is forced. |
| REW-02 | Several rewards were earned, options deferred, player rank changes | Saved options do not reroll; unusable choices handled under rules. |
| REW-03 | Reward saved while an Evolution was eligible, then incompatible Evolution acquired | Saved conflicting candidate becomes invalid, without reroll. |
| REW-04 | Every saved reward option becomes unusable | Entire reward converts to non-power compensation. |
| REW-05 | Player discovers ordinary power by seeing card but declines | Ordinary power becomes permanently known for later prep. |
| EVO-01 | Player fulfills unknown Evolution recipe but dies before seeing offer | Complete recipe **not** permanently discovered. |
| EVO-02 | Player sees Evolution card but rejects it | Full Codex recipe still undiscovered; eligible Evolution can return. |
| EVO-03 | Player acquires Evolution then dies | Full personal Codex recipe remains discovered. |
| EVO-04 | Player acquires Evolution while already dead through a pending reward | Codex discovery persists; combat effect inactive until revived. |
| EVO-05 | Two players see one player's transformation | Only actual acquirer gets personal Codex recipe. |
| EVO-06 | Fusion uses two acquired abilities | Both original slots remain occupied; no extra Fusion slot. |
| DOT-01 | Poison applied under +damage buff; buff expires | Existing Poison retains snapshotted offensive potency. |
| DOT-02 | Target becomes vulnerable halfway through DoT duration | Later ticks change based on current target vulnerability. |
| DOT-03 | Poison source dies, tick later kills enemy | Kill attribution remains; owner-dependent fresh attack procs remain suppressed. |
| REA-01 | Player A applies Frost, Player B triggers Electricity | Reaction owned by Player B. |
| REA-02 | One Electricity hit meets two unrelated reactions | Both may resolve, subject to status availability and explicit rules. |
| REA-03 | Two reactions compete to consume three Burn stacks | Authored priority allocates stacks once, deterministically. |
| REA-04 | Electricity hit also newly applies Burn to unburned enemy | No same-hit Burn reaction by default; explicit ability can allow it. |
| REA-05 | Ordinary Poison tick contacts reaction-ready target | No reaction unless its source explicitly grants eligibility. |
| KILL-01 | DoT kills enemy; ordinary explosion excludes DoTs | Legitimate DoT kill, but no explosion. |
| KILL-02 | Explosion kills enemy; explosion-trigger recursion explicitly allowed | Secondary explosion can start under power-defined rules. |
| KILL-03 | Player A deals 1 HP, Player B makes lethal attack | B gets kill; A can get one assist if its contribution window remains valid. |
| KILL-04 | Player shields killer; support power has explicit assist permission | Support player can get assist under its authored contribution conditions. |
| COOP-01 | Player dies repeatedly then is revived by two teammates | Wait uses own cumulative linear/capped counter; two rescuers share progress with diminishing returns. |
| COOP-02 | Revival interrupted halfway by enemy damage | Shared channel progress persists and can resume. |
| COOP-03 | Revived at 20 HP, automatic attack costs 25 HP | During protection activation suppressed; no free attack. |
| COOP-04 | Every character dies, with uncleared DoTs still on boss | Immediate party defeat; pending DoT kill cannot rescue wiped run. |
| COOP-05 | Boss dies with two party members dead | Entire party wins; dead members get victory payout and bank own special currency. |
| NET-01 | Last remaining connected fighter dies; disconnected living ally inside grace | Run may remain active temporarily through grace. |
| NET-02 | Same scenario, grace expires before reconnect | Run defeated by no eligible survivor even though disconnected character is physically alive. |
| NET-03 | Connected living third teammate survives after another's grace expires | Run continues; disconnected character remains vulnerable, merely no longer rescue-eligible for wipe prevention. |
| NET-04 | Disconnected player's character takes lethal environmental damage | Normal death/corpse rules apply; any all-dead condition ends run immediately. |

## 31. Explicitly open decisions, balance values, and tensions

This section is important because the discussion has sometimes used detailed assistant examples with numbers. **None of these should be silently fixed without a new owner choice.**

### 31.1 Most immediate next decisions

1. **Reconnect grace period:** exact duration; whether it begins at detected connection loss or at last acknowledged input; whether reconnect restarts/pauses it.
2. **Disconnected character automation:** do existing automatic weapons continue to start new activations while player input is absent, and if so do they spend HP/mana and interact with resource/self-death rules?
3. **Host connection failure:** how a friend-hosted game can continue simulating/recover if its host disconnects; host migration/pause/end-session semantics.
4. **Disconnected victory reward:** whether an absent but still registered/disconnected party member gets the final-boss payout and secures their own currency, and what eligibility/anti-exploit rules apply.

### 31.2 Combat economy / attack semantics

5. Exact affordability aggregation and ordering for inherited rune costs, native ability costs, mana→HP conversion, refunds, damage, healing and child triggers.
6. Which ability classes inherit which main-weapon properties; explicit catalog of allowed inheritance sets and edge conditions.
7. Whether a Trait/Augment may grant inheritance to another ability, and how inheritance modifications stack.
8. Precise handling of per-pulse, per-target and follow-up cost scopes, especially self-lethal sustained effects.
9. How repeated contacts with one enemy are deduplicated per attack instance and how true melee/backtracking collisions behave.
10. Detailed status roster, stack caps, refresh durations, source ownership and control-effect boss resistance.
11. Specific elemental reaction catalog, consumption cost, priority, cooldown/trigger scope, same-hit exceptions and chained outputs.
12. Specific on-kill/on-assist proc definitions, eligible source tags, DoT and explosion recursion, true loop protection, exact assist windows.
13. How attack speed, movement speed, ability area, shield generation, sustain and resource feedback scale into late-game absurdity.
14. Physics/readability distinction between knock-up, stun, rooted, airborne collision and crowd-control immunity.

### 31.3 Powers, runes, and rewards

15. Exact starting/max **pre-run global rune capacity** and how expansions are earned. Older in-run expansion sketch conflicts with later pre-run-only rune selection; it needs explicit reconciliation.
16. Whether runes have ranks, duplicates, rare high-capacity cost, affinity limitations, or additional pre-run tradeoffs.
17. Exact number of unified owned power slots (currently 10–12 **playtest target**, not final).
18. Candidate preparation pool size, wildcard proportion UI, availability filtering and guaranteed-offer scheduling under large pools.
19. Detailed reward cadence, number of options/card UI, weights, hard/soft prerequisites, rarity and event reward overrides.
20. How unavailable saved options appear visually; value/choice form of full-invalid compensation.
21. Rank max and branch exclusivity for individual actual powers.
22. Evolution content list, recipe hints and preview disclosure, branch compatibility, advanced/fusion tree depth and rarity.
23. Whether special event unique powers can exceed normal preparation constraints in specific explicitly written ways (without violating fixed owned capacity).

### 31.4 World, events and endgame

24. Map region count/size, generation parameters, safe/dangerous traversal tuning and co-op streaming authority.
25. Enemy families, boss moveset, hard-mode modifiers and attack telegraph readability tests.
26. Gateway placement algorithm details and how to ensure physically reachable routes under collapses.
27. Exact World Collapse pressure curve, special pursuer spawning cadence, catastrophe rules per region and guaranteed normal movement routes.
28. How incomplete puzzle reset behaves when multiple players explore the same region at different times (last-person-leaves proposal).
29. Contextual mechanism targeting UI and how combat targeting resumes if the target moves/is destroyed/needs multiple hits.
30. Specific local secret claim interaction and how to prevent accidental denial of rewards to present teammates.
31. Which events can be failed/abandoned during gateway transition, and exact disclosed penalties.
32. Early boss access appearance frequency, chains, cost and reward implications.
33. Fixed sanctuary length, final-boss phase structure, resource reset exceptions if any, and what the pre-boss cutscene can/cannot pause.

### 31.5 Co-op, death, reward, networking

34. Initial revival wait, per-death increment and cap.
35. Base revival channel time, diminishing-return multiplier curve, interruption causes/range, interaction under simultaneous damage.
36. Post-revival protection duration, partial HP value and whether it has any exceptions for internal non-attack damage.
37. How contact-damage shared interval and revival protection interplay with DoTs/debuff application.
38. Exact status of disconnected **dead** bodies, revival and reconnect handoff; whether automatic recast is active while disconnected.
39. How to treat a briefly absent player in event participation, scaling, and source-scoped rewards.
40. Invite/late-join, permanent leave, return-to-session and reconnect identity behavior; party size limits.
41. What happens to host-friend multiplayer sessions if nobody is connected, without violating chosen grace and world vulnerability rules.
42. Solo-compatible fallback specifics for each hybrid on-assist power, and the availability state of a co-op power when the only other teammate is dead but still connected.

### 31.6 Meta progression, economy, art and implementation

43. Actual names, sources and purchase sinks for common/special currencies; inflation, player incentive and unlock gating.
44. Which quests grant content vs currency; what explicitly requires victory; cross-run unlock pacing.
45. Permanent unlock design without turning the meta game into raw damage that erases challenge.
46. Exact art palette, hand-drawn production constraints, layering, VFX budget, animation workflow, accessibility options.
47. PC/multiplatform launch strategy, engine, online architecture, deterministic co-op simulation and save-data approach.
48. Performance budget methodology for hundreds/thousands of enemies, chain explosions, persistent statuses, multiple regions and co-op spectators.
49. Explicit source-of-truth format, future change-management process and tooling for versioned tests/reviews once implementation is authorized.

## 32. Historical supersessions and non-decisions to prevent accidental drift

| Earlier sketch / tempting assumption | Current authoritative rule |
|---|---|
| Early short mobile-first ~7-minute run | Normal 25:00 gateway/collapse, then escape and final boss; total can exceed 30 min |
| Mobile-first/tank-arena/Diep.io as defining product | New PC-prioritized PvE roguelite with optional friends co-op and graphite art |
| V3 manual active attack controls under investigation | Routine auto-target/auto-activation and one fixed hero-specific manual active ability |
| Fixed main weapon per hero / tank classes | Hero chosen independently from one main weapon |
| Universal support weapons are projectiles | Can be melee, orbiting, area, ranged and other genuine attack formats |
| Runes chosen from ordinary level-up pool | Globally equipped before run, separate from power rewards |
| V3 proposed in-run rune expansion and 2→3→4 slot values | Rune capacity expansion concept accepted; precise permanent/in-run timing and numbers unresolved; rune equipment is pre-run |
| One status always one pool / every source always separate | Status-specific stacking and ownership behavior |
| Default one major elemental reaction per hit (old V3 proposal) | Multiple distinct compatible reactions can activate on one hit, resolved by authored priorities |
| Same-hit newly added statuses may always react (old proposal) | Pre-existing statuses required by default, with explicit special exceptions |
| Reactions cannot chain / all reactions chain freely | Only specifically authorized reaction-to-reaction chains |
| All DoT ticks trigger everything | Only explicitly permissioned DoT reaction/on-kill sources |
| All attacks can trigger all on-kill effects | Owner/source-specific kill trigger permission; assist category distinct |
| Reward generated when player opens card | Generated/snapshotted when reward is earned |
| Prepared pool guarantees every selected power is owned | It only promises eligible offer opportunities with sufficient progression |
| Evolution discovered when recipe completed/offered | **Only actually acquiring Evolution** unlocks full personal Codex recipe |
| Every Evolution is always one final tier | Most are; specially designed Advanced/Fusion Evolutions exist |
| Fusion merges powers and refunds a slot | Original slots remain occupied; no refund |
| Evolutions can be toggled back | Permanent for remainder of run |
| All currency lost on defeat / special currency only boss payout | Common retained; unsecured special from exploration plus boss payout secured by victory |
| Only living players get final payout | **All party members including dead** receive boss payout and bank their own special currency |
| Dying strips powers/adds debuff | No extra progression/resource loss; rescue/timing is the penalty |
| Bodies can be dragged or rescue routes can be sealed | Bodies fixed, and at least one physical rescue route preserved |
| Dead players cannot meaningfully participate in choices | They can spectate and choose their locked power rewards; no combat |
| Owner death removes every status | Existing statuses persist until natural expiration |
| Support always earns assist | Support contribution only with explicit assist eligibility |
| Disconnected player automatically invulnerable/suspended/AI-controlled | Remains stationary and vulnerable in actual world |
| Disconnected living character counts forever or never | **Counts toward party survival only for finite reconnection grace** |

## 33. Glossary

**Acquired power:** An Ability, Trait or Augment actually selected/owned in the current run, costing one of the fixed unified slots. Not to be confused with a prepared candidate.

**Advanced Evolution:** Rare higher-stage transformation whose recipe includes an already acquired Evolution.

**Assist credit:** Qualification of a non-killing contributor for separately authored on-assist powers; does not convey ownership of lethal damage.

**Attack instance:** One distinct committed activation or attack event with source identity and explicit inheritance/cost/trigger behavior. May hit multiple targets.

**Attack snapshot:** Offensive properties/cost context fixed for a committed attack when it begins, surviving later temporary-buff expiration until completion.

**Candidate power pool:** The pre-run collection of known Abilities/Traits/Augments allowed to be offered during this run, plus any unfilled wildcard spaces.

**Committed attack:** An attack activation whose validation/price has been resolved and which may complete despite subsequent resource/buff changes, subject to the lethal HP-cost and death rules.

**Common currency:** Permanent progression currency retained even after failure.

**Co-op-exclusive power:** An explicitly cooperative power excluded from deliberate solo run generation and dormant without a qualifying connected teammate.

**Corpse reachability:** Invariant that dynamic geography always preserves at least one physical route for living rescuers to each fallen teammate.

**Damage-over-time / DoT:** A status or effect that deals periodic damage after application; offensive value is snapshotted when applied and target defenses evaluated on each tick.

**Deferred reward:** An earned but not yet chosen power offer, with options fixed when it was generated.

**Elemental reaction:** A rule requiring designated statuses/effects and an eligible triggering attack; can consume/reduce/preserve, chain or retrigger only according to authored permissions.

**Evolution:** Major transformation of an existing active power, acquired by choosing a bonus option after satisfying a specific recipe; permanent for that run, no new slot.

**Evolution Codex discovery:** Permanent personal knowledge of full recipe gained **only on acquisition**, not on mere eligibility or offer.

**Fusion Evolution:** Exceptional transformation with one/multiple evolved ingredients; can transform a primary, multiple contributors or their link; original slots stay occupied.

**Global rune:** Modifier equipped pre-run and applied to every eligible player-owned attack by capability tags, once per attack instance.

**Maintained effect:** An aura, continuous source or summon requiring an active living owner; deactivates on owner death under the current rule.

**On-assist effect:** Explicit power activated because a qualifying non-killer contributed to an enemy's defeat.

**On-kill effect:** Explicit power activated because that player's owned attack/status source dealt lethal damage and the effect accepts its source type.

**Prepared power:** Known ordinary power preselected as a candidate to be offered, not granted at spawn.

**Reaction priority:** Designer-authored ordering and stable tie-breaker for competing reaction consumption of limited statuses.

**Revival wait:** Mandatory eligibility delay after individual death, growing linearly with cumulative personal deaths to a cap, distinct from channel duration.

**Revival channel:** Physical teammate interaction performed after waiting is finished; shared progress is preserved through interruption; multiple rescuers accelerate with diminishing returns.

**Special currency:** Valuable progression currency collectable through high-risk optional content and boss victory, but exploration-earned portion only banked if party wins.

**Status source attribution:** Ownership of who originally applied an effect and/or caused lethal damage; retained even when conditions are visible to all teammates.

**Survival grace period:** Limited time after a disconnect during which a physically alive but disconnected character can still prevent a party wipe when no connected living players exist; after expiry they no longer count, although their character remains vulnerable in the world.

**Wildcard:** An unfilled pre-run candidate-pool space filled from eligible broader content at actual reward generation, not preselected at run start.

**World Collapse:** Catastrophic post-25:00 overworld phase with regional disasters, boss-tier pursuit and physical escape to the final gateway; ends when party crosses gateway or fails.

## 34. Guidance for the next design conversation

1. **Read this document first** and treat its explicit `CONFIRMED` rules as the working baseline.
2. Do not turn illustrative values, example spells, assistant recommendations or older handoff proposals into content approvals.
3. Preserve the user-selected V15.1 disconnect-grace choice alongside V15.0 stationary/vulnerable disconnected characters and V11.9 immediate all-dead wipe.
4. Continue with one meaningful unresolved design decision at a time when the owner asks to continue.
5. Do not write or modify the game's source code, create branches, merge repos or issue implementation commands without separate explicit authorization.
6. As decisions advance, update this Markdown **with versioned changes**, open-question status and any superseded rules rather than overwriting historical context.
7. Before implementation, convert invariants into bounded, testable acceptance criteria, deterministic test cases, profiling goals and human-playtest gates. Those steps are **future work**, not current consent.
8. The most natural next unresolved discussion topics are the precise reconnection grace period, automatic attacks while disconnected, host-disconnect behavior or victory eligibility for disconnected party members. **No choice on those topics has yet been made.**

---

**End of consolidated design record — V15.1.**  
**Latest confirmed user choice:** *C. Disconnected living characters count as party survivors during a limited reconnection grace period, then no longer prevent a wipe. Their stationary characters remain vulnerable. If another connected player is alive, the game continues.*
