# Game Design Specification (GDS)

**Project:** The new Unwritten / unfinished-world PvE game; commercial title not finalized.  
**Design baseline:** V42.6 plus owner decisions OWNER-T01–T04 and reconfirmed V42.4 acceptance coverage.\
**Document edition:** V42.6 / R1 with the planning-baseline supplement, 2026-11-25.\
**Companion:** [Game Design Document](GDD.md).  
**Purpose:** Define player-visible behavior, content, starting values, interaction requirements and gameplay acceptance checks. [Current authorization](../AGENTS.md#agents-phase)

> This is a new compilation. The previously generated `game-design-specification.md` was not used as its source or copied into these documents. The recoverable approved discussion and earlier design handoffs form the source basis.


## Contents

- [Document authority and reading contract](#gds-authority) · [Owner decisions](#gds-owner) · [Provisional rules PR01–PR12](#gds-rules) · [Reconciliation register](#gds-reconciliation)
- [1. Product and session contract](#gds-session)
- [2. Controls, movement and targeting](#gds-controls)
- [3. Combat events, inheritance and causal resolution](#gds-combat)
- [4. Health, barriers, recovery and death](#gds-survival)
- [5. Cooperative play, rescue and participation](#gds-coop)
- [6. Hero catalog](#gds-heroes)
- [7. Main weapon catalog](#gds-weapons)
- [8. Global rune and status catalog](#gds-runes)
- [9. Acquired powers, rank milestones and all 36 Evolutions](#gds-powers)
- [10. Advanced Fusion system and six complete recipes](#gds-fusions)
- [11. World, geography, realms and final transition](#gds-world)
- [12. Regional enemies and elites](#gds-enemies)
- [13. Regional bosses and blessings](#gds-regional-bosses)
- [14. Universal invaders and catastrophe Hunters](#gds-hunters)
- [15. The Forgotten Creator and final victory](#gds-final-boss)
- [16. Environmental objects, momentum and hazards](#gds-environment)
- [17. Optional events, quests and encounter scope](#gds-events)
- [18. Friendly NPCs, services and bargains](#gds-npcs)
- [19. Pickups, restoration and resource availability](#gds-pickups)
- [20. Permanent progression, currencies and discovery](#gds-progression)
- [21. XP, progression pacing and overflow](#gds-xp)
- [22. Challenges, records and balance validation](#gds-challenges)
- [23. World difficulty, regional and cooperative scaling](#gds-scaling)
- [24. Visual direction, audio, HUD and accessibility](#gds-presentation)
- [25. Onboarding and post-run experience](#gds-onboarding)
- [26. Narrative foundation and content boundaries](#gds-narrative)
- [27. Full-content prototype scope and acceptance](#gds-prototype)
- [28. Revision and supersession register](#gds-revisions)
- [29. Open-detail and source-gap register](#gds-open)
- [30. Decision coverage map and glossary](#gds-traceability)

### Catalog shortcuts

**Heroes:** [The Undying](#catalog-h01) / [The Acrobat](#catalog-h02) / [The Conductor](#catalog-h03) / [The Chronomancer](#catalog-h04) / [The Gravity Weaver](#catalog-h05) / [The Summoner](#catalog-h06) / [The Bloodbound](#catalog-h07) / [The Alchemist](#catalog-h08) / [The Architect](#catalog-h09)

**Weapons:** [Sword](#catalog-w01) / [Bow](#catalog-w02) / [Magic Staff](#catalog-w03) / [Spear](#catalog-w04) / [Warhammer](#catalog-w05) / [Twin Daggers](#catalog-w06) / [Chakram](#catalog-w07) / [Chain Whip](#catalog-w08) / [Arcane Focus](#catalog-w09)

**Acquired powers:** [Spinning Blade](#catalog-p01) / [Sketch Familiar](#catalog-p02) / [Runic Mine](#catalog-p03) / [Spectral Lance](#catalog-p04) / [Battle Tempo](#catalog-p05) / [Sharpsight](#catalog-p06) / [Vital Exchange](#catalog-p07) / [Fracture](#catalog-p08) / [Death Bloom](#catalog-p09) / [Echo Strike](#catalog-p10) / [Collision Burst](#catalog-p11) / [Reprisal Pulse](#catalog-p12) / [Ricochet Shard](#catalog-p13) / [Arcane Tether](#catalog-p14) / [Spatial Reach](#catalog-p15) / [Lingering Essence](#catalog-p16) / [Momentum Charge](#catalog-p17) / [Converging Strikes](#catalog-p18)

**Fusions:** [Seismic Arsenal](#catalog-f01) / [Infinite Domain](#catalog-f02) / [Thermal Equilibrium](#catalog-f03) / [Relentless Chorus](#catalog-f04) / [Grave Resonance](#catalog-f05) / [Sanguine Aegis](#catalog-f06)

## Document authority and reading contract
<a id="gds-authority"></a>

The GDD governs experience, intent, thematic identity and design priorities. This GDS governs gameplay and content. Apply the latest explicit owner decision within its scope and record it in the governing section. For an uncovered conflict affecting confirmed gameplay, preserve the confirmed rule, record both sources and obtain owner disposition before changing it. For genuinely unresolved details use OWNER-T04. The TDS governs architecture, the QAS governs verification, AGENTS governs authority to act and the implementation plan governs delivery. [Document responsibilities](GDD.md#gdd-authority)

Status vocabulary:

| Label | Meaning |
|---|---|
| **CONFIRMED** | An approved mechanical or content decision preserved in the recoverable record. |
| **BALANCE TARGET** | A numerical value approved for initial testing, not a measured or release-validated value. |
| **DELEGATED TUNING** | A coefficient may be chosen provisionally during balancing without reopening the underlying mechanic. |
| **PROVISIONAL PROTOTYPE RULE** | A versioned, adjustable behavior for a genuine gap under OWNER-T04. Each entry identifies the source, choice, rationale, adjustment and test. Its final design status awaits owner playtesting. |
| **OPEN - DEEP DETAIL** | A specific behavior or authoring detail was deliberately left unresolved. It is not permission to invent a new permanent rule. |
| **OPEN - SOURCE GAP** | A prior approval references material not visible in the recoverable source. The approval is preserved, but its missing contents are not fabricated. |
| **DERIVED** | A calculation, consistency consequence or test case derived from approved rules, not a new decision. |
| **SUPERSEDED** | A prior direction explicitly replaced by a later approval. It must not return accidentally. |

Unqualified operative requirements in the main specification are CONFIRMED, except that numerical starting values are BALANCE TARGETS and registered prototype rules and open details retain their indicated status. Recommendations that were never selected, missing interactive widgets, fictional UI statistics and alternative options are not requirements.

### Source basis and traceability

- **DISC:** The available approval dialogue, principally V21-V42.6 and its visible earlier decisions. Version references such as `V39.12` identify the approved discussion, not software versions.
- **M15:** `game-design-master-v15.1-full-discussion.md`, recoverable in this repository with `git show 0f1c618:game-design-master-v15.1-full-discussion.md`. This preserves early product decisions, preparation pools, reward freezing, gateway behavior, revival, disconnects and combat ownership through V15.1. Its own early reconstruction limitations remain applicable.
- **E010:** `new-game-design-source-of-truth-v0.10.md`, inspected directly for early design intent and cost semantics, with later decisions taking precedence.
- **P27:** The confirmed product-constraints section of `A-Game-I-Actually-Play_Technical-Architecture-Blueprint_V27-draft.md`, inspected directly. Its engine shortlist, networking architecture, software contracts and milestones are proposals, not requirements imported here.
- **Owner planning supplement, 2026-11-25:** Accepts the revised architecture as a working baseline for planning, records OWNER-T01–T04 and reconfirms the V42.4 categories and complete-run conditions. It adds no production verification evidence.
- Legacy mobile/PvP tank notes, research recommendations and old implementation backlogs do not override the new PvE/co-op design.

This compilation preserves supported decisions rather than claiming to be a verbatim export of every conversation turn. Early V0-V10 numbering is incomplete; V15.2-V20 is not available as a full decision transcript. Where later approvals or source handoffs preserve a rule, that rule is included. Missing exact content is registered at the end.

<a id="gds-owner"></a>

### Owner decisions after V42.6

| Decision | Governing gameplay requirement | Working contract |
|---|---|---|
| OWNER-T01 · Original-host recovery | Suspend on loss of the original host. Allow 180 seconds for its return and up to 30 additional seconds to synchronize after a timely return. Only the recovered original authority may resume after reconciliation. If recovery fails, end the interrupted run, preserve settled progression and reconcile recoverable authorized rewards. Automatic host migration and invented victory payouts are excluded. | [Cooperative play](#gds-coop) · [Recovery protocol](TDS.md#tds-host) |
| OWNER-T02 · Prototype connectivity | Native Windows LAN/direct IP is sufficient for full cooperative gameplay. Practical browser compatibility is secondary. Browser multiplayer, mandatory accounts or relays, dedicated hosting and convenient Internet matchmaking fall outside the readiness requirement. | [Transport and authority](TDS.md#tds-network) |
| OWNER-T03 · Hybrid durability | Commit important permanent rewards immediately. Batch ordinary enemy currency within a bounded interval. Settle all eligible earnings at ordinary defeat or graceful completion. Reconcile recoverable outstanding grants idempotently across sessions. | [Currency and crash exposure](#gds-durability) · [Issuance and receipt protocol](TDS.md#tds-save) |
| OWNER-T04 · Provisional rules | Agents may record and test a temporary compatible rule for a genuinely unresolved detail. The grant covers the decision process. Individual defaults remain provisional and confirmed gameplay takes precedence. | [Prototype rule register](#gds-rules) · [QA triage](QAS.md#qas-triage) |

### Non-negotiable interpretation

A bounded effect is not necessarily weak. A global prohibition on legitimate chains is not a substitute for explicit event eligibility. A content name does not grant hidden capabilities: Spectral Lance is not automatically spectral-compatible; magical damage is not automatically ground-penetrating; a shield-shaped effect is not automatically a personal barrier.

A source-specific limit applies only to the relevant mechanic. Statements such as "no universal damage cap" do not remove authored amplification caps, hit intervals, finite lifetimes, population limits or source-specific spatial restrictions.

## 1. Product and session contract
<a id="gds-session"></a>

**Basis:** M15 sections 1-4, 11, 19; V21-V26; V33; V37; V40; V42.

The game is a top-down/oblique, sprite-based, 2.5D-feeling fantasy PvE roguelite supporting solo and friend-based cooperative runs. It is a distinct product from the existing Jangan Lari reference game, not a mandate to replace that game's runtime or reproduce the earlier Diep-like tank/PvP concept. Native Windows PC is the prototype target. Browser compatibility is desirable where practical and mobile support remains a longer-term desire. Commercial release platforms remain open. The art direction does not mandate a true 3D engine.

A normal run consists of preparation, physical exploration, automatic combat with manual hero actions, individual build development, optional encounters and regional bosses, and a voluntary final encounter. At world time **25:00**, World Collapse begins and the normal final gateway becomes available. The player can travel to the gateway and seek victory, or continue surviving the escalating world. There is no automatic defeat timer, shrinking playable boundary or maximum catastrophic tier.

The target for a typical successful Normal Mode run is **25-40 minutes**. Early victories and substantially longer adventures are valid. An authored early-access discovery may permit an intentional final-arena transition before 25:00; it is not guaranteed in every procedural world and skips the Collapse escape stage. PR04 provides the prototype discovery route and its accessibility controls. [Provisional rules](#gds-rules)

### 1.1 Run preparation

Each player selects a hero, one main weapon, globally equipped runes, and a candidate pool of known/eligible powers with any permitted wildcard spaces. Main weapon selection is independent of hero. Each hero has one innate passive and one fixed manually activated ability. The hero ability is not itself a standard acquired-power Evolution, although compatible modifiers may change its use.

The initial full-content roster is **9 heroes, 9 weapons, 5 runes, 18 acquired powers, 36 standard Evolution forms and 6 Advanced Fusions**. These are content counts, not items granted at run start. Three heroes, three weapons and three runes are starter choices. Unlocking content expands available choices rather than raising its inherent baseline tier.

### 1.2 Capacity and permanence

| Layer | Capacity / commitment |
|---|---|
| Hero | One selected hero; passive and manual ability outside power capacity. |
| Main weapon | One selected weapon, independent of hero; outside power capacity. |
| Global runes | Two fixed slots; different runes only; selected before the run, no ordinary mid-run swap. |
| Acquired powers | **10 distinct slots**, shared across independent attacks, traits and trigger powers. |
| Power ranks | Five ranks per power; a rank increase uses no additional slot. |
| Standard Evolution | Retains the base power's one slot; one mutually exclusive standard form per base power per run. |
| Fusion | Combines two specific evolved components and retains both occupied slots. |
| Regional blessings / Catastrophe Essence | No acquired-power slot. |
| Overflow statistical rewards | No acquired-power slot; individually bounded. |

Powers cannot be sold, removed, replaced or swapped to reclaim capacity during a normal run. Evolutions and Fusions cannot be toggled off or reverted. A fused component cannot be reacquired separately or used in a second simultaneous Fusion. Multiple disjoint Fusions may coexist; recursive Fusion tiers are not part of the approved design.

Early wording allowed "up to two" while later roster discussions said "exactly two." Two distinct slots are confirmed. PR01 governs whether either may be empty in this prototype. Fully populated loadouts give **810** combinations using `9 heroes * 9 weapons * C(5,2)`. [Provisional rules](#gds-rules)

### 1.3 Prepared candidate pools and discovery

The candidate reward pool is distinct from the ten powers actually acquired. Preparing a power makes it eligible to be offered; it does not grant ownership during the run. PR03 sets the provisional pool size. Earlier examples of 20 or 50 spaces were illustrative.

Filled preparation spaces refer to known and otherwise eligible content. Blank spaces are genuine wildcards drawn from eligible broader content **when a reward is generated**, not a hidden list rolled at run start. A fully filled prepared pool receives no forced wildcard substitutions. A declined prepared power may appear again. Eligible prepared powers should receive eventual offer opportunities given sufficient progression, without a promise of automatic acquisition or of being seen before an early defeat. PR03 sets the current offer schedule. [Provisional rules](#gds-rules)

Seeing an ordinary power can record knowledge of it; acquisition is not required merely to recognize it. **Knowledge is not ownership:** for the six expanded powers, the approved discovery accomplishment and permanent-currency unlock govern future availability. The relationship between wildcard encounter knowledge and those specific unlock accomplishments must not silently make every locked power purchasable merely by seeing it. PR02 defines fresh-profile access and preserves the six named discovery and ownership paths. [Provisional rules](#gds-rules)

### 1.4 Reward generation and choices

Each level grants one ordinary power selection. Shared party XP produces shared levels, but each player receives their own choices. Ordinary event/secret power rewards and appropriate merchant rewards use the same preparation and eligibility framework. Explicitly designated special events may offer outside-pool content; ordinary rewards may not silently do so.

Options are generated and frozen **when the reward is earned**, not when its panel opens. Players may accumulate multiple pending rewards and choose later in real time. Opening, closing, relocating, changing a build or dying cannot reroll them. The eligible Evolution rotation advances on reward generation. Multiple eligible standard Evolutions rotate through **one bonus Evolution option per ordinary selection**; the player chooses one reward total. Fusion becomes eligible in subsequent reward selections without a consumable catalyst. Declined eligible transformations can return. PR03 specifies the prototype card budget and separate rotations when both kinds qualify. Recheck the required retained catalyst property before selection. [Provisional rules](#gds-rules)

Owned eligible powers appear as next-rank upgrades rather than duplicate acquisitions. A max-rank, conflicting or otherwise invalid choice cannot be taken. At full capacity, rank upgrades, eligible transformations and applicable alternatives remain available. If all choices in an old frozen reward become unusable, convert the reward to non-power compensation rather than rerolling its original options. Exact compensation is delegated tuning, with category details open where they change reward identity.

Contextual Reward Distribution balances new acquisitions against upgrades using capacity and eligibility; it does **not** favor a desired recipe or selected build goal. Recipe inspection is passive through the Codex/build panel. Automatic build tracking, recommendation markers and compatibility-warning assistants are deferred, not approved initial features.

## 2. Controls, movement and targeting
<a id="gds-controls"></a>

**Basis:** M15 sections 3, 5, 8, 10; V21.11-V21.14; V23 input revision; V35.3; V37 weapons; V39.14-V39.16; V40.19.4 and V40.19.7.

Routine weapons and acquired automatic attacks select targets and activate automatically. The player controls movement, positioning, manual hero ability use, interactions and build choices. No universal dodge-roll is required. A hero-specific dash or Vault remains a distinct ability rather than a mandatory global action.

Controls are rebindable, including mouse-focused movement with minimal keyboard use and keyboard-plus-mouse movement. The originally discussed right-click movement and left-click targeted-ability behavior are defaults, not compulsory mappings. Left-click movement, arrow-key movement and other player configurations must be supportable. Interaction is a separate rebindable action, initially presented as **E**; movement clicks are not overloaded with automatic NPC, gateway or revival interaction.

When the reward side panel is open, movement remains possible on visible ground through the configured movement action. Selecting a reward must not accidentally cast a hero ability. Focus, UI hit testing and remapping must preserve that separation. Ordinary panels and dialogue do not pause combat or grant invulnerability.

### 2.1 Movement contract

All heroes share the same unmodified movement speed. The reference is **100 movement units/second**, a relative balance scale rather than an engine-specific pixel/world-unit commitment. Most ordinary enemies are slower; specialized pursuers may match or exceed that speed. Terrain use, attacks and control provide alternatives to mandatory movement upgrades.

Movement remains unrestricted during ordinary weapon attacks, including preparation and execution. Attacks do not automatically lunge the player, slow them or redirect movement unless an explicitly authored mechanic says so. Attack orientation is independent of movement direction. Direction changes are responsive, diagonal travel has no unintended speed advantage, and there is no excessive baseline inertia. Movement bonuses do not automatically increase projectiles, force or attack frequency.

Enemies retain natural overlap and do not form impenetrable body-blocking walls around the player. Ordinary contact damage is a separate authored threat with a **shared contact-damage interval** to prevent many overlapping enemies applying uncontrolled instantaneous hits. It is not universal immunity from projectiles, fields, hazards or other independent attacks. Genuine forced collisions between compatible entities remain possible under the physics rules; ordinary overlap is not automatically an impact.

### 2.2 Automatic targeting

Eligible hostile creatures have primary priority. Nearest valid hostile is the default unless the attack has a more specific authored rule. Selection requires appropriate knowledge, spatial eligibility and range; it does not reveal hidden enemies or guarantee contact. Automatic attacks normally wait for a valid target rather than repeatedly spending resources into empty space. Freely directed/manual area abilities may validly activate without an enemy.

| Target | Automatic fallback when no eligible hostile is in range | Deliberate target |
|---|---|---|
| Supply container | Yes | Yes |
| Fragile barricade | Yes | Yes |
| Brittle pillar | No | Yes |
| Volatile crystal | No | Yes |
| Unstable machinery | No | Yes |
| Discovered sealed cache | Yes | Yes |
| Undiscovered secret | No | No automatic identification |
| Protected structure | No | No destructive targeting |
| Ordinary interactive mechanism | No damage-target fallback | Interaction; explicitly compatible precision attack where authored |

Dangerous objects may still receive genuine incidental attack damage. Deliberate object targeting uses configurable controls. For precision mechanisms, contextual interaction can direct the next eligible automatic attack at the object, then normal targeting resumes. Range, timing, resource costs, geometry and interception still apply; it is not an invisible free switch activation. An object hit may count toward an activation-based counter, but not creature-only lifesteal or on-kill effects.

### 2.3 Accuracy and precision

There is no random hit/miss roll after genuine eligible geometric contact. Base Bow, Ink Dart and Spectral Lance delivery aims directly at current target position; predictive aiming must come from compatible mechanics such as Sharpsight. Projectile guidance is separate from prediction and initial directional accuracy. "100% aiming accuracy" does not guarantee interception of a moving target, homing, range, penetration or immunity bypass.

There is no universal random critical-hit statistic. Enhanced precision damage requires explicit mechanical conditions: a real exposed weakpoint, a qualifying direction, a specified sequence or a vulnerability. Each condition uses normal damage categories and source identity. A name or decorative highlight cannot manufacture an independent source.

## 3. Combat events, inheritance and causal resolution
<a id="gds-combat"></a>

**Basis:** M15 sections 5-6, 23-25; V28-V38 content; V39.1-V39.21.

### 3.1 Functional attack model

Every combat action distinguishes **Action** (activation and owner), **Delivery** (trajectory or hit geometry), **Payload** (damage, statuses, force, costs and other effects) and **Triggers** (conditions for follow-ups). These are gameplay responsibilities, not mandated software classes.

An attack activation, each hit, damage component, status application, reaction, elimination and generated child are distinct. Inheritance is explicit and capability-based. Full main-weapon inheritance can include damage, statuses, compatible rune effects, drawbacks and resource costs while preserving the recipient's native delivery. Partial inheritance transfers only named properties. Generated attacks do not automatically inherit every on-hit, on-kill, rune, counter or resource effect of their parent.

A global rune applies once to each qualifying attack instance; multiple inheritance routes cannot duplicate the same modifier or cost on that instance. A separate child activation can have its own legitimate price. Existing Sword/Spinning Blade shared every-third-attack counter semantics are preserved: qualifying activations contribute to the shared counter; its generated bonus attack does not increment the same counter or trigger itself. The exact qualifying activation definition for a continuous orbit remains open, rather than treating every contact or visual frame as a new cast.

### 3.2 Offensive snapshots and live target state

An attack snapshots its applicable offensive properties at activation. Later buff expiration, a new rank or a transformation does not retrospectively rewrite it. A committed projectile can apply a status using its inherited offensive snapshot even if its source buff expired before impact. Target defense, resistance and vulnerability are evaluated when damage actually resolves.

Damage-over-time offense snapshots at application. Individual reapplication rules determine whether later applications change that snapshot; no universal strongest/last snapshot rule has been approved. Explicit evolving properties such as Burn intensity, Rebound Momentum or Ascending Pierce can change under their own rules. A temporary main-weapon transformation can be inherited by an explicitly compatible secondary attack, including costs; subsequent activations after expiration use the restored current weapon.

### 3.3 Event definitions and default trigger assignments

| Event | Meaning |
|---|---|
| Attack Activation | A validated action has committed. |
| Genuine Contact | Actual compatible geometry overlaps or collides. |
| Successful Hit | An eligible attack is accepted rather than completely rejected by hit prevention. |
| Successful Damage | Positive personal-barrier damage and/or actual HP damage. |
| Barrier Damage | Capacity genuinely absorbed through damage, not expiration/clamping. |
| HP Damage | Actual health removed, excluding overkill. |
| Status Application | An accepted new status or eligible refresh. |
| Displacement | Real forced movement, not intended force against an immovable target. |
| Collision Impact | A qualifying new physical collision. |
| Elimination | One valid attributed defeat in a combat lifecycle. |
| Barrier Depletion | Complete consumption by eligible damage. |
| Natural Expiration | An effect completes its authored lifetime. |
| Near Miss | A genuinely threatening attack narrowly avoided under authored geometry. |

| Mechanic | Required baseline outcome |
|---|---|
| Battle Tempo, Fracture, Echo Strike | Qualifying successful hit. |
| Bleed, Flame, Frost | Eligible successful hit plus accepted relevant status application. |
| Lightning | Eligible successful hit. |
| Force | Eligible successful hit; actual displacement is separately required by displacement reactions. |
| Vital Exchange / player Soul Harvest blessing | Actual eligible hostile HP damage, not barrier damage or overkill. |
| Converging Strikes | Successful damage from distinct eligible owned sources. |
| Death Bloom / Life Harvest | Qualifying attributed elimination. |
| Reprisal Pulse | Genuine hostile HP or personal-barrier damage. |
| Collision Burst | Eligible displacement and actual impact. |
| Final Resonance | Eligible natural expiration. |
| Aegis Release | Hostile depletion of the specifically associated fortified barrier. |
| Grave Imprint | Genuine residual blossom damage. |

Each requirement is necessary, not sufficient: source permission, ownership, cooldown, available status/charge and geometry also apply. Damage immunity removes damage-based eligibility; separately compatible non-damaging effects require their own permission. Interception by a wall is not a hit on the enemy behind it. Ordinary DoT ticks are not weapon activations and do not inherit universal on-hit or elemental reaction permission. Explicit effects may authorize designated DoT or generated-kill reactions.

### 3.4 Staged causal resolution

Use the following gameplay order for each originating combat event:

1. Capture relevant **pre-existing** target conditions.
2. Complete the originating damage and record actual barrier/HP outcomes.
3. Confirm lethal outcomes and elimination ownership.
4. Evaluate eligible hit effects, status applications and rune reactions.
5. Resolve eligible displacement and physical interactions.
6. Resolve recovery, resource and defensive effects.
7. Resolve elimination-triggered effects and progression entitlement.
8. Process newly generated combat events through subsequent applicable cycles.

A dead target cannot receive new ordinary statuses or displacement. Recorded death state can still satisfy an eligible elimination rule. Secondary effects cannot retroactively change completed damage, install a barrier against the hit that created it or resurrect an ordinary dead character through healing.

Same-hit new statuses do not satisfy pre-existing-status conditions by default. Multiple compatible reactions may occur from one hit. Where reactions consume the same finite resource/status, use authored priority and a stable tie-breaker, revalidate remaining eligibility and never double-spend. Priority is not a player-programmed reaction queue. Exact order between a parent hit and its separately generated lightning event, and the visibility of a newly applied status to that child, must follow the pre-existing-state rule without silently bypassing it; PR10 specifies the provisional ancestry comparison. Use PR12 for otherwise tied finite claims. [Provisional rules](#gds-rules)

No universal reaction cooldown or arbitrary universal chain-depth cutoff is introduced. Each effect declares valid continuation, consumption, cooldown, lifetime or other termination conditions. Intentional every-hit reactions and legitimate recursive elimination chains remain supported. Invalid zero-resource self-generation is not permitted. Visual batching and audio suppression must not silently remove genuine gameplay outcomes.

### 3.5 Damage calculation

For a nonnegative physical or magical damage component:

```text
Offense = authored_base_and_flat_terms * product(1 + sum(compatible_bonuses_in_category))
D_effective = max(0, D_base * (1 - R) * (1 - P))
Mitigation = D_effective / (D_effective + K)
PostMitigation = Offense * K / (D_effective + K)
IncomingResolved = PostMitigation * applicable_post_mitigation_vulnerability
Then: eligible personal barriers -> actual HP -> record overkill separately
```

This reduction/penetration expression describes the approved percentage case; additional flat modifiers require explicit definitions rather than an invented order. Modifier category assignments are authored. Additive stacking within a category and multiplication across independent categories do not mean every bonus is its own multiplier. Physical and magical defenses remain separate. **Initial K = 100 for both**, independently tunable.

Defense reduction affects the target first and benefits all compatible attackers. Penetration affects only the attack carrying it and applies to the remaining defense. Total Exposure is vulnerability, not penetration. Neither reduction nor penetration bypasses a shield collision, personal barrier or explicit immunity. Effective defense cannot go below zero. Ordinary finite defense cannot create complete immunity; there is no mandatory minimum damage floor or hidden boss damage cap. Mixed attacks resolve their separately authored components.

### 3.6 Resource commitment and payment scopes

Validate alive/eligible character state, cooldown readiness, mandatory resources and charges, target/placement and authored restrictions **collectively before commitment**. Failed validation consumes neither partial resources nor cooldown. On valid commitment, costs and cooldown apply even if the attack misses, is intercepted or yields no benefit. Interrupting a committed action does not automatically refund it.

Supported explicit payment scopes are per activation, per channel/pulse interval, per target only when stated, and follow-up activation. A sword hitting ten enemies pays one per-activation price, not ten. Mana depletion after commitment does not cancel an already paid attack; a later child checks its own affordability, and child failure does not undo its parent. Base weapons have no mandatory mana/ammunition expenditure; compatible modifications may add real costs and do not become free when unaffordable.

HP payments bypass barriers and ordinary damage mitigation, can be lethal when permitted and do not count as hostile damage. Actual HP paid determines sacrifice-based benefits. The early explicit lethal-payment exception remains: if paying the activation's HP price kills the caster, the affected cast ends; generic commitment does not allow that self-killed cast to complete. Previously committed unrelated effects follow post-death rules. Automatic potentially fatal HP-cost activations are suppressed during the special revival-protection window, not cast for free. Harmonic Burst remains usable at zero Resonance under V39.20. PR09 supplies its provisional zero-charge delivery. [Provisional rules](#gds-rules)

Momentum Charge is spent by the next eligible weapon activation, not every beam tick. Chorus Charge is consumed by its eligible distinct-source activation. Bloom Reserve specifically requires a successful eligible automatic attack, not merely a miss-prone activation; its earlier hit condition is not removed by the generic resource table. Crimson Fortification consumes real reserves only on valid fortification. Exact aggregation of multiple independent optional costs remains a deep-detail item.

### 3.7 Timing categories

Attack frequency, cooldown recovery, delivery speed, orbital rotation, tick frequency, effect lifetime and movement speed are separate. A modifier changes only explicitly compatible categories.

```text
AttackInterval_effective = AttackInterval_base / (1 + F)
Cooldown_effective = Cooldown_adjusted / (1 + R)
```

`F` and `R` are compatible frequency/recovery bonuses, additive within their categories with explicitly authored multipliers possible. Cooldown-duration penalties modify the adjusted cooldown rather than silently acting as attack speed. Changing rates preserves accrued timer progress; buffs, Evolution, Fusion, death and revival do not automatically reset timers. No zero-interval infinite attacks are created.

Battle Tempo explicitly bridges to eligible Spinning Blade rotational cadence, as approved in its definition. This does not make all generic attack-frequency bonuses universally alter orbit velocity or per-target contact intervals. Source-specific mappings must preserve this distinction. Additional attacks such as Overdrive Chorus are explicitly generated events, not arbitrary timer resets.

### 3.8 Persistent effect lifecycle

Initial application establishes duration and cadence. Eligible reapplication refreshes duration/stacks/intensity without restarting damage ticks or adding an immediate tick. Bleed stack changes and Burn intensity changes affect subsequent scheduled damage. A scheduled tick exactly at natural expiration resolves before expiration reactions. There is no automatic partial tick at expiration.

Leaving and reentering a persistent field does not reset its per-target interval. Lingering Essence may permit additional legitimate scheduled ticks by extending lifetime. Temporal Compression accelerates compatible scheduled remaining damage rather than duplicating total scheduled damage. Exact compression of an indefinitely refreshed lifecycle and Burn-intensity clock interaction remain open; it cannot be silently implemented as unconstrained DPS multiplication.

Natural expiration differs from destruction, replacement, forced removal, owner death and realm cleanup. Only eligible natural expiration creates Final Resonance or Residual Echo. Afterimages have their own bounded schedule and cannot regenerate their own afterimages/Final Resonance. Defeated targets cannot take subsequent status damage.

## 4. Health, barriers, recovery and death
<a id="gds-survival"></a>

**Basis:** M15 sections 20-21; V27; V30; V38.12; V39.5-V39.8, V39.11-V39.12, V39.19-V39.21; V40.19.1-V40.19.3.

### 4.1 Shared baseline

All nine heroes start at **100/100 HP, 10 physical defense, 10 magical defense, no passive HP regeneration and no starting barrier**, before explicit upgrades/abilities. With `K=100`, 10 effective defense produces `10/110 = 9.0909%` mitigation and 110 effective HP against that compatible damage type, excluding healing, barriers, penetration and vulnerability. These are initial balance targets.

Leveling grants reward selections, not automatic healing, HP, damage or attack-speed growth. There is no implicit passive recovery simply from waiting or leaving combat. Explicit hero abilities, pickups, services, powers, blessings and upgrades can supply it.

### 4.2 Maximum-stat adjustments

Maximum HP changes preserve absolute current HP, clamping only when current HP exceeds the new maximum. Increasing maximum HP does not itself heal. Decreasing it does not count as hostile damage or an HP sacrifice. A maximum-HP modifier cannot resurrect a dead character, and maximum HP must remain positive for a living character.

The same separation applies to capacity: a larger barrier cap does not generate barrier; a smaller cap removes excess without a depletion reaction. A larger resource capacity does not automatically replenish it. Stat clamping is not damage, healing or spending. Percentage-based passives immediately reevaluate the current HP/max-HP relationship. Existing offensive snapshots remain unchanged; defense changes affect future incoming damage. Repeated buff activation/expiration must not manufacture recovery.

Example (derived from the approved rule): Glass Covenant lowers maximum HP from 100 to 70 while current HP is 80. Current HP becomes 70, with zero hostile damage and no sacrifice empowerment, Reprisal Pulse or damage-triggered Recovery Surge from that clamp.

### 4.3 Barrier absorption priority

Each personal barrier retains its source, capacity, duration, ownership and lifecycle. Incoming damage consumes compatible temporary barriers in ascending remaining lifetime; persistent barriers are last by default. Equal remaining lifetimes resolve oldest first. Excess passes to the next barrier and finally HP. Directional shields and constructs intercept physical delivery before this stage and are not personal absorption layers.

| Source | Same-source rule |
|---|---|
| Life Harvest | Accumulate persistent capacity up to its cap. |
| Siphon Pulse | Strongest replacement; temporary lifetime and authored decay. |
| Mirror Guard | Strongest replacement; temporary lifetime. |
| Crimson Fortification | Independently tracked fortified barrier lifecycle. |
| Guardian Shrine | Strongest replacement; temporary lifetime. |
| Barrier Fragment | Bounded accumulation with temporary duration. |
| Future source | Must define accumulation, refresh, replacement and lifecycle explicitly. |

Strongest replacement compares whole instances, not best capacity plus best duration. With 80 remaining capacity for 5 seconds, a new 60-capacity/8-second barrier does not replace it. With equal capacity and a longer new lifetime, the new instance wins. A new 60-capacity barrier replaces a 40-capacity one. Capacity and lifetime are not combined unless a specific mechanic authorizes it.

Different sources may coexist. There is no default universal total barrier cap beyond explicit source/combined restrictions. Barrier decay, expiration, replacement and maximum-capacity clamping are not hostile damage/depletion. Refresh cannot restore consumed capacity unless authorized. Replacing a fortified barrier discards its stored retaliation charge without Aegis Release. No newly generated barrier absorbs the hit that generated it retroactively.

### 4.4 Recovery and conversion

Each healing source retains its conversion rate, compatible amplification and source limit. Compatible bonuses use categorized hybrid stacking. Damage-based recovery uses **actual eligible hostile HP damage**, excluding barrier damage and overkill, including compatible owned DoTs, summons, traps, reactions and causally owned environmental impacts.

Resolve eligible recovery and its source limits, apply compatible healing amplification once, restore missing HP up to maximum, then handle eligible excess under its explicit conversion rule. The exact order among multiple source-specific limits and receiver modifiers is open where it affects results. Crimson Reservoir uses eligible excess **after applicable recovery limits**, not theoretical pre-limit healing. It is not a barrier. Sanguine Fury generates offensive charge from **actual HP restored by default**, not overhealing. Vital Exchange and the player Soul Harvest blessing coexist as independent eligible sources.

There is no default universal healing cap, but each recovery/conversion mechanic remains bounded. Barrier generation is not HP healing. Resource conversion does not automatically create another heal event. Aegis Release can heal missing HP through eligible Vital Exchange, but its overheal cannot refill Crimson Reservoir and it cannot directly generate Mirror Guard. Ordinary healing cannot reverse a finalized death or prevent a lethal hit retroactively.

### 4.5 Immediate death and terminal causal completion

A character reaching zero HP dies immediately unless an explicit prevention mechanic resolves beforehand. Ordinary healing after that point is ineffective. Complete the current simultaneous combat group and its eligible immediate causal reactions before declaring the terminal outcome.

| Situation | Outcome |
|---|---|
| Last survivor and Forgotten Creator die in the same completed combat group | Victory for eligible party members. |
| Last eligible survivor dies and final boss survives the completed group | Defeat. |
| Lethal hostile hit qualifies for immediate Reprisal Pulse | Eligible immediate retaliation may resolve. |
| A distant projectile would hit later after everyone is dead | Do not wait for it; no post-wipe waiting mode. |
| A later Echo/DoT tick would kill the boss | Do not extend terminal resolution to future scheduled events. |
| Boss dies while some teammates were already dead | Party victory; dead members retain eligible victory payout. |
| HP sacrifice is lethal | Ordinary death without hostile-hit retaliation; affected cast ends. |

No duplicate terminal outcomes or elimination rewards. Cleanup ends remaining effects without manufacturing kills, depletion or natural-expiration events. "Simultaneous combat group" is a gameplay causality requirement; exact technical scheduling precision is delegated, not permission for arbitrary outcome races.

### 4.6 Committed effects after owner death

While another eligible survivor keeps the run active, previously committed effects continue valid remaining lifecycles and compatible secondary reactions with their original ownership. No new ordinary automatic or manual attacks start for the dead player.

| Effect | Behavior after owner death |
|---|---|
| Already launched projectiles | Continue delivery. |
| Already placed Arcane Sigils | Resolve their scheduled activation. |
| Continuous Spinning Blade | Suspend orbital damage; no new ordinary attack cycling. |
| Sketch Familiar | Dormant; no new autonomous attacks. |
| Armed Runic Mines | Remain until triggered or expired. |
| Bleed / Burn | Continue remaining schedules and ownership. |
| Chill / Fracture | Remain until expiry/removal. |
| Scheduled Echo Strike | Remains eligible under its committed rules. |
| Existing Arcane Tether | Valid links continue remaining lifecycle. |
| Gravegarden / Residual Echo | Existing fields and authorized natural-expiration reactions continue. |
| Manifest Guardian | Cannot initiate new attacks; lifetime continues. |
| Living Construct | Remains physically present/destructible; exact owner-dependent behavior is specified separately. |
| Seismic Arsenal | Existing mines/shards keep compatible interactions. |

A post-death owned Bleed kill can produce eligible Death Bloom under the later committed-effect rule; the older blanket prohibition on all generated on-kill effects after death is superseded. Resulting healing cannot revive the owner. Powers selected while spectating update ownership/Codex immediately but cannot create newly acquired active combat behavior until revival. Death and revival do not reset cooldowns, replenish charges, duplicate companions or restore expired effects.

## 5. Cooperative play, rescue and participation
<a id="gds-coop"></a>

**Basis:** M15 sections 19-21 and 25; V26; V34.8; V35.8; V36.5, V36.13; V39.11-V39.18; V40.10, V40.18.16; V42.1-V42.4.

### 5.1 Shared versus personal state

The session is a self-contained solo or friend-co-op run, not an MMO. Teammates may split across regions and special realms. They share world time, catastrophic tier, eligible XP/levels, explored geography and applicable world outcomes. They have individual heroes, weapons, rune choices, candidate pools, acquired powers, rewards, charges, permanent unlocks, Codex verification and Trade Shard wallets.

Global Party Scaling uses the party size locked at run initialization. Separation, death and temporary disconnection do not weaken enemies. PR07 distinguishes the one-to-four-player verification envelope and prototype admission from the open permanent party limit. PR06 governs guest survivor grace. Original-host return has its own deadline. [Provisional rules](#gds-rules) · [Owner decisions](#gds-owner)

No ordinary hostile player-to-player collision damage or forced displacement is introduced. Friendly-fire restrictions remain applicable to owned hazards; a full per-effect friendly-fire policy is an open implementation-facing gameplay matrix. Protected NPC rules remain independent.

### 5.2 Inclusive local encounter rewards

The latest V42.2 decision applies to regional boss blessings, events, quest encounters and other encounter-specific rewards: **nearby party members who participate qualify, with no minimum damage or last-hit requirement**. Arriving in the active encounter late before completion counts even without dealing damage. Evasion, healing, support or tiny contributions are sufficient. A remote teammate who never participates does not automatically receive the encounter-specific reward.

Shared XP remains shared. Shared discovered geography remains shared knowledge, not universal physical loot entitlement. Final boss victory is the explicit party-wide exception, including dead eligible party members. Individual mastery, personal Evolution acquisition, bargain acceptance and permanent ownership remain subject to their own requirements; proximity does not acquire another player's Evolution or prove a personal weapon challenge.

PR05 sets the provisional local footprint, departure/return and dead/disconnected eligibility at settlement. Persistent non-encounter world quests still need objective-specific rules. [Provisional rules](#gds-rules)

### 5.3 Kill, assist and participation are different

The owner of lethal damage receives the kill and eligible on-kill reactions. Other valid contributors may receive source-specific assist credit, at most once per enemy death. There is no universal offensive damage threshold. Any actual valid current/recent offensive contribution may qualify, including one point of real damage or an effective eligible control/defense-weakening status; a miss, entirely ineffective contact or expired contribution does not. Support assists require an explicitly eligible support mechanic. Contribution windows are source-specific. Encounter reward participation under V42.2 is broader and must not be used to duplicate personal on-kill or on-assist combat effects.

Dominant causal ownership selects one primary source for a physical impact, considering remaining directional contribution, attenuation and resistance. The latest tap does not steal a stronger earlier contribution. Neutral or enemy contributions may dominate. Equal contributions use stable ordering. Secondary participation credit never duplicates the damaging event or recovery. Influence expires when its physical contribution ends.

### 5.4 Death and revival

Individual death does not remove powers, ranks, transformations, earned currencies, pending rewards or committed discoveries, and adds no arbitrary weakness penalty. It costs lost active participation, rescue risk and a cumulative revive wait. Buff/effect timers continue during death.

```text
revival_wait(n) = min(initial_wait + (n - 1) * per_death_increment, hard_cap)
```

`n` is the player's cumulative deaths this run. The wait is linear, capped, never decays through survival and does not reset at the final gateway. It resets at the next run. Values are delegated tuning. Channel time is separate from the mandatory wait.

After eligibility, a living eligible teammate physically approaches and channels the body. Moving away or taking interrupting enemy damage stops channeling, but earned channel progress is preserved. Multiple rescuers advance one shared meter with diminishing additional speed. Completion revives at partial HP with brief protection. Exact time, radius, interruption handling and HP/protection values remain provisional/open as appropriate.

Revival protection blocks external enemy/environmental damage. It does not make HP-cost attacks free. An automatic HP-cost attack that would leave zero or less HP is suppressed during this protection; affordable activations still pay. When protection ends, normal potentially lethal costs return. No special blanket immunity for voluntarily activated self-harm was approved.

A body stays where it fell: no carrying, dragging, pushing or convenience teleport. The final party gateway is the explicit transport exception, and dead players arrive still dead. Geography must preserve a physically traversable rescue path, even if dangerous or long. This is route existence, not guaranteed survival.

### 5.5 Spectating and disconnected characters

Dead players can view their corpse or a living teammate across regions, communicate and use permitted party pings, inspect revive wait/progress and choose their own earned frozen rewards. They cannot independently scout hidden geography, attack, interact or gain omniscient offscreen information.

A disconnected character remains at the last valid world position, stationary and fully vulnerable. No invulnerability, safe relocation, automatic disappearance or AI survival pilot is implied. Committed attacks follow ordinary persistence. A guest killed while disconnected leaves a normal corpse with its usual timer and rescue eligibility. Alive reconnection resumes control at the actual location; dead reconnection returns to the dead-player experience.

A disconnected living character counts toward party survival only during a limited reconnection grace period. After that period they can remain physically alive but no longer prevent a wipe. If a connected living player remains, the run continues. If no connected survivor remains, an unexpired living-disconnect grace can temporarily sustain the session; once no eligible survivor remains, apply terminal rules. This is not a post-death revival grace or a pause.

PR06 provisionally fixes the guest survivor window, new automatic/manual commitments and its deadline tie. Expiry alone neither kills the guest nor precludes reconnecting to a still-active run. PR07 governs reclaiming the initialized seat. Loss of the original host suspends play under OWNER-T01 while host continuity and state are checked. [Provisional rules](#gds-rules) · [Owner decisions](#gds-owner)

If future co-op-only powers are authored, they retain their slots and become dormant without a qualifying connected teammate, with no automatic solo substitute; none is silently added to the 18-power catalog. Explicit co-op-only powers are excluded from deliberately solo preparation/reward pools. Most assist-oriented designs should retain useful solo-compatible behavior when individually authored; that guideline does not grant an unapproved fallback to a deliberately co-op-exclusive power.

## 6. Hero catalog
<a id="gds-heroes"></a>

**Basis:** V27.1-V27.7; V37.1-V37.9; V39.20; V40.19.1, V40.19.8. All heroes use the shared baseline and every weapon. Numerical passive targets below were proposed for initial balance; exact manual-ability values were not present in the visible approved table and are not invented here.

### H01. The Undying - starter
<a id="catalog-h01"></a>

**Identity:** Kill-earned persistent protection plus a separate, stronger temporary defense. **Passive: Life Harvest.** Personally credited qualifying kills restore limited persistent barrier; **initial target: 2 barrier per kill, 30 capacity**. Kill eligibility follows actual ownership, not proximity reward eligibility. Eligible companion/DoT kills can contribute where their source qualifies.

**Manual: Siphon Pulse.** Converts eligible damage into temporary barrier protection, separate from Life Harvest. It is not automatically actual HP restoration. The temporary barrier uses the approved temporary decay/strongest-replacement rules. Exact damage conversion, pulse delivery, active window, cooldown and decay coefficients remain delegated tuning or open where they define delivery.

Life Harvest and Siphon Pulse may coexist and are absorbed under shortest-remaining-lifetime priority. Reprisal Pulse can react to genuine hostile damage absorbed by either. Other independent barriers, Vital Exchange and Sanguine Aegis remain compatible. The hero is not assigned a Sword and gains no unique baseline HP/defense stat advantage.

### H02. The Acrobat - starter
<a id="catalog-h02"></a>

**Identity:** Positioning, genuinely narrow evasions and directional movement. **Passive: Close Call.** Rewards narrowly avoiding a genuinely threatening eligible attack, not an irrelevant distant miss. **Initial target: +20% movement and +20% compatible attack frequency for 3 seconds**, with bounded refresh/stack rules to be tuned.

**Manual: Vault.** A directional movement ability. Eligible ground-level attacks are avoided while airborne; airborne-reaching attacks and explicitly designated hazards can still hit. It is not universal invulnerability, teleportation through sealed boundaries or a mandatory global dodge shared by all heroes. Actual voluntary traveled distance may generate Momentum Charge. Landing/travel distance, duration, targeting and cooldown numbers are not finalized.

Primal Instinct and Close Call may both activate when their separate evasion conditions are satisfied. Knock-up, stun and airborne eligibility remain distinct. Using a Sword does not interrupt Vault-compatible movement; every ordinary weapon retains independent attack orientation.

### H03. The Conductor - starter
<a id="catalog-h03"></a>

**Identity:** Qualifying ability interactions generate resources for linked attacks. **Passive: Resonance.** Eligible interactions accumulate charges; **initial target: maximum 5**. Not every contact or repeated effect automatically qualifies.

**Manual: Harmonic Burst.** Converts available charges into additional linked attacks through authored eligibility. V39.20 preserves usability at zero charges; a zero-charge cast is not rejected solely for lacking optional charges. A valid cast that hits nothing still commits applicable cost/cooldown. PR09 supplies the provisional zero-charge effect. Remaining charge-generation, linked-delivery and consumption details retain their open or delegated status. [Provisional rules](#gds-rules)

Resonance is hero-owned, separate from Architect Structural Resonance, Arcane Tether Resonant Current, and any similarly named effect. Legitimate rune, summon and Fusion interactions may participate when explicitly compatible, without creating artificial attack-source identities.

### H04. The Chronomancer - unlockable
<a id="catalog-h04"></a>

**Identity:** Manipulates timing of owned effects, not the global clock. **Passive: Temporal Echo.** A qualifying successful attack schedules a delayed repetition of a portion of damage at its original impact location. **Initial target: 25% of qualifying original damage.** It is not Echo Strike's full attack-delivery copy and can miss if the enemy moves. The exact base-versus-resolved-damage input and spatial footprint remain open; do not unintentionally apply target mitigation twice by guessing.

**Manual: Time Fracture / Temporal Compression.** A selected localized field accelerates compatible owned delayed activations and remaining DoT deliveries. Original total scheduled damage is not duplicated, lifetime is not freely extended, and global time/enemy telegraphs are unchanged. Teammates' effects are not automatically accelerated. Compatible cases include pending Temporal Echo/Echo Strike waves, Arcane Sigils, eligible mine arming and Bleed/Burn schedules. Temporal Echo cannot recursively reproduce itself absent explicit authorization.

**Discovery:** Temporal knowledge in the Inverted Archive, followed by permanent-currency unlock unless a specifically designated direct exception applies.

### H05. The Gravity Weaver - unlockable
<a id="catalog-h05"></a>

**Passive: Gravitational Influence.** Amplifies compatible player-owned attraction/repulsion without granting force to attacks that lack it. **Initial target: +30% compatible displacement strength.** Respect original direction, real geometry, mass/resistance and explicit immunity.

**Manual: Singularity / Gravity Reversal.** Place a localized anomaly: attract compatible enemies and movable objects, then reverse into a magical burst and outward displacement wave. Actual movement can generate collisions and environmental reactions in both stages. Resistant targets can still take otherwise valid magical damage. Do not forcibly move teammates/protected NPCs or pull through solid/sealed boundaries.

Force, Collision Burst, mines, Death Bloom grouping, piercing alignment and movable objects are intended synergies. No particular rune/weapon is mandatory. **Discovery:** a genuine displacement-and-collision mastery accomplishment; thresholds remain tunable.

### H06. The Summoner - unlockable
<a id="catalog-h06"></a>

**Passive: Shared Essence.** Qualifying main-weapon hits generate temporary bounded Essence that empowers compatible owned summons. **Initial target: 5 stacks; each grants +5% summon damage and compatible attack frequency.** Summon attacks cannot directly generate the same stacks. The passive has a built-in beneficiary through the hero active and does not require acquiring Sketch Familiar.

**Manual: Manifest Guardian / Living Guardian.** Summon one temporary durable independent companion with its own position, movement, HP, target selection and attacks. It attacks nearby enemies and attempts to stand between owner and threats. Its real shield geometry intercepts compatible attacks; melee strikes have limited displacement. It can be damaged/destroyed and expires. Maximum one active Guardian per Summoner; acquired companions remain separate.

Summon damage belongs to the player, and only explicitly compatible runes/powers inherit. The Guardian cannot revive players, collect pickups or pass sealed boundaries. Destruction/expiration is not a hostile-creature reward event. After owner death it cannot start new attacks. **Discovery:** companion mastery with Sketch Familiar or its Evolutions.

### H07. The Bloodbound - unlockable
<a id="catalog-h07"></a>

**Passive: Blood Pact.** Outgoing damage rises as actual HP percentage falls, not HP-plus-barrier. **Initial maximum bonus: +40%.** A barrier can protect low HP without suppressing that passive. Zero HP is still death.

**Manual: Crimson Offering / Crimson Empowerment.** Pay an explicit portion/amount of actual HP to gain temporary damage and compatible attack-frequency amplification. Empowerment strength uses actual HP paid at activation, subject to bounds. Later healing lowers Blood Pact's dynamic low-HP bonus but does not remove the committed empowerment. Barriers/mitigation cannot pay the sacrifice; it is not a hostile hit and does not activate Reprisal Pulse. Repeated use cannot create unlimited stacking. No automatic healing or lethal prevention.

**Discovery:** accept and fulfill a qualifying HP-sacrifice covenant offered by the Nameless Stranger. Exact HP-cost formula, duration and cooldown are provisional, not the illustrative 80%-to-55% example.

### H08. The Alchemist - unlockable
<a id="catalog-h08"></a>

**Passive: Catalytic Reaction.** Applying an eligible owned compatible status to a target already carrying another compatible status generates an authored catalytic reaction. **Initial base reaction damage: 15 magical.** Not every pair of debuffs is automatically a recipe. Rune-pair reactions remain separate.

**Manual: Transmutation / Catalytic Propagation.** Create an alchemical field, apply temporary Catalyst Mark and spread compatible owned negative statuses between enemies with bounded original potency and remaining duration. Do not consume the original status. Against an isolated target, periodically generate bounded reactions from eligible existing combinations. Catalyst Mark supplies an intrinsic interaction component; its exact compatibility table remains to be authored.

Propagation respects resistance, ownership, same-hit ordering and stack limits; it cannot manufacture unlimited duration/intensity through repeated transfers. **Discovery:** multiple status interactions plus a relevant combat mastery accomplishment.

### H09. The Architect - unlockable
<a id="catalog-h09"></a>

**Passive: Structural Resonance.** Each owned construct accumulates a bounded response to genuine hostile strikes/interception, owned enemy displacement into it, or compatible movable-object impacts. At threshold, consume its Resonance to emit a magical area pulse. **Initial pulse damage: 30 magical**; threshold is tunable. The pulse does not inherently displace, and charging does not prevent structural damage.

**Manual: Living Construct / Living Formation.** Place three separated temporary destructible physical structures around a valid selected location. Each has independent durability, collision and Resonance. Gaps allow navigation. One formation active per Architect. Valid placement excludes occupied creatures and existing solid terrain. Structures can intercept compatible projectiles and serve as genuine collision surfaces, including in the final arena; they cannot seal essential routes or permanently trap entities. Stationary contact does not generate repeated impact charge. Destruction is not a creature kill.

Force, Collision Burst/Compression Burst, Momentum Relay, mines and physical objects can exploit the geometry. **Discovery:** restore the specialized construction mechanism in the Ancient Foundry. Specific construction shapes, durability, expiration and recast replacement details remain tunable/open.

### 6.1 Hero access and characterization

All six discoveries persist on defeat and precede permanent-currency purchase, unless an explicitly designated accomplishment directly unlocks ownership. No circular dependencies, challenge-only gameplay gate or inherent unlock-tier statistical advantage. Newly unlocked heroes are selectable on subsequent runs.

All nine have individual identities, origins and discoverable histories as approved in V41.7. The actual nine-origin table was not visible in the available exchange, so detailed biographies are **OPEN - SOURCE GAP**, not newly invented stories. Mechanical identity above is fully supported; narrative writing is deferred until prototype stability.

## 7. Main weapon catalog
<a id="gds-weapons"></a>

**Basis:** V28.1-V28.10; V37.10-V37.17; V40.19.5-V40.19.7. Every hero can equip every weapon. All automatically attack and preserve normal player movement. Base attacks require no mandatory mana and use unlimited ammunition where relevant. Compatible effects may add costs, statuses, guidance, geometry or follow-ups without deleting the original delivery restrictions.

### 7.1 Approved initial numerical reference

These are BALANCE TARGETS, before defense, hero effects, runes, permanent upgrades and acquired powers. Range units use the 100-unit/second player movement reference; they are not mandated rendering pixels.

| Weapon | Damage | Activation interval | Conditional single-target DPS | Reach/range | Base coverage |
|---|---:|---:|---:|---:|---|
| Sword | 20 physical | 1.00 s | 20 | 75 | 110-degree frontal sweep |
| Bow | 24 physical | 1.00 s | 24 | 450 | One arrow |
| Magic Staff | 24 neutral magical | 1.20 s | 20 | 360 placement | 65-unit sigil radius |
| Spear | 20 physical | 1.00 s | 20 | 125 | 22-unit thrust width |
| Warhammer | 28 impact + 8 wave physical | 1.80 s | 20 if both stages hit | 65 | 110-unit shockwave radius |
| Twin Daggers | 9 physical | 0.40 s | 22.5 | 50 | Narrow alternating strikes |
| Chakram | 12 physical/pass | 1.20 s | 20 if both passes hit | 260 outbound | Real outward/return paths |
| Chain Whip | 18 physical | 1.00 s | 18 | 150 | 100-degree curved sweep |
| Arcane Focus | 6 magical/tick; 4 ticks | 1.20 s | 20 if all ticks hit | 300 | 24-unit beam width |

DPS is a comparison, not guaranteed output. Multiple genuine targets receive the weapon's authored damage rather than a total-DPS budget divided among them. Arcane Focus's four scheduled ticks occur across a one-second beam window. Exact first-tick placement and high-frequency overlap handling remain source-specific tuning/details.

### W01. Sword - starter
<a id="catalog-w01"></a>

**Pure Physical Cleave:** Select a nearby eligible target and perform a directional sweep with actual melee geometry. Every compatible enemy intersecting the sweep can be hit. The player remains free to move at full ordinary speed and change movement direction; targeting may orient the attack independently. No automatic lunge, chase movement or attack lock.

No innate Bleed, knockback, stun or elemental status. Those require compatible modifications. Preserve approved Sword/Spinning Blade property inheritance and the shared counter rules when their qualifying mechanic is active; do not treat one sweep hitting many enemies as many attack activations. Exact attack animation, reach and timing remain tunable.

### W02. Bow - starter
<a id="catalog-w02"></a>

**Precise Single-Target Arrows:** Fire one physical arrow toward the selected enemy's current position at launch. No default predictive leading or homing. The arrow follows a fixed straight trajectory, can miss and can be intercepted by another eligible enemy. It stops on the first valid enemy unless piercing or another compatible modification changes that behavior.

Unlimited arrows, no reload and no ammunition collection. Attack timing governs frequency. Accuracy improvements are earned through powers/traits: Sharpsight predicts initial aim; Guided Flight can explicitly add steering. Neither is free baseline behavior. Rune effects require a genuine eligible hit, not firing toward a target.

### W03. Magic Staff - starter
<a id="catalog-w03"></a>

**Arcane Sigil:** Automatically place a sigil at a selected enemy's current position. A short visible delay precedes magical area damage. The sigil does not follow the enemy; enemies must be within its actual area at activation. Multiple eligible enemies can be hit. Placement alone is not a hit/status application.

Neutral magical damage, no innate element/status, and zero base mana cost. Compatible powers/runes can change element, delayed targeting or costs. An unaffordable modified activation does not silently become a free enhanced spell. Sharpsight's later approved compatibility can predict a delayed impact where explicitly supported, without making the unmodified Staff predictive.

### W04. Spear - unlockable
<a id="catalog-w04"></a>

**Piercing Thrust / Consistent Piercing:** A narrow extended melee thrust hits every compatible enemy along its real geometry once per ordinary thrust. Equal base damage is delivered to each, before defenses/modifiers. Direction commits at activation. Solid obstacles and compatible directional shields intercept; the thrust is not a projectile because of its reach.

No innate force, status or penetration amplification. No artificial target-number limit within valid geometry. Movement stays unrestricted. **Discovery - Piercing Mastery:** hit multiple aligned enemies with one eligible piercing attack using previously available content such as Spectral Lance; then permanent-currency unlock.

### W05. Warhammer - unlockable
<a id="catalog-w05"></a>

**Crushing Impact / Crushing Shockwave:** Slow, strong central physical impact followed by a lower-damage traveling radial wave. Each stage has distinct geometry and damage events and can hit an eligible creature once. An enemy can receive both if it genuinely intersects both. The wave innately pushes compatible enemies and movable objects outward, enabling collision builds without Force Rune.

Force can add compatible displacement; it does not erase stage identity. Ground delivery does not automatically hit airborne, intangible or fully burrowed targets. Resistance to displacement does not prevent otherwise valid damage. No permanent destruction of protected terrain. Movement stays unrestricted through the relatively long preparation and execution. **Discovery - Crushing Force:** qualifying physical impact kills using displaced environmental objects.

### W06. Twin Daggers - unlockable
<a id="catalog-w06"></a>

**Relentless Strikes / Continuous Alternating Strikes:** Each activation is one rapid physical strike, alternating left and right regardless of hits/misses. Each independently selects an eligible target and commits direction. A strike hits the first compatible enemy intersecting its narrow geometry.

No simultaneous double-strike default, mandatory combo finisher, movement lock, innate Bleed, poison, knockback or random critical bonus. High-frequency legitimate hit synergies remain intended. Each attack is distinct for activation costs, but source identity remains the same weapon for Converging Strikes. **Discovery - Relentless Rhythm:** a required number of qualifying successful attacks within a defined window; exact threshold delegated.

### W07. Chakram - unlockable
<a id="catalog-w07"></a>

**Returning Edge / Dynamic Returning Edge:** The outbound rotating projectile uses a committed trajectory. At maximum travel or a compatible outbound obstruction it begins return behavior. Return steering follows the moving owner's current position, within travel-speed, turning and obstruction constraints. This is owner-return guidance, not enemy homing.

Naturally pierces compatible creatures. A creature may take one ordinary hit in each outbound and return stage; continuous overlap within a stage is not unlimited damage. Several Chakrams may coexist within an authored active limit. Return interception may make a blade expire without reaching the owner, but cannot permanently disable the weapon. No travel across dimensions or sealed boundaries, no innate status/force. **Discovery - The Returning Edge:** ancient returning-blade blueprint and associated Artisan research.

### W08. Chain Whip - unlockable
<a id="catalog-w08"></a>

**Sweeping Reach / Grasping Retraction:** The extension follows a curved physical strike path and damages each compatible intersected enemy once. Retraction pulls successfully struck and still physically eligible enemies a limited distance toward the player. Pulling by itself adds no second direct damage hit; genuine resulting collisions can produce authorized effects.

Retraction respects mass/resistance/obstacles and does not permanently attach enemies. Resisting the pull does not cancel sweep damage. Force Rune's outward contribution and the innate inward retraction remain distinct effects, not an automatically canceled rule. **Discovery - Converging Force:** an inward-displacement accomplishment using environmental Gravity Wells or already available abilities.

### W09. Arcane Focus - unlockable
<a id="catalog-w09"></a>

**Sustained Ray / Committed Direction:** Automatically activate a neutral magical beam in a direction fixed for that activation. The origin follows the player's movement; no default turning toward the target. Positioning changes the line's location, allowing a player-driven sweep without automatic tracking.

Naturally penetrates compatible creatures, while solid obstacles/compatible shields obstruct. Per-target contact intervals govern repeated damage, not frames. Exiting/reentering cannot reset that interval. Beam activation rate, lifetime and tick interval are separate; generic attack speed does not inherently speed its ticks. No innate elemental status, force or defense penetration. **Discovery - Focused Energy:** restore the Silent Observatory's focusing mechanism.

### 7.2 Weapon access, enhancement and transformation

All six discoveries precede permanent-currency ownership unless an explicit direct-unlock exception is authored. They must be achievable without their own unlock and without mandatory challenge modifiers. Discoveries survive defeat; newly unlocked weapons become selectable next run.

Artisan improvements and one temporary alternate form can modify a main weapon without consuming a power slot. Expiration restores the underlying current weapon/progression, not an obsolete version. Greatblade, Volley and Constellation examples were not finalized weapon forms. No additional named main-weapon Evolution tree is implied by the **36 acquired-power Evolutions**; the exact legacy main-weapon Evolution scope is an open reconciliation item.

## 8. Global rune and status catalog
<a id="gds-runes"></a>

**Basis:** V29; V31.10, V31.31; V37.18-V37.22; V39.7-V39.9. Global runes are pre-run equipment, outside power capacity, applied once to each explicitly compatible owned attack instance. They do not automatically convert a weapon's original damage type or propagate to every child/tick. Added costs require an authored effect; the early mana-cost Bleed example does not impose a baseline mana cost on the approved Bleed Rune.

### R01. Bleed - starter

Eligible successful hits apply capped stacks of physical damage over time. Repeated applications add stacks to the limit and refresh eligible duration, increasing subsequent scheduled damage. Misses and sigil placement alone do not apply stacks. Each owner has independently capped stacks and damage; separate players' valid Bleeds can all deal their owned damage.

Offense snapshots at application; live target defense/vulnerability affects ticks. Cadence continues through refresh. Default DoT ticks do not reapply Bleed or receive all direct-hit triggers. Exact per-stack potency, whether all stacks share one refreshed duration, snapshot replacement details and cap values are explicitly authored/tunable rather than inferred from "stacking."

### R02. Lightning - starter

Eligible successful hits create chain lightning through a limited number of nearby valid enemies. The originally struck enemy receives the original attack's normal damage; separate electrical arcs deliver additional lightning damage to eligible nearby targets. Default reach and jump count are finite. A miss generates no hit-triggered chain, and a lone target does not guarantee a nearby chain victim.

Ownership follows the triggering player. Compatible powers may change jumps, targeting, secondary eligibility or propagation. There is no blanket ban on further interactions, but the chain does not infinitely restart itself merely because it deals lightning damage. Target-repetition policy and jump coefficients remain explicitly authored.

### R03. Force - starter

Eligible hits add directional knockback according to actual attack geometry. Sword pushes by impact direction, Bow along projectile travel, Staff outward from its sigil center. Enemy-specific displacement resistance applies; bosses are not automatically immune. Preserve original attack damage. Compatible secondary attacks/physical objects may carry force when explicitly eligible. No movement means no displacement-dependent Blood Wake, Storm Relay or Collision Burst, even if the hit itself is valid.

### R04. Flame - unlockable

**Burn / Persistent Combustion:** One owned Burn lifecycle per enemy, with non-stacking magical DoT whose intensity grows with continuous active duration to a cap. Reapplication refreshes remaining duration and preserves intensity without instantly raising it, adding stacks or generating an extra tick. Expiration resets intensity. Each owner's instance retains its own potency/duration/damage.

Burn does not inherently spread, create fields or grant Flame damage to every primary hit. **Discovery - Heart of the Furnace:** restore an optional furnace/conduit mechanism in the Ancient Foundry and reveal its inscription, using starter-accessible means; then permanent-currency purchase or explicit direct exception.

### R05. Frost - unlockable

**Chill / Persistent Chill:** Apply its defined movement suppression immediately; reapplication refreshes duration without stacking strength. No innate damage, freeze, attack interruption, outgoing-damage reduction, projectile slowdown or knockback-distance reduction. Slow resistance and positive minimum voluntary speed apply. Committed dashes follow explicit compatibility.

Owners keep separate Chill instances, but base slowing does not add across them: strongest applicable effective Chill governs movement, followed by the next strongest on expiry. **Discovery - Trial of Stillness:** an optional Inverted Archive control trial preventing designated enemies reaching marked places, solvable with starter-accessible displacement/environmental mechanisms and abilities. Frost itself, an unlockable hero or weapon is not required.

### 8.1 Multi-owner status rules

| Status/effect | Per owner | Combined target result |
|---|---|---|
| Bleed | Capped owned stacks | Independent damage. |
| Burn | Own intensity and lifetime | Independent damage. |
| Chill | Own potency/lifetime | Strongest effective slow, not additive immobilization. |
| Fracture | Own capped stacks | Shared effective reduction limit, without deleting owned stacks. |
| Total Exposure | Owner must reach their Fracture maximum | Strongest applicable exposure bonus. |
| Grave Imprint | Temporary non-stacking owned marker | Owner-specific Rebirth. |
| Catalyst Mark | Owned marker | Authored owner-specific catalytic reactions. |

Reapplication does not rewrite another owner's instance. Consuming an owner's eligible status does not remove a teammate's by default. Personal recovery uses individually attributed damage. Fracture's resulting target defense reduction benefits other attackers without transferring ownership. Later V37.21/V39.7 rules supersede early blanket permission to use teammates' statuses for all reactions: cooperative status exploitation requires explicit authorization.

### 8.2 All ten rune-pair interactions

Both respective runes must be equipped to access a dedicated pair interaction. Each base rune remains functional. Compatible player-owned weapons, hero abilities, acquired powers, Evolutions, Fusions and environmental events can satisfy prerequisites; the trigger need not originate only from a rune implementation. Teammate states are not automatic substitutes. No automatic rune fusion replaces the original effects.

#### RP01. Bleed + Lightning - Thunder Rupture

A qualifying lightning hit against an already Bleeding target consumes its eligible existing Bleed stacks and creates immediate electrical burst damage scaling with consumed stacks. No stacks means no rupture. Consuming stacks sacrifices remaining DoT potential. Same-hit newly applied Bleed does not satisfy a pre-existing Bleed requirement. Original Bleed/Lightning functions continue. Reaction damage belongs to the trigger owner. Exact area, scaling and stack-selection policy remain authored; a condition checking Bleed at death fails if the relevant Bleed was fully consumed before death.

#### RP02. Bleed + Force - Blood Wake

Qualifying actual displacement of an already Bleeding enemy leaves a short-lived damaging trail along its real movement path. Existing Bleed remains intact. Enemies must intersect the trail to take damage; no displacement creates no trail. Originating Force application alone is insufficient against an immovable target. Trail width, duration, damage cadence and secondary eligibility are authored.

#### RP03. Lightning + Force - Storm Relay

A qualifying Lightning-plus-Force hit that physically moves an enemy creates additional lightning arcs from its new position. Preserve normal chain lightning and knockback. A valid target within arc reach is still required. No displacement produces no relay. Real collision or authored later triggers may continue; a relay is not guaranteed damage and does not grant arbitrary unlimited reach.

#### RP04. Bleed + Flame - Bloodfire

A qualifying kill of an enemy already carrying both eligible Bleed and Burn leaves temporary burning ground at the death location. It deals magical damage at contact intervals, does not inherently apply either source status, and cannot generate further Bloodfire fields by itself. Other explicitly eligible kill/field interactions remain possible. Real active status at death matters, not historical application alone.

#### RP05. Bleed + Frost - Frozen Wounds

Eligible Bleed ticks gain bounded physical damage amplification while the target is also Chilled. Amplification depends on effective Chill movement suppression, with a cap. No extra stacks, added ticks or consumption. The exact cross-owner strongest-slow calculation must honor owner-specific prerequisite permission rather than borrowing an unowned Chill automatically.

#### RP06. Lightning + Flame - Flashfire

Qualifying lightning damage against an already Burning enemy creates a localized magical explosion. Preserve Burn duration/intensity. Explosion generation is bounded per Lightning activation and does not inherently restart lightning chains. Explicit powers may authorize further secondary effects without removing these activation accounting rules.

#### RP07. Lightning + Frost - Conductive Rime

A qualifying lightning strike against an already Chilled enemy grants an additional eligible chaining opportunity. Real target availability, chain-length bounds and authored repeat-target restrictions still apply. It does not increase range to infinity or guarantee additional targets.

#### RP08. Force + Flame - Cinder Transfer

When a displaced Burning enemy genuinely collides with another compatible enemy, transfer a bounded portion of Burn intensity and remaining duration to the struck enemy. Preserve the original Burn. Another transfer requires a new qualifying displacement/collision; propagation alone is not self-replicating force or a fresh full-duration Burn.

#### RP09. Force + Frost - Glacial Impact

A displaced Chilled enemy takes additional concentrated physical damage on a genuine collision with a compatible creature or solid obstacle. Scale with actual impact strength within bounds. It is not Collision Burst's area shockwave and does not inherently add an explosion. Resistance matters through real movement/impact.

#### RP10. Flame + Frost - Thermal Shock

Applying or refreshing Burn to an already Chilled target, or Chill to an already Burning target, causes additional magical burst damage. Use an independent reaction cooldown per enemy and owner. Preserve both statuses. Simultaneous first-time applications do not count as pre-existing statuses. Reapplication/timing and actual accepted status rules still apply.

### 8.3 Depth, spectral state and status compatibility

Fully burrowed enemies cannot be hit by ordinary surface delivery. Explicitly underground-compatible attacks can affect them. Existing DoTs continue; new status application needs compatible delivery; underground displacement needs explicit authorization. Magical damage alone does not penetrate ground. Exposed recovery returns ordinary eligibility.

Fully intangible enemies can only be hit by explicitly spectral-compatible delivery, independently of physical/magical classification. Existing DoTs continue; new statuses/force require compatibility. Incompatible attacks do not hit or trigger hit effects, and intangible creatures do not intercept ordinary incompatible projectiles or obstruct ordinary creature movement. Spectral movement does not automatically cross sealed environmental boundaries. Materialization restores normal interaction. Every starter build can defeat these enemies through sufficient exposed windows.

## 9. Acquired powers, rank milestones and all 36 Evolutions
<a id="gds-powers"></a>

**Basis:** V30.1-V30.77; V37.23-V37.30. Eighteen powers occupy one slot each before and after standard Evolution. Each has five ordinary ranks, fixed authored progression rather than player-selected rank branches, and signature milestones at Rank 3 and Rank 5. Rank 2 and Rank 4 improve explicitly compatible existing properties; their precise coefficients were not individually approved and are delegated tuning. Ordinary ranks retain the power's identity; Evolution is a major transformation.

Every standard recipe below requires **the base power at Rank 5** plus the named catalyst. A catalyst written as another acquired power requires ownership unless an authored recipe explicitly adds a rank requirement. A rune catalyst must be equipped. Catalysts remain independently active, are not consumed, and keep their own slots where applicable. Evolved/Fused catalysts retain eligibility only when the required property remains available. Eligibility offers an option; it does not auto-transform. The player chooses one of the two mutually exclusive standard forms per base power per run.

### P01. Spinning Blade
<a id="catalog-p01"></a>

**Category:** Independent automatic attack. **Base:** One continuously orbiting blade follows the player and damages compatible enemies through real physical contact. It can contact multiple enemies along its path, but overlapping every frame is not repeated eligible damage. Use authored per-target contact timing. Movement remains free. Compatible main-weapon properties/runes and the established Sword shared activation counter are retained without duplicating the same inherited modifier. The exact cadence event used by that counter/costs for a continuous orbit is open.

| Rank | Development |
|---|---|
| 1 | Continuous single-blade orbit. |
| 2 | Ordinary compatible scaling. |
| 3 - Twin Blades | Add a second blade to the same ring; independent physical contact, normal hit timing, no extra power slot. |
| 4 | Further compatible scaling. |
| 5 - Razor Momentum | Qualifying blade hits temporarily build bounded orbital rotation speed; successful contact maintains it, inactivity causes decay. |

Razor Momentum is source-specific; Battle Tempo is shared offensive momentum. Both can operate where compatible without redefining every rotation/contact as an activation.

<a id="evolution-e01a"></a>
**E01A - Blade Tempest. Recipe: Spinning Blade 5 + Battle Tempo.** Multiple interlocking, counter-rotating orbital formations follow the player. Real blade paths and contact timing determine hits; intersections do not imply unlimited duplicate damage. Preserve compatible Twin Blades/Razor Momentum and Sword interactions. This concentrates offense around the hero, unlike a stationary field. Catalyst remains active.

<a id="evolution-e01b"></a>
**E01B - Phantom Circuit. Recipe: Spinning Blade 5 + Echo Strike.** Qualifying blade strikes create temporary spectral orbital afterimages at previous battlefield positions. Original blades keep orbiting the owner; afterimage blades rotate around stationary locations with actual contact geometry. Several can coexist within authored limits. Preserve compatible inheritance and ownership. Echo Strike remains a separate attack-copy mechanic, not automatically consumed or replaced. Afterimage lifetime, density, hit cadence and exact previous-position selection remain authored.

### P02. Sketch Familiar
<a id="catalog-p02"></a>

**Category:** Independent automatic attack. **Base:** One living graphite companion follows its owner and automatically fires physical Ink Darts from its own position. Direct aim, real travel/collision, no default homing or prediction. Darts can miss or be intercepted. The companion is not manually controlled. Damage/kills belong to the summoning player and can support eligible Life Harvest, Vital Exchange and runes. Base familiar destructibility is not implied by the separately defined destructible Living Guardian and remains an open attribute.

| Rank | Development |
|---|---|
| 1 | Single Ink Dart from an autonomous following companion. |
| 2 | Ordinary attack scaling. |
| 3 - Twin Quill | Two independent darts in a narrow spread per attack; both may hit one enemy when geometry allows. |
| 4 | Further compatible scaling. |
| 5 - Piercing Quill | Both darts gain limited enemy piercing; solid obstacles still intercept. |

Prediction/guidance apply only through explicitly compatible additions. Multi-dart hits and multiple familiars remain one Sketch Familiar source for distinct-source checks.

<a id="evolution-e02a"></a>
**E02A - Margin Hunter. Recipe: Sketch Familiar 5 + Sharpsight.** One tactical companion autonomously seeks advantageous off-axis/flanking positions and fires precision volleys using compatible predictive aiming. Physical, non-homing projectiles remain subject to cover and evasion. No automatic teleportation, wall penetration or guaranteed hits. Retain Twin Quill/Piercing Quill where compatible.

<a id="evolution-e02b"></a>
**E02B - Ink Squadron. Recipe: Sketch Familiar 5 + Battle Tempo.** Several independently positioned graphite companions follow the owner and fire autonomous Ink Darts. They may distribute targets or concentrate fire. Real trajectories and compatible multi-dart/piercing properties remain. Squadron count and firing limits are authored, not unlimited summon multiplication. Battle Tempo accelerates eligible firing; Shared Essence can empower compatible summons.

### P03. Runic Mine
<a id="catalog-p03"></a>

**Category:** Independent automatic attack. **Base:** Periodically place temporary magical traps near recent player positions. Mines arm under their authored timing, then immediately detonate when a valid enemy enters the trigger radius. The explosion damages compatible enemies inside its real area; no base fuse after triggering or lingering field. Untriggered mines expire and simultaneous mines are bounded. A trap does not require the owner to stop moving or press a placement button.

| Rank | Development |
|---|---|
| 1 | Automatic independent proximity mine. |
| 2 | Ordinary mine-property scaling. |
| 3 - Twin Runes | Place two independent mines at distinct valid nearby positions each cycle. |
| 4 | Further compatible scaling. |
| 5 - Pressure Charge | Each armed mine independently gains explosive strength over waiting time, capped; detonation still occurs immediately when triggered. |

Waiting for charge is not a new minimum activation delay. Each mine uses its own charge at detonation and is consumed once. Source ownership survives legitimate mine-generated reactions.

<a id="evolution-e03a"></a>
**E03A - Runic Web. Recipe: Runic Mine 5 + Death Bloom.** Nearby active mines form visible eligible connections. One triggered mine propagates ignition through connected armed mines, each exploding at its actual location and consuming itself. A network blast can hit nothing if enemies are absent. Death Bloom separately responds to valid kills. Each mine's Pressure Charge is preserved; no mine repeats its own explosion in the same lifecycle.

<a id="evolution-e03b"></a>
**E03B - Seismic Mine. Recipe: Runic Mine 5 + Force Rune.** Preserve the magical explosion and add an expanding kinetic shockwave that physically pushes eligible enemies outward. Real displacement can move enemies into other mines, objects or enemies and support Collision Burst, Blood Wake or Storm Relay only with their own conditions. Resistance remains meaningful. No automatic linked mine ignition is granted by this Evolution itself.

### P04. Spectral Lance
<a id="catalog-p04"></a>

**Category:** Independent automatic attack. **Base:** Periodically launch a straight, non-homing magical spear toward an eligible enemy's current position. It naturally pierces enemies along genuine travel geometry. Before Rank 5, all eligible penetrated enemies receive consistent base damage, independently mitigated. It can miss. The name does not confer spectral/underground compatibility.

| Rank | Development |
|---|---|
| 1 | Straight consistent-damage piercing spear. |
| 2 | Ordinary scaling. |
| 3 - Crescent Lance | Expand the spear's actual collision width throughout flight; still one spear. |
| 4 | Further compatible scaling. |
| 5 - Ascending Pierce | Each successful penetration amplifies damage to subsequent enemies up to a cap; tracked per spear, starting anew on launch. |

The Rank 5 behavior explicitly modifies the earlier consistent-damage baseline. It never retroactively amplifies targets already hit. Guiding effects can explicitly change an otherwise fixed trajectory, with geometry still real.

<a id="evolution-e04a"></a>
**E04A - Sunderline. Recipe: Spectral Lance 5 + Fracture.** Leave a temporary magical damaging fissure along where the spear actually traveled, not an infinite line toward a target. Enemies intersecting it take scheduled eligible damage. Compatible fissure hits can apply Fracture. Preserve piercing, Crescent Lance and compatible Ascending Pierce behavior; exact path-segment snapshot/amplification transfer to the fissure remains source-defined.

<a id="evolution-e04b"></a>
**E04B - Skewer Drive. Recipe: Spectral Lance 5 + Force Rune.** Carry eligible struck enemies forward along part of the actual spear trajectory before release. Resistant enemies can still take valid spear damage without being carried. Real collisions can trigger impact effects; already Bleeding carried enemies may create Blood Wake, and eligible Lightning-plus-Force movement may create Storm Relay when the rune requirements exist. Carry limits/distance and wall handling are authored; no movement through solid boundaries.

### P05. Battle Tempo
<a id="catalog-p05"></a>

**Category:** Passive / attack modifier. **Base:** Qualifying successful attacks build one short-lived capped Tempo pool per player. Tempo accelerates every compatible automatic attack source: main weapon, eligible Spinning Blade rotational cadence, familiar firing, mine placement and lance firing. It does not automatically accelerate manual cooldowns, already flying projectiles, DoT ticks or unrelated clocks. Faster costly activations increase real resource expenditure.

| Rank | Development |
|---|---|
| 1 | Shared capped attack-frequency momentum. |
| 2 | Ordinary compatible scaling. |
| 3 - Unbroken Rhythm | Lose stacks progressively rather than all at once on timeout; qualifying hits interrupt decay/refresh. |
| 4 | Further compatible scaling. |
| 5 - Peak Performance | At maximum Tempo, compatible automatic attacks gain additional damage; losing maximum disables the bonus for subsequent snapshots. |

<a id="evolution-e05a"></a>
**E05A - Overdrive Chorus. Recipe: Battle Tempo 5 + Echo Strike.** High Tempo enables temporary synchronized windows with additional coordinated attack beats across compatible automatic sources. Each source retains its delivery, targeting, contact and activation-cost rules. Extra beats are not guaranteed damage and may produce authorized Echo/other reactions. Shared Tempo and both rank milestones remain. Window timing/retrigger limits are authored.

<a id="evolution-e05b"></a>
**E05B - Impact Cadence. Recipe: Battle Tempo 5 + Force Rune.** Sustained rhythm thresholds let qualifying attacks release directional kinetic shockwaves that push compatible enemies. Original attacks and Tempo acceleration remain. Actual collisions/displacement may support other authorized reactions; force does not bypass resistance or guarantee impact. Exact thresholds, geometry and damage payload are authored, not an automatic effect on every visual tick.

### P06. Sharpsight
<a id="catalog-p06"></a>

**Category:** Passive / targeting modifier. **Base:** Compatible attack activation predicts a moving target's future position. Once fired, the projectile retains its normal fixed trajectory. It does not grant free homing, wall penetration or guaranteed contact. Bow, Ink Dart, Spectral Lance and explicitly compatible delayed attacks/copies benefit.

| Rank | Development |
|---|---|
| 1 | Predictive initial targeting. |
| 2 | Ordinary compatible prediction improvement. |
| 3 - Adaptive Prediction | Account for acceleration, deceleration and recent directional changes. |
| 4 | Further compatible scaling. |
| 5 - Convergent Aim | Calculate each compatible projectile's firing angle independently; converge or distribute using predicted valid targets instead of rigid spread alone. |

<a id="evolution-e06a"></a>
**E06A - Guided Flight. Recipe: Sharpsight 5 + Spectral Lance.** Compatible projectiles gain controlled in-flight steering, with explicit turning/tracking limits and ordinary obstacle collision. Preserve predictive launch aiming and Convergent Aim. Curving a lance does not remove its piercing rules. This is the authored exception to otherwise fixed default flight, not an unconditional guaranteed hit.

<a id="evolution-e06b"></a>
**E06B - Weakpoint Atlas. Recipe: Sharpsight 5 + Fracture.** Qualifying accurate hits against already Fractured enemies reveal temporary exploitable weakpoints. Compatible follow-up attacks must genuinely exploit them for additional effectiveness against applicable defenses. Preserve prediction but add no homing. Explicit immunities remain. Weakpoint geometry, lifetime and exact reduction are authored; it does not reveal an enemy HP bar or automatically make every follow-up a critical hit.

### P07. Vital Exchange
<a id="catalog-p07"></a>

**Category:** Passive / recovery. **Base:** Convert bounded eligible player-owned offensive HP damage to the owner's actual HP. Weapons, companions, traps, DoTs and rune reactions are all supported when eligible. Later V39.9/V39.19 clarify that barrier damage and overkill do not heal. No teammate-damage theft, excess maximum HP, self-resurrection or automatic refund of HP costs.

| Rank | Development |
|---|---|
| 1 | Bounded damage-based HP recovery. |
| 2 | Ordinary compatible scaling. |
| 3 - Survival Instinct | Conversion efficiency rises as actual HP percentage falls, to a maximum; barriers do not change the HP test. |
| 4 | Further compatible scaling. |
| 5 - Recovery Surge | Crossing a critical-HP condition grants a temporary damage-based recovery boost subject to a recovery cooldown. |

Survival Instinct weakens as HP recovers. Recovery Surge is not automatic healing or lethal prevention; eligible offense must still occur. Exact threshold/rearm behavior remains authored.

<a id="evolution-e07a"></a>
**E07A - Crimson Reservoir. Recipe: Vital Exchange 5 + Reprisal Pulse.** Store eligible excess offensive healing in a capped reserve for later HP restoration. The reserve is not a damage-absorbing barrier, does not directly pay HP costs and does not automatically save a lethal hit. Preserve baseline healing and rank milestones. PR08 supplies the provisional release conditions, rate and barrier replacement test. [Provisional rules](#gds-rules)

<a id="evolution-e07b"></a>
**E07B - Sanguine Fury. Recipe: Vital Exchange 5 + Battle Tempo.** Qualifying actual offensive healing generates bounded temporary offensive charge, strengthening compatible attacks while preserving HP restoration. Later V39.19 fixes actual HP restored as the default; unused theoretical overheal does not automatically charge it. Normal offensive snapshots apply. No unlimited charge accumulation.

### P08. Fracture
<a id="catalog-p08"></a>

**Category:** Passive / hostile defense debuff. **Base:** Qualifying hits build capped temporary Fracture stacks, refresh eligible duration and reduce applicable physical and magical mitigation. Fracture deals no inherent damage. Subsequent direct damage, DoTs and rune reactions benefit from current reduced defenses. Explicit immunity and special eligibility remain intact; no boss HP gate is added.

| Rank | Development |
|---|---|
| 1 | Temporary stacking defense reduction. |
| 2 | Ordinary compatible scaling. |
| 3 - Deepening Cracks | Each additional stack contributes progressively stronger defense reduction, with bounded effective reduction. |
| 4 | Further compatible scaling. |
| 5 - Total Exposure | At an owner's maximum stacks, target gains additional eligible incoming-damage vulnerability benefiting player and teammates; no consumption. |

Owners track stacks independently; combined defense reduction has a shared limit, and strongest applicable Total Exposure governs. Exposure ends below the required maximum. Reduction and post-mitigation vulnerability remain separate operations.

<a id="evolution-e08a"></a>
**E08A - Shatter Cascade. Recipe: Fracture 5 + Death Bloom.** A player-credited kill of a Fractured enemy releases damaging magical armor fragments from the death position. Genuine fragment contacts apply a portion of the defeated enemy's Fracture pressure. Further eligible kills may propagate. Death Bloom remains a separate explosion, not replaced. Ownership follows the triggering player under the owner-specific status/kill rules. Counts/range/transfer caps are authored.

<a id="evolution-e08b"></a>
**E08B - Sunder Pulse. Recipe: Fracture 5 + Battle Tempo.** Subsequent qualifying hits against a target already at maximum Fracture generate additional magical pulses from it without consuming stacks. Reaching maximum establishes eligibility; it is not itself a guaranteed extra same-hit pulse. Works on isolated eligible bosses without kills. Pulse damage can participate only in explicitly compatible follow-ups. Preserve Total Exposure and normal defense erosion.

### P09. Death Bloom
<a id="catalog-p09"></a>

**Category:** Trigger / elimination reaction. **Base:** A qualifying player-credited enemy death causes a magical explosion at the death location. Eligible weapons, companions, mines, DoTs and rune reactions can provide the kill. Explosion kills can create further Death Blooms. Successive explosions in a connected kill cascade increase strength up to an amplification cap; subsequent legitimate kills can continue at that cap. Damage without another qualifying kill does not advance the cascade. Separate cascades begin with their own initial state.

| Rank | Development |
|---|---|
| 1 | Kill-triggered magical explosions with bounded cascade amplification. |
| 2 | Ordinary compatible scaling. |
| 3 - Expanding Bloom | Connected-cascade explosion radius grows to a separate cap. |
| 4 | Further compatible scaling. |
| 5 - Bloom Convergence | Spatially and temporally overlapping active Death Bloom damage areas create a concentrated magical burst in their actual shared area. |

Visual particle overlap is not enough for Bloom Convergence. Original explosions retain damage; eligible convergence kills can continue the cascade. Multi-explosion pair accounting and overlap timing remain authored details. No universal maximum chain length is imposed.

<a id="evolution-e09a"></a>
**E09A - Bloom Reserve. Recipe: Death Bloom 5 + Battle Tempo.** Qualifying kills generate limited stored Bloom charges while normal explosions/cascades remain. A subsequent successful eligible automatic attack can spend a charge to explode against a living enemy at its actual impact; the enemy need not die first. This carries crowd-earned offense into an isolated boss fight. Stored capacity and charge spending per event are bounded. Misses do not supply the successful-hit trigger or generate charges.

<a id="evolution-e09b"></a>
**E09B - Gravegarden. Recipe: Death Bloom 5 + Runic Mine.** Each qualifying kill retains the original explosion and leaves a temporary damaging magical blossom at the death location. Enemies must actually intersect it at damage intervals. Multiple fields can coexist/overlap under authored limits; valid field kills can create further eligible Death Bloom/Gravegarden effects. Fields do not attack distant enemies or reveal secrets. Exact overlapping-damage accounting is source-specific.

### P10. Echo Strike
<a id="catalog-p10"></a>

**Category:** Trigger / attack replication. **Base:** Qualifying successful main-weapon and independent-power attacks generate a delayed spectral copy preserving appropriate delivery, geometry and collision. Triggered attacks require explicit eligibility. Projectile echoes can miss; melee and area copies require real contact. It copies an attack event, not permanent power ownership: an echoed mine explosion does not create an extra persistent mine, and a blade copy is not another permanent orbit.

| Rank | Development |
|---|---|
| 1 | Delayed compatible attack copy. |
| 2 | Ordinary compatible scaling. |
| 3 - Resonant Fidelity | Bounded echo damage amplification based on distinct enemies actually struck by its parent attack; repeated hits on one enemy do not inflate the distinct count. |
| 4 | Further compatible scaling. |
| 5 - Adaptive Echo | Compatible copies independently select valid targets on activation; retain source-specific location/range restrictions. |

Adaptive Echo does not relocate a stationary mine explosion across the world or add homing. Sharpsight can improve compatible initial aiming. Activation delay, copy damage, extra cost scopes, per-parent copy multiplicity and the sampling point for a still-traveling parent's distinct-hit count remain authored details.

<a id="evolution-e10a"></a>
**E10A - Endless Reverberation. Recipe: Echo Strike 5 + Battle Tempo.** An eligible echo that genuinely hits can schedule another delayed echo wave. Each wave must independently qualify; a miss ends its branch without canceling other branches. No arbitrary fixed depth prohibition. Authored damage progression, lifetime/cost/continuation safeguards prevent unintended infinite computation. Resonant Fidelity may use each parent wave's distinct hits; Adaptive Echo may find new valid targets. Echo copies retain associated original source identities by default.

<a id="evolution-e10b"></a>
**E10B - Mirror Array. Recipe: Echo Strike 5 + Sharpsight.** Generate multiple delayed copies from distinct authored offset origins. Each uses actual geometry, suitable delivery, compatible prediction and collision. They are attacks, not permanent characters/weapons. Offset placement, count and timing remain bounded/authored. Compatible rank milestones apply; no new independent source per copy.

### P11. Collision Burst
<a id="catalog-p11"></a>

**Category:** Trigger / physical impact reaction. **Base:** Player-owned displacement drives an enemy into another compatible enemy or suitable solid obstacle, producing an area shockwave at the real collision point. The displaced enemy and other eligible enemies within its area can take damage. No actual movement/impact means no trigger. Ordinary crowd contact or an ineffectual Force hit is insufficient.

The base shockwave does not inherently displace surrounding creatures. Force is a useful source, not a requirement. Ownership follows the primary eligible displacement cause. Exact base shockwave damage classification is not consistently stated in the record and remains an authored property, not inferred from the word "collision."

| Rank | Development |
|---|---|
| 1 | Genuine impact produces a damaging area shockwave. |
| 2 | Ordinary compatible scaling. |
| 3 - Impact Velocity | Damage increases with actual impact speed to a cap; does not itself expand radius. |
| 4 | Further compatible scaling. |
| 5 - Compression Burst | Solid-environment obstacle impacts gain damage and radius; enemy-to-enemy collisions keep ordinary behavior. |

<a id="evolution-e11a"></a>
**E11A - Momentum Relay. Recipe: Collision Burst 5 + Force Rune.** Shockwaves gain outward displacement. Each genuinely displaced enemy that subsequently collides can create another valid Collision Burst. Preserve resistance, physical geometry, attenuation and source ownership. No automatic chain length cutoff, but each new impact must actually occur. This is an explicit force-producing mechanic, unlike passive collisions that cannot create energy.

<a id="evolution-e11b"></a>
**E11B - Aftershock Field. Recipe: Collision Burst 5 + Runic Mine.** Preserve the immediate impact burst and leave a temporary stationary magical field at that collision location. It emits additional timed damaging shockwaves; each must actually reach an enemy. Multiple fields may coexist under authored limits. No extra knockback absent another compatible effect. Impact Velocity/Compression Burst carry only according to authored compatibility; exact pulse inheritance coefficients remain tunable.

### P12. Reprisal Pulse
<a id="catalog-p12"></a>

**Category:** Trigger / defensive retaliation. **Base:** A genuine enemy hit damaging HP or an active personal barrier releases a magical area pulse around the hero. Fully absorbed barrier hits qualify. Misses, complete evasion, ineffective hits and self-paid HP costs do not. It does not negate the incoming attack or automatically make the player safe.

| Rank | Development |
|---|---|
| 1 | Automatic magical counterattack from genuine hostile HP/barrier damage. |
| 2 | Ordinary compatible scaling. |
| 3 - Proportional Wrath | Bounded damage amplification from actual HP plus barrier damage sustained by that triggering hit; prevented damage is excluded. |
| 4 | Further compatible scaling. |
| 5 - Expanding Wrath | Consecutive qualifying incoming hits build bounded pulse radius; decays without such hits. |

The same enemy hit's HP/barrier outcomes are not automatically separate retaliation activations. Retaliation limits are authored; no assumption of every simulation frame. Expanding Wrath does not automatically enlarge summoned blade orbit radius.

<a id="evolution-e12a"></a>
**E12A - Mirror Guard. Recipe: Reprisal Pulse 5 + Vital Exchange.** Qualifying retaliation damage generates capped temporary barrier protection. Original pulse remains. Creating a barrier is not receiving a hit and cannot by itself trigger another pulse. A new real hostile hit can damage that barrier and qualify. Vital Exchange separately heals eligible actual enemy HP damage. Barriers cannot pay self-HP costs.

<a id="evolution-e12b"></a>
**E12B - Vengeful Halo. Recipe: Reprisal Pulse 5 + Spinning Blade.** A qualifying HP/barrier hit retains the normal magical pulse and summons temporary orbiting spectral blades. Blades follow the hero and require genuine contact; the original Spinning Blade remains independently active. Lifetimes/counts and compatibility are authored. A miss, evasion or HP payment cannot summon them. Spectral visual appearance alone does not establish an intangible-target hit permission or a damage-type conversion.

### P13. Ricochet Shard
<a id="catalog-p13"></a>

**Category:** Independent attack; expanded unlock. **Base: Piercing Ricochet.** Automatically fire a physical shard toward a valid target. It pierces compatible enemies and rebounds from compatible solid surfaces according to actual collision angle. Each genuine rebound creates a new segment; an enemy may be hit in a later segment subject to per-target intervals and total projectile hit limits. No resting-contact pseudo-rebounds.

Rebound count/lifetime remain bounded. A destructible surface must still exist at contact to reflect the shard. Constructed geometry may be eligible. Base shard has no force/status and remains useful in open terrain without rebounds.

| Rank | Development |
|---|---|
| 1 | Piercing, physically reflected projectile. |
| 2 | Ordinary compatible scaling. |
| 3 - Rebound Momentum | Genuine rebounds increase projectile damage for remaining life within a cap. |
| 4 | Further compatible scaling. |
| 5 - Splinter Reflection | First successful solid-surface rebound releases one weaker offset shard; splinters do not recursively create more Splinter Reflections. |

<a id="evolution-e13a"></a>
**E13A - Mirror Trajectory. Recipe: Ricochet Shard 5 + Sharpsight.** Evaluate viable reflected paths before launch, increase compatible rebound allowance and improve reflected-splinter prediction. Reflections remain physically determined; no automatic in-flight enemy steering is conferred.

<a id="evolution-e13b"></a>
**E13B - Siege Shard. Recipe: Ricochet Shard 5 + Force Rune.** Genuine solid-surface rebounds emit localized physical shockwaves that damage and push compatible enemies away from the contact. Obstacles and bounded activation limits remain. Real downstream collisions can react; no impact without a real rebound.

**Discovery - Geometry of Impact:** physical mastery using displaced enemies/objects colliding with solid surfaces, achievable through starter Force/environmental mechanics without this power.

### P14. Arcane Tether
<a id="catalog-p14"></a>

**Category:** Independent attack; expanded unlock. **Base: Adaptive Connection.** Automatically create a temporary magical link between two eligible enemies. It follows real endpoint positions, damaging connected enemies and others actually intersecting its line at defined intervals. With one enemy, a valid stationary magical anchor supplies the other endpoint.

An invalid endpoint may be replaced by a nearby eligible enemy or valid stationary anchor, with bounded reconnections. Never reset original duration or damage cadence. Solid geometry suppresses obstructed links. Anchors are not creatures, summons or walls. No base force, cross-dimension connection or unlimited simultaneous tether creation.

| Rank | Development |
|---|---|
| 1 | Adaptive temporary magical connection. |
| 2 | Ordinary compatible scaling. |
| 3 - Elastic Conduit | Increase maximum link length and width within authored bounds. |
| 4 | Further compatible scaling. |
| 5 - Resonant Current | Consecutive successful contact intervals against the same enemy increase link damage to that enemy, capped; losing continuous contact resets its amplification. |

<a id="evolution-e14a"></a>
**E14A - Triune Circuit. Recipe: Arcane Tether 5 + Spatial Reach.** Three endpoints form pairwise links; stationary anchors fill missing enemies. The enclosed interior does not inherently damage. Links share applicable per-target intervals, avoiding damage multiplied merely by multiple overlapping links. All original reconnection/lifetime restrictions remain.

<a id="evolution-e14b"></a>
**E14B - Binding Circuit. Recipe: Arcane Tether 5 + Frost Rune.** Add attraction around the link that gradually pulls compatible Chilled enemies toward its nearest point. Actual contact still required for ordinary damage. Respect displacement resistance and obstacles; real resulting collisions may react. No automatic freezing or unlimited pull through walls.

**Discovery - Forgotten Connections:** restore a damaged conduit network in the Runic Archive, using valid energy connections between ancient mechanisms.

### P15. Spatial Reach
<a id="catalog-p15"></a>

**Category:** Passive modifier; expanded unlock. **Base: Contextual Spatial Expansion.** Independently amplify compatible melee reach/width, projectile range/width, AoE radius, beam dimensions, orbit radius/geometry, link length/width and chaining distance. Each property has explicit limits. Range is not speed, force, damage, duration, chain count, visibility or wall penetration.

Sword/Spear/Daggers/Whip gain compatible reach/geometry; Staff sigil radius; Warhammer impact/wave reach; Bow/Chakram/Shard projectile properties; Focus beam dimensions; Spinning Blade orbit/contact geometry; Mine/Bloom blast radius; Tether link dimensions; Lightning chain distance. Not every property of an affected attack scales automatically.

| Rank | Development |
|---|---|
| 1 | Contextual spatial amplification. |
| 2 | Increase compatible amplification. |
| 3 - Adaptive Coverage | Optimize compatible initial direction/placement to cover additional targets while retaining the selected priority target in intended geometry; no homing or override of player preference. |
| 4 | Further compatible scaling. |
| 5 - Outer Edge | Bounded damage bonus for genuine hits in added coverage outside otherwise applicable geometry. |

<a id="evolution-e15a"></a>
**E15A - Kinetic Expansion. Recipe: Spatial Reach 5 + Momentum Charge.** An eligible attack releasing full Momentum Charge receives additional compatible spatial amplification; its charged shockwave also benefits. This is a movement-earned expanded activation, not universal constant extra damage.

<a id="evolution-e15b"></a>
**E15B - Expanding Domain. Recipe: Spatial Reach 5 + Lingering Essence.** Compatible persistent attack fields gradually expand during their active lifetime to a maximum. Geometry genuinely changes, but expansion neither adds damage ticks nor extends lifetime. Baseline spatial benefits remain global. Dynamic expansion is an explicit exception to activation-fixed geometry; PR10 defines the provisional Outer Edge comparison. [Provisional rules](#gds-rules)

**Discovery - Beyond the Boundary:** damage a required distinct-enemy count through one eligible area attack, achievable with starter Sword/Staff or previously available attacks.

### P16. Lingering Essence
<a id="catalog-p16"></a>

**Category:** Passive modifier; expanded unlock. **Base: Contextual Persistence.** Independently extend compatible owned status, field, summon, structure and buff durations under per-category limits. Supported examples: Bleed duration, Burn lifetime, Chill, Fracture, armed mine life, tether life, Bloodfire, eligible Tempo retention, Crimson Empowerment, Time Fracture, Transmutation, Manifest Guardian and Living Formation.

Duration does not inherently change tick frequency, potency cap, cooldown, world timer, quest deadlines or revival protection. Longer lifespan may produce more scheduled ticks normally. Refresh cannot repeatedly multiply remaining duration. Destruction can still end summons/structures early.

| Rank | Development |
|---|---|
| 1 | Contextual duration amplification. |
| 2 | Increase compatible durations. |
| 3 - Enduring Potency | Compatible persistent effects gradually gain bounded resistance to hostile duration-shortening/removal; cannot defeat absolute removal or mandatory lifecycle termination. |
| 4 | Further compatible scaling. |
| 5 - Final Resonance | Eligible naturally expiring damaging status/field releases one final damage event based on accumulated active duration, with real target eligibility; cannot recreate/refresh itself. |

<a id="evolution-e16a"></a>
**E16A - Eternal Ember. Recipe: Lingering Essence 5 + Flame Rune.** Further extend compatible Burn. At maximum intensity, eligible ticks periodically release localized magical heat pulses damaging nearby enemies. Do not consume/reset Burn or inherently apply additional statuses. Pulse timing and eligibility remain bounded.

<a id="evolution-e16b"></a>
**E16B - Residual Echo. Recipe: Lingering Essence 5 + Echo Strike.** An eligible naturally expired persistent damaging field leaves a weaker temporary afterimage at its final location with compatible geometry and its own intervals. No afterimage-of-afterimage or recursive Final Resonance. Natural-expiration eligibility is not created by forced removal, replacement, realm transition or owner death.

**Discovery - Enduring Influence:** maintain an eligible hostile status continuously on a durable enemy for a required time, achievable with starter Bleed.

### P17. Momentum Charge
<a id="catalog-p17"></a>

**Category:** Trigger power; expanded unlock. **Base: Momentum Retention.** Actual voluntary distance builds charge. After a grace period without movement, partial charge decays; full charge remains stored. The next eligible main-weapon activation consumes it and emits an additional directional magical shockwave with genuine contact and no innate displacement.

Walking against a wall, teleportation, involuntary force and realm transitions do not generate distance. Compatible voluntary Vault travel can. One activation consumes at most one charge; multi-hit stages or beam ticks do not spend additional charges. A missed shockwave is not refunded. Secondary waves neither consume nor independently create movement charge.

| Rank | Development |
|---|---|
| 1 | Movement charge with protected full-charge retention. |
| 2 | Compatible efficiency/shockwave scaling. |
| 3 - Momentum Reserve | Further voluntary movement at full charge fills a limited reserve, less than a complete extra charge; transfers to the next cycle after release. |
| 4 | Further compatible scaling. |
| 5 - Flow State | A charged wave genuinely damaging an eligible enemy grants one temporary movement enhancement per release, with bounded stacking. |

<a id="evolution-e17a"></a>
**E17A - Kinetic Breaker. Recipe: Momentum Charge 5 + Force Rune.** Charged shockwaves gain outward force against eligible enemies/objects, allowing genuine Collision Burst, Momentum Relay, Glacial Impact and environmental chains. Resistance and geometry remain.

<a id="evolution-e17b"></a>
**E17B - Crosscurrent. Recipe: Momentum Charge 5 + Echo Strike.** Schedule one weaker additional wave from the original release location, using the most recent valid voluntary movement direction captured at activation rather than necessarily the attack direction. It must hit and cannot generate further Crosscurrent waves. Preserve reserve and Flow State only through explicitly compatible events.

**Discovery - Unbroken Motion:** sustained voluntary combat movement with successful attacks and genuine evasions, possible on every starter hero. Safe out-of-combat walking alone does not satisfy mastery.

### P18. Converging Strikes
<a id="catalog-p18"></a>

**Category:** Trigger power; expanded unlock. **Base: Independent Source Convergence.** Two distinct compatible player-owned sources damage the same enemy within a window to create an additional magical burst. Each enemy/owner has its own reaction window/cooldown; fresh events are required for a new cycle. A multi-projectile attack, repeated hits from one weapon or several summons from one power are not multiple sources.

Main weapon is one source; each independent power and compatible damaging hero ability can be separate. Evolution retains its original source. Echo copies retain the copied source by default. Rune/secondary effects need explicit distinct-source permission. Convergence damage cannot independently initiate itself.

| Rank | Development |
|---|---|
| 1 | Magical reaction from two distinct compatible sources. |
| 2 | Compatible burst/reaction scaling. |
| 3 - Convergent Shock | Add localized area damage to nearby eligible enemies; this explosion cannot independently start another convergence on them. |
| 4 | Further compatible scaling. |
| 5 - Third Vector | A third distinct source hitting the original target in a follow-up window adds one enhanced burst; does not reset ordinary cooldown. |

<a id="evolution-e18a"></a>
**E18A - Unified Assault. Recipe: Converging Strikes 5 + Battle Tempo.** Successful convergence grants a temporary enhancement to the next eligible activation from a source not participating in that convergence. It expires if unused and has bounded stored charges. This rewards source diversity, not duplicated copies of one attack.

<a id="evolution-e18b"></a>
**E18B - Convergence Circuit. Recipe: Converging Strikes 5 + Arcane Tether.** Convergence on an enemy intersecting an owned active tether sends additional magical pulses along real compatible links. They damage enemies encountered, respect obstructions/propagation bounds and support explicitly compatible evolved networks. They do not automatically become independent convergence sources.

**Discovery - Unified Offensive:** damage an elite/boss with at least three distinct eligible owned sources within a defined window, achievable with main weapon plus starter-pool independent powers/hero delivery.

### 9.1 Expanded power availability

All six expanded discovery requirements are followed by permanent-currency ownership, with explicitly designated direct-unlock exceptions. Discovery survives defeat, but permanent ownership does not grant the power during an active run. It becomes eligible for subsequent prepared candidate pools and must be acquired/ranked each run. Base unlock does not reveal Evolution recipes automatically. Existing wildcard discovery remains supported without silently overriding a fully prepared pool.

### 9.2 Transformation knowledge and planning

Standard Evolution full-recipe verification remains personal and tied to actual acquisition; owning ingredients, seeing an option, declining it or witnessing a teammate is insufficient. Acquisition while spectating still verifies it and survives defeat. Archivist hints can progress toward understanding without granting ownership or free transformation. Fusion knowledge has the separately approved five-stage path described next. The initial interface uses passive Codex/build-panel inspection, not automatic reward weighting or a mandatory build planner.

## 10. Advanced Fusion system and six complete recipes
<a id="gds-fusions"></a>

**Basis:** V38.1-V38.14, supplemented by later combat-resolution rules. Fusion is an authored hybrid of two specifically compatible acquired Evolution forms, not a universal combine-anything operation or a random extra statistical tier. Both must be legitimately acquired during the same run. An eligible Fusion appears through subsequent ordinary power reward opportunities, costs one selection, requires no additional consumable catalyst or permanent-currency payment, and occupies both original slots.

Fusions are voluntary and irreversible for the run. Declining preserves future eligibility while prerequisites remain valid. Undiscovered recipes can appear when mechanically satisfied. Multiple independent Fusions can coexist if components do not overlap and all catalyst/rune requirements can be met. A Fusion cannot be an ingredient of a higher recursive Fusion tier. Its component properties can still serve as ordinary catalysts when explicitly preserved.

### 10.1 Contextual Hybrid Inheritance

Each recipe declares preserved, transformed, combined and replaced properties. Disclose meaningful losses/tradeoffs before selection. Do not silently duplicate attacks, buffs, charges or lifecycles on transition. No implicit cooldown reset, resource refill, healing, summon duplication or restored durability.

Preserved attacks retain original source identities; transformed attacks retain their associated source by default. A combined attack uses explicit recipe identity. New Fusion reactions are secondary sources, not automatically independent for Converging Strikes. External catalysts stay owned and active. Ownership and real collision/targeting remain unchanged.

| ID | Fusion | Component Evolutions | Consumed base slots | Additional requirements |
|---|---|---|---|---|
| F01 | Seismic Arsenal | Seismic Mine + Siege Shard | Runic Mine + Ricochet Shard | Force equipped |
| F02 | Infinite Domain | Triune Circuit + Expanding Domain | Arcane Tether + Spatial Reach | Lingering Essence catalyst retained |
| F03 | Thermal Equilibrium | Eternal Ember + Binding Circuit | Lingering Essence + Arcane Tether | Flame and Frost equipped |
| F04 | Relentless Chorus | Blade Tempest + Unified Assault | Spinning Blade + Converging Strikes | Battle Tempo retained |
| F05 | Grave Resonance | Gravegarden + Residual Echo | Death Bloom + Lingering Essence | Runic Mine and Echo Strike retained |
| F06 | Sanguine Aegis | Crimson Reservoir + Mirror Guard | Vital Exchange + Reprisal Pulse | Reciprocal component catalysts; no additional rune/power |

Each component already requires its base at Rank 5. Catalyst powers consume their ordinary slots unless already legitimately part of the retained build. They are not free hidden ingredients.

### F01. Seismic Arsenal - Reciprocal Seismic Resonance
<a id="catalog-f01"></a>

**Identity:** Reciprocal interactions between piercing reflected projectiles and seismic traps. Preserve both independent offensive foundations, not just one merged explosion.

**Projectile to mine:** A genuine Siege Shard rebound creates a physical shockwave. If that wave actually reaches a compatible armed Seismic Mine, it activates the mine's normal detonation even without enemy proximity. Unarmed mines cannot be detonated by this Fusion interaction.

**Mine to projectile:** A Seismic Mine's actual wave can charge a compatible shard it physically contacts. The charged shard's next genuine rebound shockwave gains bounded compatible damage, radius and displacement. The rebound consumes the accumulated seismic charge. Charge cannot replenish rebounds, extend projectile lifetime or create more mines.

| Preserved | Integrated / new |
|---|---|
| Mine placement, Twin Runes and Pressure Charge | Shockwaves can trigger armed mines. |
| Normal Seismic Mine explosion and displacement | Mine waves can charge shards. |
| Piercing Ricochet, Rebound Momentum and Splinter Reflection | Next real rebound consumes charge for an enhanced wave. |
| Siege Shard physical shockwaves | Bounded conditional empowerment. |

Each mine detonates once. Shard counts, lifetime, hit limits and amplification remain finite. No automatic mine-to-mine ignition is added: that was the unselected Seismic Chain Network alternative, not Reciprocal Resonance. Original mine and projectile source identities remain separate. The Architect can supply compatible rebound geometry; Gravity Weaver can strengthen force; actual collision chains may activate Collision Burst/Momentum Relay. Other rune-pair opportunities still require a legal second rune. Both component attacks remain functional in open terrain without a Fusion contact.

### F02. Infinite Domain - Resonant Domain
<a id="catalog-f02"></a>

**Identity:** A moving three-endpoint network whose widening perimeter can support a damaging interior. Triune Circuit's links retain ordinary magical contact damage. Expanding Domain progressively widens compatible coverage across the original active lifetime, within caps.

When three endpoints form a valid unobstructed enclosed triangle, its actual interior periodically emits a weaker magical pulse. Collinear/coincident endpoints, lost enclosure or obstructed required links suspend interior pulses. Stationary anchors may complete the network when enemies are insufficient. A bounding circle or rectangle is not the actual damaging interior.

| Preserved | Integrated / new |
|---|---|
| Adaptive Connection, Elastic Conduit, Triune Circuit | Bounded expansion of link coverage. |
| Resonant Current | Applies to qualifying link damage, not automatically interior pulses. |
| Global Contextual Spatial Expansion and Adaptive Coverage | Other attacks keep Spatial Reach benefits. |
| Outer Edge and global Expanding Domain | Eligible expanded geometry remains meaningful. |
| Existing per-target link intervals | Separate periodic interior resonance. |

Multiple links keep their shared per-target damage accounting. Interior pulses are distinct scheduled events with their own limits and do not multiply by the number of intersected links. Reconnection does not reset lifetime, expansion progress or tick intervals. Pulses are not automatically new independent sources. No inherent attraction, displacement or status is added. Lingering Essence remains a catalyst and may extend compatible duration. Convergence Circuit can interact through explicitly compatible links without treating a Fusion as a new recursive ingredient.

### F03. Thermal Equilibrium - Thermal Conduction
<a id="catalog-f03"></a>

**Identity:** Sustain and distribute elemental interactions along Binding Circuit. Require **Flame + Frost**, occupying both rune slots. Preserve Burn's increasing intensity, Chill's fixed non-stacking slow, Thermal Shock's per-owner/target cooldown and Binding Circuit's damage/attraction.

**Thermal Transmission:** A qualifying Thermal Shock on an enemy intersecting an active owned Binding Circuit sends damaging magical thermal pulses along compatible actual links. Physical obstructions can stop propagation. A pulse must genuinely encounter a valid target.

**Elemental Transfer:** An eligible Eternal Ember heat pulse against a target on a link can conduct a bounded Burn portion to other Chilled enemies genuinely reached. Ordinary Thermal Transmission does not transfer Burn. Source Burn/intensity and Chill duration remain intact; copied potency, duration and ownership obey transfer restrictions. Transfer cannot automatically refresh a stronger existing Burn. PR10 specifies the provisional equal/weaker/stronger comparison per owner. [Provisional rules](#gds-rules)

| Preserved | Integrated / new |
|---|---|
| Global Contextual Persistence, Enduring Potency, Final Resonance | Heat-pulse-triggered bounded elemental transfer. |
| Eternal Ember | Conductive heat interaction. |
| Adaptive Connection, Elastic Conduit, Resonant Current | Real links carry thermal pulses. |
| Binding Circuit attraction | Still requires Chilled eligible enemies/resistance. |
| Persistent Combustion, Persistent Chill, Thermal Shock | Original statuses/reaction remain independent. |

Conductive pulses do not independently reproduce themselves. No automatic Chill application, freezing, immunity removal or unbounded status refresh. A single target remains supported through stationary anchor geometry. Original source identities remain intact. Infinite Domain cannot coexist because both consume Arcane Tether; Seismic Arsenal cannot coexist under these recipes because Force plus Flame plus Frost would exceed two rune slots.

### F04. Relentless Chorus - Synchronized Rhythm
<a id="catalog-f04"></a>

**Identity:** Orbital contact helps initiate source-diverse coordinated attacks. Preserve Blade Tempest's continuous counter-rotating formations and Unified Assault's nonparticipant-source enhancement.

**Chorus Charge:** A genuine Converging Strikes reaction involving Blade Tempest's orbital damage grants bounded synchronization charge.

**Chorus Strike:** The next eligible independent activation from a source that did not participate in that convergence spends the charge, receives the ordinary Unified Assault enhancement, and emits additional temporary physical spectral blades from the player's current position along that attack's committed direction. This is one qualifying consumption/enhancement opportunity, not two costs. The traveling blades require real contact and do not replace the orbit.

| Preserved | Integrated / new |
|---|---|
| Spinning Blade, Twin Blades, Razor Momentum, Blade Tempest | Orbital convergence produces Chorus Charge. |
| Independent Source Convergence, Convergent Shock | Charge connects to the next valid independent activation. |
| Third Vector | Still requires an actual later hit by a third source. |
| Unified Assault | Enhancement is integrated with Chorus Strike. |

All orbiting and Chorus spectral blades retain Spinning Blade source identity. Chorus blades cannot independently generate another Chorus Charge. A source without meaningful directional delivery needs explicit Chorus compatibility rather than an invented aim direction. Battle Tempo is an independent retained catalyst. No convergence cooldown reset or orbital interval reset. Example: blade plus Sword converge; Spectral Lance activation releases the Chorus strike; only its genuine timely hit can then satisfy Third Vector.

### F05. Grave Resonance - Resonant Renewal
<a id="catalog-f05"></a>

**Identity:** Persistent kill fields leave residual effects that prepare enemies for new empowered fields through independent offense.

**Grave Imprint:** Actual residual blossom damage applies a temporary non-stacking owner-specific imprint.

**Resonant Rebirth:** If another eligible owned source outside the Gravegarden attack family kills the imprinted enemy, the corresponding new Gravegarden blossom is empowered with bounded damage/coverage. It **replaces** the ordinary blossom that kill would create, not duplicates it. Consume the imprint. Its residual descendant returns to ordinary afterimage strength; empowered generations cannot compound indefinitely.

| Preserved | Integrated / new |
|---|---|
| Death Bloom, Expanding Bloom, Bloom Convergence | Existing kill/cascade mechanics continue. |
| Gravegarden | A qualifying independent kill can empower its corresponding field. |
| Global Contextual Persistence and Enduring Potency | Other compatible effects retain duration benefits. |
| Final Resonance | Eligible original lifecycles only. |
| Residual Echo globally | Residual blossom contacts can apply Grave Imprint. |

Each original field creates at most one residual afterimage; residuals create neither further afterimages nor Final Resonance. Forced removal is not natural expiration. Existing contact intervals, active-field limits and attribution remain. Runic Mine and Echo Strike stay independent catalysts. Kills and progression entitlements are not duplicated. A residual's own kill is not an "independent source" Rebirth even though other legitimate on-kill effects may still be allowed.

### F06. Sanguine Aegis - Reciprocal Sanguine Cycle
<a id="catalog-f06"></a>

**Identity:** Connect stored excess healing, barrier protection and genuine damage absorption to retaliation. Crimson Reservoir and Mirror Guard are reciprocal component catalysts; no external rune/power is required.

**Crimson Fortification:** When Mirror Guard validly generates a barrier, consume a bounded real portion of stored Crimson Reservoir to strengthen that barrier. The unspent reserve keeps its authored recovery purpose. Reserve cannot be created from nothing or spent twice.

**Aegis Release:** Track eligible hostile damage actually absorbed by this specific fortified barrier. If hostile damage depletes it, emit one additional magical pulse around the player, scaling with that absorbed amount within a cap. Damage absorbed by Life Harvest, Shrine or other unrelated barriers does not charge it.

| Preserved | Integrated / new |
|---|---|
| Vital Exchange, Survival Instinct, Recovery Surge | Ordinary HP recovery remains independent. |
| Crimson Reservoir | Actual reserves fuel fortification. |
| Reprisal Pulse, Proportional Wrath, Expanding Wrath | Genuine hostile-hit retaliation remains. |
| Mirror Guard | Bounded defensive generation remains. |
| Independent barrier lifecycles | Fortified layer tracks absorbed damage and one release. |

Natural expiry, voluntary removal, replacement, capacity clamp and decay do not trigger Aegis Release. Replacement discards its accumulated charge. HP sacrifices cannot be absorbed or charge retaliation. Aegis Release cannot directly activate Mirror Guard, itself or another release; eligible Vital Exchange can heal missing HP, but release-generated overhealing cannot refill Crimson Reservoir. No automatic resurrection, lethal prevention or invulnerability. Independent recovery/barrier systems remain compatible without closing an unintended self-sustaining conversion loop.

### 10.2 Fusion discovery and passive planning

Fusion knowledge persists through **Unknown -> Rumored -> Partially Identified -> Recipe Identified -> Experimentally Verified**. The Recipe Identified stage can reveal full acquisition requirements before acquisition; actual successful selection verifies the complete mechanic. This Fusion-specific progression is distinct from earlier standard Evolution full-recipe verification rules. Spontaneous acquisition can skip intermediate knowledge stages.

Thematic knowledge opportunities: Seismic Arsenal through Foundry/Artisan research; Infinite Domain through Archive/Observatory; Thermal Equilibrium through elemental inscriptions/Archivist; Relentless Chorus through combat mastery/Hall of Echoes; Grave Resonance through Catacombs/Forgotten Lands; Sanguine Aegis through Restorer/Stranger. These are discovery opportunities, not additional mandatory recipe ingredients.

No permanent-currency purchase is required for knowledge progression, no external guide requirement, no mandatory challenge modifier, and no automatic component ownership. All meaningful changes are disclosed at the offer. Initial planning is passive inspection only; informational tracking UI is deferred pending player need and never implies reward-probability manipulation.

## 11. World, geography, realms and final transition
<a id="gds-world"></a>

**Basis:** M15 sections 9-12, 18; V34.1-V34.10; V35-V36; V40 threat scaling.

### 11.1 Procedural world contract

One generated run offers more content than an ordinary player is expected to visit. Use interconnected regions, loops, alternate physical routes, backtracking and meaningful shortcuts, not a compulsory central hub or three disconnected locked levels. Hybrid procedural generation combines authored landmarks/puzzle/encounter modules with variable geography, placement, routes and populations; it does not require arbitrary geometry generation.

Each faction has a recognizable core environment and transitional territory with mixed terrain, contested landmarks and overlapping faction activity. All core regions are reachable without mandatory regional boss victory, minimum level or specific build. No general fast travel. Ordinary regional enemies have authored limited pursuit; Hunters can pursue across compatible regional boundaries. Exact portal pursuit is not inferred as unlimited cross-dimension tracking.

| Region | Dominant faction | Terrain and exploration |
|---|---|---|
| Primeval Wilds | Wildborn | Ancient forests, grassland, ravines, enormous roots, dens and overgrown ruins. |
| Runic Expanse | Runebound | Abandoned arcane cities, workshops, geometric ruins, monumental machinery. |
| Forgotten Lands | Hollow Legion | Silent settlements, ruined castles, burial grounds, dead forests, temples and spectral remnants. |
| Transitional territories | Mixed | Organic terrain blends, contested sites and faction encounters. |

### 11.2 Twelve landmark types

| Region | Landmark | Availability | Approved exploration function |
|---|---|---|---|
| Primeval Wilds | Ancient Worldtree | Guaranteed regional anchor | Winding roots, hidden chambers and elevated natural paths. |
| Primeval Wilds | Beast's Den | Variable | Dangerous caves and concentrated Wildborn threats/rewards. |
| Primeval Wilds | Overgrown Sanctuary | Variable | Reclaimed architecture, inscriptions and environmental mechanisms. |
| Primeval Wilds | Whispering Falls | Variable | Pools, waterfalls, concealed passages and routes. |
| Runic Expanse | Ancient Foundry | Guaranteed regional anchor | Dormant production machinery, constructs and restoration. |
| Runic Expanse | Runic Archive | Variable | Magical knowledge, rune clues and concealed chambers. |
| Runic Expanse | Silent Observatory | Variable | Celestial/focusing mechanisms and exceptional discoveries. |
| Runic Expanse | Sealed Vault | Variable | Fortified optional mechanisms, defenders and valuable rewards. |
| Forgotten Lands | Fallen Citadel | Guaranteed regional anchor | Ruined fortress halls/walls, combat and architectural exploration. |
| Forgotten Lands | Endless Catacombs | Variable | Interconnected burial chambers and necromantic threats. |
| Forgotten Lands | Abandoned Village | Variable | Environmental stories, NPCs, hidden quests and inhabitants' remnants. |
| Forgotten Lands | Veiled Shrine | Variable | Supernatural interactions, secrets and possible special-realm access. |

Locations, interiors, routes, encounters, secrets and rewards vary. A familiar landmark does not guarantee identical treasure or an identical puzzle. "Guaranteed" refers to the landmark's presence, not automatic discovery or reward ownership.

### 11.3 Exploration knowledge and layered secrets

Physical exploration reveals map geometry; discovered geometry persists during the run and is shared across the party. Fog is not removed merely because a projectile travels far or a mobile NPC moves. Map/compass can assist without solving routes.

Layered Discovery supports observation, experimentation, knowledge and emergent interactions. Visual cracks, unusual vegetation, water concealment, inscriptions, contextual audio, NPC clues, mechanisms, enemy-caused destruction and unusual compatible reactions can reveal optional content. No automatic undiscovered-secret icon or "secret nearby" announcement. Specialization can open optional alternatives but mandatory paths cannot require a specific hero/rune/power. Prior knowledge may help across runs without guaranteeing the same location.

Completed mechanisms and opened shortcuts persist. Backtracking does not reset defeated entities or completed events, although normal new spawning continues. PR11 defines when the last relevant occupant has abandoned an incomplete resettable puzzle. [Provisional rules](#gds-rules)

### 11.4 Special realms

| Realm | Identity and activities |
|---|---|
| Inverted Archive | Distorted repository, disconnected/impossible-looking architecture, rare knowledge, spatial puzzles and unlock opportunities. |
| Silent Garden | Isolated supernatural vegetation, restorative mechanisms, mysterious inhabitants and bargains. |
| Fractured Beyond | Unstable pocket terrain, spatial hazards, powerful Unravelling encounters and exceptional risk/reward. |
| Hall of Echoes | Ancient-battle manifestations, specialized combat conditions, mastery and unlock opportunities. |

These are independent optional interconnected environments, not one-room loot pockets or compulsory locked trials. Players can enter/leave independently through valid exits without completing every encounter. World time and shared XP continue across realms. Existing builds/resources carry over under normal lifecycle rules. Combat requires compatible spatial presence; links/attacks cannot connect across dimensions merely because XP is shared.

Corpses remain in their real realm, requiring physical rescue. Revealed entrances provide applicable shared knowledge. Collapse applies globally; realms are not indefinite sanctuaries, and valid exits remain reachable. Existing realm content/puzzles may continue; new optional event starts are disabled after Collapse, with PR11 distinguishing dormant trials, continuing activities and exits.

### 11.5 World Collapse and the final gateway

At **25:00**, activate Collapse, reveal the exact final gateway and major regional connections to the party, and provide direction without an automatically solved route. Local unexplored geometry and optional secrets remain fogged. The gateway must be physically reachable through ordinary compatible movement, not necessarily nearby.

Any one living party member entering the gateway transports the whole party, including players/corpses in other realms. Dead teammates remain dead. No unanimous readiness vote was approved for this established transition. Existing revival death counts/waits carry over. Unfinished events resolve through their previously disclosed gateway/abandonment rules.

Overworld AI, spawns, projectiles, hazards and pending catastrophe activity stop/clean up. Cleanup is not an elimination, XP event, lifesteal source or natural expiry reward. Player builds/resources and legitimate remaining timed effects follow their own transition rules; no free full heal, resource reset or barrier refill is implied. A short safe preparation interval in the final arena precedes the boss; it is a specific exception to ordinary non-pausing, unsafe NPC interactions. Boss activation occurs after its authored interval even if someone remains dead. Living players may revive eligible teammates physically. Exact preparation seconds are delegated tuning.

### 11.6 Collapse environment

Progressive Reality Fracturing creates localized reality fissures, gravity anomalies, temporary unstable geometry, distorted ground and traveling storms while scenery visibly deteriorates. Ground/obstacle damage and control follow actual compatibility, not invisible universal punishment. Essential routes, final gateway access and body-rescue routes remain physically possible. No shrinking boundary or automatic destruction of all remaining secrets. Hazard overlaps must preserve readable warnings and feasible escape geometry.

Existing events can continue; no new optional challenge/support event begins after 25:00. Accepted NPC interactions/services and existing mechanisms remain available. This restriction does not stop Hunter arrivals, combat drops or automatic catastrophic hazards, which are continuing world escalation rather than optional event activation. PR11 governs a previously dormant trial discovered during Collapse. [Provisional rules](#gds-rules)

## 12. Regional enemies and elites
<a id="gds-enemies"></a>

**Basis:** V31.1-V31.41. Each regional faction has six ordinary archetypes, one authored elite counterpart per archetype and one regional boss. Role labels guide diversity rather than requiring identical behavior across factions. Ordinary and elite enemies display **no HP bars**. Distinguish them by readable silhouettes, animation, sound and effects. Only regional bosses have overhead bars; the final boss has a screen-level bar.

All attacks require genuine geometry, protected preparation and appropriate recovery. Intentional control weaknesses, durability, mass and status resistances are authored per enemy, not inferred universally from faction identity. Compatible faction battles and environmental effects can damage enemies/bosses. Friendly NPCs remain protected.

### 12.1 Wildborn ordinary roster

| Enemy | Profile | Confirmed combat behavior and counterplay |
|---|---|---|
| **Fangling** | Small, low durability, moderately fast, low displacement resistance | **Instinctive Pack Hunting:** independent aggressive pursuit spreads around occupied attack positions to approach from several directions. Short physical bites with brief recognizable preparation. Not rigid synchronized formation AI. Pack casualties do not disable survivors. Area attacks and real displacement are useful. |
| **Prowler** | Medium, moderate durability, fast, low/moderate displacement resistance | **Stalking Pounce:** circle for an attack angle, visibly crouch/prepare, launch a committed directional physical pounce, then recover exposed. No continuous course correction to guarantee a hit. Direction changes after commitment can evade it. |
| **Thornback** | Medium, moderate durability/speed/resistance | **Quill Volley:** maintain distance, visibly raise quills and commit a directional spread of independent physical spines. Fixed non-homing travel and gaps between projectiles. Retreat when approached where possible. |
| **Ironhide** | Large, high durability/resistance, slow normal movement, fast charge | **Unstoppable Stampede:** prepare a committed multi-creature directional charge. Damage hostile targets, displace eligible creatures including Wildborn allies; allies receive no direct charge damage. Stop at solid obstacles or charge distance, then recover. Enemy-generated movement/kills do not automatically belong to the player. |
| **Howler** | Medium/large support, moderate durability/speed | **Frenzy Howl:** visible/audio preparation, temporary nearby Wildborn movement and compatible attack-frequency enhancement. Keep individual attack identities and minimum tells. Multiple buffs are bounded. Basic close physical bite. Killing it prevents future howls, not an invented removal of every already valid buff. |
| **Burrowmaw** | Medium/large, moderate durability, underground specialist | **Tunnel Pursuit:** visible moving surface disturbances show subterranean travel. Lock and telegraph an emergence location, emerge with damage, then remain exposed through recovery. No silent retarget after commitment. Depth compatibility applies while fully burrowed. |

### 12.2 Wildborn elite roster

| Elite | Base | Added authored mechanic |
|---|---|---|
| **Razorfang** | Fangling | **Double Bite:** two consecutive biting attack windows; avoiding the first does not remove the second. |
| **Dreadstalker** | Prowler | **Intercepting Pounce:** predict movement before a telegraphed commitment; later course change can evade it. |
| **Quillstorm** | Thornback | **Staggered Volley:** sequential spreads at different angles, with changing safe projectile gaps. |
| **Siegebreaker** | Ironhide | **Cataclysmic Stampede:** multi-target charge plus a separately telegraphed terminal shockwave. |
| **Alpha Howler** | Howler | **Dominant Howl:** retain offensive howl and coordinate nearby allies toward a selected hostile from complementary directions. |
| **Earthshaker** | Burrowmaw | **Burrowing Rampage:** visible underground path produces sequential telegraphed eruptions before final emergence. |

These elites add behavior, not just HP/damage. High-frequency enhancements cannot remove valid attack preparation or recovery opportunities. Exact elite multipliers remain delegated tuning.

### 12.3 Runebound ordinary roster

| Enemy | Profile | Confirmed combat behavior and counterplay |
|---|---|---|
| **Rune Sentinel** | Medium, moderate/high durability, slow/moderate, moderate force resistance | **Legion Advance:** flexible frontline spacing, deliberate committed physical blade strikes and visible preparation. Can break formation, pursue independently and reorganize after displacement. Formation is not immunity. |
| **Bulwark** | Medium/large, high durability/resistance, slow | **Living Bastion:** real directional shield collision intercepts compatible attacks while it positions between hostiles and vulnerable allies. Short shield bash. Side/rear angles and compatible area/ground delivery can bypass its covered geometry. No universal immunity aura or assumption that all magic ignores it. Shield durability and intercepted-hit triggers remain explicit open details. |
| **Rune Artillery** | Medium, moderate durability/resistance, slow | **Runic Bombardment:** sequential explosive magical projectiles, independently selected and fixed telegraphed landing areas per shot. Prefer protected backline. Launched shots do not chase a moving player. Each explosion needs actual area contact. |
| **Stone Colossus** | Large, high durability, very high force resistance, slow | **Runic Rupture:** a ground strike generates branching committed fissure paths with traveling damage and safe gaps. Heavy melee sweep supports close combat. Exposed heavy recovery. No silent path rewriting, permanent terrain destruction or implicit underground hit capability. |
| **Rune Mender** | Small floating support, low/moderate durability | **Restoration Link:** one damaged eligible ally at a time, visible gradual HP repair up to maximum. Interrupt through eligible control, excess range, blocking terrain or caster death. No resurrection; multiple Menders cannot produce unbounded healing. |
| **Arc Conduit** | Medium, moderate durability, slow/moderate | **Arc Network:** several temporary bounded links to compatible nearby allies. Warnings precede damaging activation. Endpoints' actual positions determine lines. Expiry, excess range or endpoint death ends relevant links; caster death removes its network. Only intersecting lines damage, not the whole enclosed perimeter. Contact intervals prevent per-frame damage. |

### 12.4 Runebound elite roster

| Elite | Base | Added authored mechanic |
|---|---|---|
| **Rune Praetorian** | Rune Sentinel | **Runic Discipline:** frontal wide sweep followed by narrow thrust, each separately telegraphed; retain Legion Advance. |
| **Aegis Bastion** | Bulwark | **Projected Aegis:** temporary visibly activated wider magical shield geometry intercepting compatible attacks. |
| **Siege Oracle** | Rune Artillery | **Siege Pattern:** supplement sequential bombardment with simultaneous distributed danger zones and viable escape gaps. |
| **Worldbreaker** | Stone Colossus | **Cataclysmic Rupture:** delayed secondary eruptions along committed fissures, each with its own protected warning. |
| **Rune Architect** | Rune Mender | **Restoration Network:** multiple individually interruptible repair links with bounded total healing. Distinct from the playable Architect. |
| **Nexus Conduit** | Arc Conduit | **Interlinked Nexus:** additional links between compatible allied endpoints, not just caster-to-ally spokes. Bound counts/coverage and preserve navigability. |

### 12.5 Hollow Legion ordinary roster

| Enemy | Profile | Confirmed combat behavior and counterplay |
|---|---|---|
| **Hollow Soldier** | Medium, moderate durability/speed, low/moderate force resistance | **Relentless March:** independent persistent pursuit and committed physical weapon strikes; no retreat from damage or allied deaths. Does not inherently gain control immunity, faster recovery or self-resurrection. |
| **Wraith** | Medium, low/moderate durability, fast, state-dependent interaction | **Spectral Pursuit:** visibly intangible during periodic approach; materialize before telegraphed close magical attack and remain materialized through recovery. Explicit Spectral Compatibility governs vulnerability; every starter weapon has usable exposed windows. |
| **Grave Archer** | Medium, low/moderate durability, moderate speed, low force resistance | **Withering Arrow:** visible draw, straight non-homing physical projectile, and bounded temporary reduction of compatible outgoing damage on accepted hit. No remote curse from a missed/intercepted arrow, movement slow, ability removal or automatic player Hex Rune. |
| **Bone Reaver** | Large, high durability/resistance, slow | **Executioner's Judgment:** long telegraph, heavy physical strike with bounded additional damage against low actual current HP. Barriers/mitigation remain valid; no automatic execution. Basic heavy sweep and substantial recovery. |
| **Soul Weaver** | Medium, low/moderate durability, slow/moderate backline | **Reanimation Ritual:** one visible interruptible ritual restores an eligible ordinary fallen Hollow Legion ally at its corpse with partial HP and original capabilities. Bound resurrection per creature and per caster; no ordinary elite/boss resurrection. Control, distance, terrain or caster death can interrupt. |
| **Hexbinder** | Medium, low/moderate durability, slow, low force resistance | **Binding Grounds:** telegraph committed temporary cursed areas, slowing hostile occupants with bounded overlap and positive minimum speed. No inherent damage, complete immobilization or manual-ability disable. Leaving all applicable fields/expiry ends suppression. |

### 12.6 Hollow Legion elite roster

| Elite | Base | Added authored mechanic |
|---|---|---|
| **Deathguard** | Hollow Soldier | **Undying Advance:** faster recovery from eligible staggers/knockdowns; real displacement and lethal damage remain effective. |
| **Phantom Reaper** | Wraith | **Soul Passage:** telegraphed committed damaging spectral traversal, then materialized recovery. This is an explicit elite attack, not a change to every ordinary Wraith's attack timing. |
| **Deathmark Archer** | Grave Archer | **Deathmark Arrow:** preserve Wither and add bounded temporary incoming-damage vulnerability on successful eligible hits. |
| **Dread Executioner** | Bone Reaver | **Reaping Judgment:** preliminary broad sweep then low-HP execution strike, independently telegraphed. |
| **Grave Sovereign** | Soul Weaver | **Grave Awakening:** longer area ritual reanimates multiple eligible ordinary allies under resurrection/reward limits. |
| **Maledictor** | Hexbinder | **Compound Curse:** movement suppression plus reduced HP restoration. Neither is fully disabled by overlap alone. |

### 12.7 Enemy healing, resurrection and entitlement

Healing/repair restores missing HP/durability in the current lifecycle; it does not revive a dead enemy. Barriers are separate. Resurrection renews combat life while preserving enemy identity, faction and original progression entitlement. Clear old statuses, barriers and displacement; restore an authored partial HP amount and readable resurrection recovery. A new reinforcement is a new entity with its own explicit reward eligibility.

| Entity/lifecycle | Ordinary progression entitlement | Compatible combat kill reactions |
|---|---|---|
| Natural enemy | One original entitlement | Yes |
| Ordinary reinforcement | Yes within authored spawn/reward limits | Yes |
| Resurrected ordinary enemy | Only previously unclaimed original entitlement | Yes on each genuine eligible elimination |
| Temporary hostile summon | None by default | Only if explicitly eligible |
| Creator Primordial Manifestation | No ordinary progression reward by default | Yes |
| Player summon | None | No hostile-creature kill rewards from its destruction |
| Noncombat illusion / despawn / cleanup | None | None |

An enemy first killed solely by a faction may still have an unclaimed player progression entitlement for a later qualifying resurrected death. Do not award it twice. Repeated deaths do not increment unique-enemy mastery counters. One lifecycle has at most one elimination. Boss healing does not reset reached phase progression. Enemy-reward rules never allow a self-sustaining unlimited reward-producing summon/rez loop.

## 13. Regional bosses and blessings
<a id="gds-regional-bosses"></a>

**Basis:** V31.12-V31.15, V31.24-V31.27, V31.38-V31.41; V40.18.10; V42.2. Regional encounters are optional. Each boss embodies its faction but is not a compulsory route gate. Overhead HP bars apply, not a screen-scale final-boss display.

All three use adaptive attack preferences and HP-based escalation. Protected telegraphs, actual hit geometry and recovery remain. No forced invulnerability transition, scripted HP floor, hidden burst cap or phase-completion objective. Real burst can skip phases or defeat the boss before it performs all abilities. HP healing never reverses a reached phase. Numerical thresholds remain tuning.

### B01. The Primal Sovereign

**Identity:** Colossal antlered wolf-like apex predator, high mobility, substantial durability/force resistance; aggressive pursuit, melee and pack coordination. Territorial presence increases Wildborn aggression and encourages larger packs.

| Ability | Confirmed behavior |
|---|---|
| Crown Sweep | Wide frontal antler arc after visible preparation; flank/out-range to evade. |
| Sovereign Pounce | Commit a telegraphed landing point, leap, damage and displace compatible hostiles within actual impact. |
| Primal Slam | Traveling expanding ground shockwave, avoid its real moving edge. |
| Devouring Bite | Heavy narrow frontal bite with commitment and recovery. |
| Primal Dominion | Rally/enhance/coordinate existing nearby Wildborn; if insufficient eligible allies exist, call a limited pack through valid arrivals. |

**Phases:** Territorial Hunt (deliberate individual attacks and occasional command); Apex Dominance (combinations and stronger pack pressure); Primal Fury (aggressive pursuit/combination and shorter recovery, protected tells intact).

Close frontal targets favor sweeps/bites, distant targets favor pounce, surrounding targets favor slam, available allies favor Dominion. Preferences are not omniscient guaranteed counters or hidden resistance to the player's build. Reinforcement active capacity/total availability and rewards are bounded; genuine kills still support authored chains.

**Defeat - Primal Instinct:** End territorial enhancements, leaving existing ordinary Wildborn alive with their base abilities. Grant eligible nearby participants a run-long blessing whose genuinely qualifying evasions temporarily increase movement and compatible automatic attack frequency. No slot, automatic evasion or account-stat permanence. Close Call can coexist if both conditions qualify. Collapse escalation is unaffected.

### B02. The Eternal Architect

**Identity:** Colossal ancient construct with floating runic machinery, low/moderate mobility, high durability and very high displacement resistance. Territorial influence strengthens Runebound formations and support prevalence.

| Ability | Confirmed behavior |
|---|---|
| Grand Bombardment | Sequential explosive shots followed by distributed patterns; each landing warned. |
| Architect's Rupture | Large branching ground fissures with designated delayed eruptions and escape routes. |
| Orbital Judgment | Readably rotating damaging energy beams from floating mechanisms. |
| Grand Aegis | Temporary directional shield segments physically intercept compatible attacks; unprotected angles/compatible deliveries can bypass. |
| Grand Nexus | Real damaging links with nearby compatible constructs, altered by movement/displacement/destruction. |
| Grand Restoration | Multiple visible, individually interruptible repair links to damaged allies, bounded total output, no self-repair from this ability or resurrection. |

**Phases:** Guardian Protocol (maintain formation via deliberate bombardment/protection/repair); Dominion Protocol (combine networks, beams and area attacks based on surviving allies); Cataclysm Protocol (more aggressive overlapping attacks/shorter recovery while retaining available defenses).

Adaptive Assembly was not selected. The boss does not gain an automatic reinforcement-summoning ability merely to replace allies. Destroying allies reduces Restoration/Nexus opportunities. Full protection must not become a mandatory break-shield invulnerability gate.

**Defeat - Structural Insight:** End territorial enhancements while existing constructs retain ordinary formations, shields and repair. Grant run-long compatible physical/magical defense penetration, no slot. Fracture remains independently useful; penetration cannot ignore physical interception, barriers or explicit immunity. Valid against final boss; exact percentage is tuning.

### B03. The Eternal Reaper

**Identity:** Towering skeletal scythe entity, high mobility/durability, very high force resistance. Spectral melee, lifesteal and low-HP execution pressure. Territorial influence increases Wraith/Bone Reaver offensive pressure. The Hollow Monarch proposal was rejected.

| Ability | Confirmed behavior |
|---|---|
| Reaper's Crescent | Broad telegraphed physical scythe sweep. |
| Death's Passage | Committed damaging spectral dash, then materialized exposed recovery. |
| Soul Harvest (enemy ability) | Telegraphed magical area pulse converts bounded actual eligible hostile HP damage into self-healing; misses do not heal. |
| Final Judgment | Heavy overhead strike with bounded bonus against low actual HP, no automatic execution. |
| Spectral Severance | Magical crescent projectiles with committed real trajectories. |
| Death's Debt | Qualifying damage builds capped Soul charges; spending the threshold permits a separately telegraphed magical eruption. |

**Phases:** Soul Pursuit (establish scythe/dash/crescent rhythm); Insatiable Hunger (combine spectral/melee, harvest and earned charges); Final Reckoning (aggressive pursuit/chains/execution and shorter recovery). Phase changes never grant free Soul charges. Healing does not roll phases back. Charges and self-healing are separate; healing does not automatically generate charges. Materialized vulnerability remains sufficient for every starter build.

**Defeat - Soul Harvest (player blessing):** End territorial enhancements; existing Legion resurrection/curses remain. Grant run-long bounded damage-to-HP conversion for eligible actual owned enemy HP damage, no power slot. It can coexist with Vital Exchange. No barrier conversion, lethal prevention or healing from teammate-owned damage. Distinguish this blessing from the Reaper's same-named attack.

### 13.1 Scaling and rewards

All regional bosses participate in full catastrophic maximum-HP/damage scaling and compatible bounded speed/control-resistance escalation, global party scaling and their regional baseline. Existing absolute current HP is preserved at upgrades; real healing may fill the larger maximum. Committed attacks keep snapshots. Defeated regional bosses do not respawn because a new tier begins. Blessings remain fully available without repeat-kill penalties or mandatory boss completion. The prototype applies PR05 to V42.2 participation. [Provisional rules](#gds-rules)

## 14. Universal invaders and catastrophe Hunters
<a id="gds-hunters"></a>

**Basis:** V32; V40.5, V40.18; latest targeting revision V42.1.

The Unravelling is **one powerful self-sufficient roaming archetype**, not a fourth six-role regional roster. The discarded six-enemy invader proposal, its support roles and an automatic elite tree are not content requirements. An individual is above regional elites; two independent invaders can credibly challenge one regional boss through actual combat, not a guaranteed win or literal two-to-one stat formula. No HP bar, even at boss-like strength.

### U01. The Unravelling

Appearance: distorted/incomplete graphite, disconnected body fragments, unstable geometry. No exclusive territory, formation dependency or supporting roster.

| Ability | Confirmed behavior |
|---|---|
| Fractured Reach | Extended melee sweeps through actual disconnected fragment movement. |
| Rift Passage | Visible spatial relocation to a committed valid destination; follow-up attacks have their own tells; sealed boundaries remain. |
| Distorted Barrage | Magical projectiles change direction at visibly designated committed trajectory points, not automatic enemy homing. |
| Reality Shatter | Multiple telegraphed spatial ruptures with navigable safe gaps. |
| Spatial Implosion | Attract compatible hostiles/objects toward a committed point, then separately warn and release an explosion. Resisting pull does not itself negate damage. |

Autonomous roaming, cross-region travel, target evaluation, repositioning and temporary disengagement remain. No automatic heal/invulnerability on disengagement, no coordinated formations or shared target orders between invaders. Before Collapse, rare small encounters become more frequent/diverse encounters with this versatile archetype; the earlier group-size/ordinary-elite roster language is superseded by independently roaming population growth.

**Latest pursuit rule:** V42.1 overrides V32.3/V32.6's lack of player priority. Prioritize **detected living players**, remaining hostile to regional factions and able to fight attackers/obstructions before resuming pursuit. Without a valid player pursuit, compatible faction engagements remain possible. No omniscient locations, build-stat adaptation or automatic teleport to escaped players. Losing pursuit through terrain/mobility is possible. Dead players are not pursuit targets.

**Reward - Fractured Power:** Full authored substantial XP/common rewards and **one additional power selection** per qualifying defeat, using existing preparation, frozen queue, rank/capacity, Evolution/Fusion and overflow rules. Enemy-only defeat does not manufacture player rewards. Encounter participation and personal combat ownership remain separate.

### U02. The Erasure

World Collapse-only catastrophe-tier entity, stronger than an individual regional boss at the authored baseline. Colossal incomplete graphite with destructive spatial presence. Fully defeatable, hidden HP bar, no artificial run-ending immunity or required survival time.

| Ability | Confirmed behavior |
|---|---|
| Obliteration Sweep | Massive real multi-target limb sweep. |
| Singularity Collapse | Large gravitational pull, then separately telegraphed destructive magical explosion. |
| World Fracture | Long branching committed spatial paths with damaging propagation and safe gaps. |
| Catastrophic Arrival | Telegraph valid spatial destination and a separate arrival shockwave; cannot bypass sealed bounds. |
| Reality Storm | Successive multi-directional magical projectile waves with designated direction changes. |
| Annihilation Beam | Sustained long-range magical beam along one committed direction; repeated contact intervals, no automatic tracking after commitment. |

**Constant Catastrophe:** All six abilities available immediately, adaptive selection, no per-encounter HP phases or kill-fed empowerment. World-tier escalation still changes stats under common rules; Constant Catastrophe does not exempt it from the global clock.

The original Dominant Threat Hunter preference is superseded by V42.1's detected-player priority for both Hunter types. It may still engage powerful regional enemies as battlefield conditions permit, but must not silently ignore a detected player because an earlier version preferred a boss. Multiple Hunters act independently.

**Reward - Catastrophe Essence:** Exceptional ordinary rewards and bounded stacking run-long compatible offensive damage amplification, no power slot or permanent account damage. Every eligible fresh Hunter kill grants its full authored rewards. Reaching the Essence cap stops further amplification according to its limit, not through a repeat-kill XP/currency punishment. Erasure does **not** also grant Fractured Power's automatic extra selection by default.

### 14.1 Hunter escalation and fairness

Both use approved catastrophic HP/damage and bounded compatible speed/control resistance. Independent allowances operate within finite world population limits. During Collapse, new encounter composition shifts progressively toward Erasure; existing Unravelling are not deleted or transformed. Missed spawns do not accumulate into a flood. Valid warnings/locations, accessible gateways and no hidden player-build counter-scaling remain mandatory. Neither Hunter follows into the final arena.

Reward reductions of 15-25%, graduated repeat-kill penalties and suppression of exceptional drops were explicitly rejected. Difficulty comes from escalating enemies and hazards, not devaluing genuine success. The same resurrected enemy's single progression entitlement remains separate from newly spawned Hunter kills.

## 15. The Forgotten Creator and final victory
<a id="gds-final-boss"></a>

**Basis:** V33.1-V33.8; V39.11; V40.18.11. **Identity:** An ancient creator-like entity able to shape reality, summon faction-inspired manifestations and transform localized terrain. It is not The Origin of Collapse or The Last Calamity, which were unselected alternatives. The Creator has the highest authored baseline enemy combat strength; extreme overworld catastrophe scaling can exceed that fixed reference.

### 15.1 Continuous Adaptive Encounter

Fight one uninterrupted battle in **The Unfinished Canvas**, an open white-paper arena with incomplete graphite borders. Localized transformations, independent manifestations and attacks may overlap without mandatory secondary objectives. There is no requirement to destroy every summon, break all structures or wait through immunity before damaging the Creator.

The arena is large enough for melee, ranged, orbital, area and force-based play using ordinary movement. Outer boundaries are visible/impassable. The entire party arrives together; dead bodies remain revivable; existing builds/blessings/Catastrophe Essence remain. Pending reward selections are still available. No return to the overworld. Overworld Hunters/enemies do not enter.

### 15.2 Seven signature abilities

| Ability | Approved delivery and constraints |
|---|---|
| **Creation's Edge** | Shape enormous temporary weapons for successive physical/magical sweeps or directional strikes; each has independent preparation and real geometry. Component damage types remain authored. |
| **Genesis Rupture** | Branching committed reality fractures propagate and create delayed eruptions at designated locations; preserve safe gaps. |
| **Celestial Mechanism** | Floating runic mechanisms produce rotating beams and committed magical projectiles, with readable moving gaps. |
| **Essence Reclamation** | Telegraphed magical pulse converts bounded actual eligible hostile HP damage into self-healing; no remote drain outside geometry. |
| **Echoes of Creation** | Temporary warned attack manifestations replay selected Creator attacks from independent origins then vanish. These are attack sources, not persistent enemy summons. |
| **Reality Rewrite** | Create temporary physical structures and hazardous sections under Living Geometry rules. |
| **Genesis Cataclysm** | Extended combination of branching ruptures, rotating beams, distributed blasts and attack manifestations; each damaging component retains its own warning/timing. |

The Creator remains vulnerable during the ultimate when ordinary compatibility permits. Killing it legitimately ends the sequence; a minimum spectacle length is not required. Actual safe routes remain available despite overlapping components. Effects never delete player powers, controls or permanent progression.

### 15.3 Four Primordial Manifestations

| Manifestation | Influence | Approved role |
|---|---|---|
| **Instinct** | Wildborn | Aggressive pursuit, pounces and physical melee. |
| **Order** | Runebound | Directional protection and geometric magical attacks. |
| **Mortality** | Hollow Legion | Spectral movement, curses and execution strikes. |
| **Chaos** | Unravelling | Spatial relocation, distorted projectiles and gravitational attacks. |

Each is independently positioned, moving, target-selecting and damageable, with its own HP and combat behavior, comparable to a powerful regional elite. Hidden HP bars, visible summon warnings, bounded active count and bounded total summons apply. Destruction reduces pressure but is not a damage gate. No ordinary progression rewards by default; valid kill-trigger reactions remain eligible. Detailed manifestation attack catalogs and numeric stats remain deep content/tuning work, not copied wholesale from regional bosses without authoring.

### 15.4 Living Geometry

Temporary walls, pillars, barriers and hazardous ground have real compatible physical geometry. Players, manifestations and boss respect relevant collisions. Projectiles can be obstructed or explicitly penetrate; Force/Collision Burst/Momentum Relay and Architect structures may exploit actual surfaces. Vault may cross explicitly eligible low obstacles, not every wall.

Warn placement before materialization. Do not create unavoidable overlap through a creature, seal the only route or trap an entity permanently. Essential movement remains possible. Structures expire or disappear on encounter end; their cleanup is not an enemy kill or free natural-expiration reaction. Exact destructibility, health and interaction classifications for each Creator structure are authored details, not implied universal indestructibility.

### 15.5 The Cycle of Creation

| Phase | Tactical emphasis |
|---|---|
| **Genesis** | Weapon strikes, fundamental ruptures and projectiles establish patterns. |
| **Manifestation** | More independent manifestations and distributed attack origins. |
| **Reconstruction** | Living Geometry, rotating machinery and combination hazards. |
| **Unmaking** | Aggressive full-repertoire sequences, Cataclysm opportunities and shorter recovery. |

HP-based escalation changes tactical preferences. Self-healing cannot undo attained phases. Transitions do not refill HP, grant immunity, remove all existing summons/structures, or force a mandatory objective. Real damage may skip phases or win immediately. Protected preparation/escape rules remain in all phases.

### 15.6 Independent final-boss difficulty

No elapsed-time or catastrophic-tier multiplier applies to Creator HP, damage, speed, arena hazards or manifestation statistics. Global party-size HP/damage and selected compatible challenge modifiers still apply. No adaptive scaling to individual player builds. Staying in the Collapse can legitimately make final victory easier through earned progression. The final encounter is the alternative to endurance, not another infinitely scaling gate.

### 15.7 Victory - Legacy of Creation

Defeating the Creator completes the run immediately under the terminal causal rules; remaining summons need not die. All eligible party members, including dead players, receive their eligible victory rewards. Individual achievements/unlocks still evaluate personal requirements.

Every victory grants authored common currency, rare currency and a substantial completion bonus. First victory records its achievement and unlocks foundational challenges plus access to additional discoverable content. Unique hero, weapon, build and condition accomplishments can grant permanent rewards. There is no mandatory hidden true ending or requirement to repeat victories to make the first genuine.

Earned permanent currencies/discoveries survive defeat under the **later V40.13 economy**, while victory-only payouts require victory. Temporary powers/ranks/Evolutions/Fusions, blessings, Catastrophe Essence, bargains and Trade Shards reset at run end. Victory quantities and further reward details remain delegated or open. PR05 sets prototype disconnected-recipient eligibility. OWNER-T03 protects delivery of recoverable authorized awards across sessions. [Provisional rules](#gds-rules) · [Reward durability](#gds-durability)

## 16. Environmental objects, momentum and hazards
<a id="gds-environment"></a>

**Basis:** V34.3; V35.1-V35.6; V39.15-V39.17. The environment is selectively reactive, not fully destructible. Essential terrain, gateways, protected NPCs and critical quest/traversal structures cannot be accidentally destroyed. Destruction persists this run unless explicit restoration applies. Objects are not creatures and do not inherently grant creature-kill rewards.

### 16.1 Six functional destructible categories

| Object | Functional behavior | Compatibility considerations |
|---|---|---|
| Supply Container | Possible consumables/currency on destruction | Finite contents and single destruction. |
| Fragile Barricade | Remove an obstruction/reveal an alternate route | Essential route constraints still apply. |
| Brittle Pillar | Warn and collapse into a physical impact area | Real debris/area hit and causal attribution. |
| Volatile Crystal | Magical explosion | Genuine contact can propagate eligible environmental chains. |
| Unstable Machinery | Release stored energy / reactive hazard | Authored damage, control, warnings and trigger conditions. |
| Sealed Cache | Reveal concealed contents | Discovery condition before ordinary targeting/claim. |

Regional variants may change effects, not just skins: Wilds roots/boulders/seed pods; Expanse crystals/storage/machinery; Forgotten Lands urns/sarcophagi/bone barricades/relics. These are regional variation directions, not an extra unbounded mandatory item catalog. Individual durability and attack compatibility govern destruction by players, enemies or environmental impacts.

### 16.2 Six movable object types

| Object | Physical profile and use |
|---|---|
| Loose Crate | Light/fragile, easy displacement and destruction. |
| Stone Boulder | Heavy/durable, strong eligible physical impacts. |
| Broken Construct | Medium-heavy impact object and obstruction. |
| Burial Sarcophagus | Heavy/resistant movable obstacle. |
| Volatile Vessel | Light/fragile with collision-triggered explosion. |
| Fallen Pillar | Heavy elongated obstruction and broad impacts. |

Compatible force can move them into creatures or objects, causing real damage/displacement and further reactions. Stationary resting objects do not continuously deal impact damage. Heavy objects need sufficient force; momentum decays. Friendly/hostile/neutral eligibility and protected terrain still apply. Loose objects cannot permanently seal mandatory traversal/rescue access.

### 16.3 Controlled Physical Momentum

Slow resistance, mass, forced-displacement resistance and stability remain separate. Chill changes compatible voluntary movement, not forced velocity. Ordinary knockback is not automatically a stun or cancellation of an attack telegraph.

```text
EffectiveSlow = AppliedSlow * (1 - SlowResistance)
VoluntarySpeed = max(ApplicablePositiveMinimum, BaseSpeed * (1 - EffectiveSlow))
DeltaVelocity = DirectionalImpulse / PositiveEffectiveMass * (1 - DisplacementResistance)
ImpactStrength = 0.5 * ReducedMass * NormalRelativeApproachSpeed^2
ReducedMass = m1 * m2 / (m1 + m2)
```

The impact expression is an approved balancing relationship, not a direct HP-damage formula. Actual distance depends on deceleration, terrain, simultaneous forces and collisions. Immovable obstacles use an effectively immovable profile. Conversion thresholds and coefficients remain tuning. Opposing/combined forces act directionally; they cannot push through sealed geometry.

| Contact | Default handling |
|---|---|
| Forced enemy -> compatible enemy | Bounded momentum transfer and eligible impacts. |
| Forced enemy -> wall | Obstruction and eligible collision reactions. |
| Moving object -> enemy | Compatible physical damage and displacement. |
| Object -> object | Bounded momentum transfer. |
| Object -> wall | Obstruction and possible destruction. |
| Enemy -> destructible structure | Compatible durability damage. |
| Incompatible spectral contact | No ordinary physical collision. |
| Ordinary player -> enemy overlap | Not automatically momentum impact damage; separate contact-attack rules apply. |
| Player -> player | No hostile collision damage/forced displacement. |

Passive collisions cannot increase impact energy without an explicit new force source. Resting/minor overlap and ordinary crowd movement do not create impact damage. The same continuous contact cannot repeatedly retrigger an impact without separation and a genuine new collision. Momentum Relay is an authored additional force source; it may produce further real impacts, not artificial repeated wall contact.

### 16.4 Causal environmental ownership

Direct/indirect environmental reactions inherit the action that actually caused them. A player launching a boulder, knocking an enemy into a crystal or chaining one owned crystal explosion into another preserves eligible ownership. An Ironhide independently breaking that crystal owns its effect; a naturally erupting fissure is neutral. No player credit arises merely from watching the enemy fight.

With several contributors, assign primary impact ownership to the strongest remaining contribution in the actual impact direction after attenuation/resistance; retain eligible participation credit separately. One damage event has one primary owner by default. Secondary reaction packets retain explicit source identity and accepted triggers; an environmental blast is not automatically a weapon activation or fully rune-inherited attack.

### 16.5 Seven universally compatible hazard types

| Hazard | Mechanics |
|---|---|
| Pressure Spikes | Creature/object pressure activates a warned physical ground strike; forced movement can trigger it. |
| Flame Vent | Periodic telegraphed magical fire over a defined area. |
| Toxic Ground | Compatible periodic/DoT exposure for occupants. |
| Runic Energy Barrier | Periodic damaging magical beams between real endpoints. |
| Gravity Well | Localized pull on compatible creatures/objects, enabling real impacts. |
| Structural Collapse | Warned falling debris/physical impact zone. |
| Cursed Field | Bounded movement, offensive or restoration penalties while eligible occupants remain. |

Hazards apply by delivery, status, resistance and ownership, not automatic home-faction exemption. Regional bosses/Hunters can be affected. Natural hazards are neutral; deliberately activated effects use causal ownership and existing friendly-fire restrictions. No protected-NPC damage. Persistent hazards use intervals, not frame damage. Readable activation and escape opportunities are required. Exact pressure-plate and energy-barrier interaction variants remain authored.

### 16.6 Eight systemic mechanism types

| Mechanism | Purpose |
|---|---|
| Ancient Lever | Open gates or activate machinery through interaction. |
| Pressure Plate | Respond to compatible creature/object weight. |
| Rotating Conduit | Redirect magical energy. |
| Runic Sequence | Recognize and enter a discovered activation pattern. |
| Restoration Device | Repair/activate a designated structure. |
| Movable Keystone | Solve through physical repositioning. |
| Energy Node | Power connected mechanisms. |
| Resonance Altar | Respond to specifically compatible physical/magical interaction. |

Puzzles are interconnected and can admit several physically valid solutions: a boulder, eligible enemy or teammate may weight a plate; connected nodes can power machinery; inscriptions can explain a sequence. Enemy actions may activate mechanisms unintentionally. Observable feedback is mandatory. Puzzles operate in real time. Solo/build-independent mandatory progression is preserved; optional specialized routes can reward particular capabilities. Failed attempts do not permanently invalidate essential progress. No engine-specific circuit system or automated solver is prescribed.

## 17. Optional events, quests and encounter scope
<a id="gds-events"></a>

**Basis:** M15 sections 12 and 15; V34.4-V34.8; V36.11-V36.14; V42.2.

### 17.1 Living World Events - six archetypes

| Event | Activation | Approved activity |
|---|---|---|
| Contested Treasure | Autonomous | Rival factions converge; fight, exploit distraction or secure the discovery. |
| Ancient Trial | Player-initiated | Specialized combat conditions/enemies/hazards for optional mastery/progression. |
| Forgotten Mechanism | Player-initiated | Investigate connected mechanisms to reveal chamber, shortcut or reward. |
| Wandering Stranger | Autonomous presence/opportunity | Information, unusual request, trade or limited opportunity; consequential choices require consent. |
| Forbidden Bargain | Player-initiated | Explicit benefit in return for disclosed sacrifice/disadvantage/challenge. |
| Reality Anomaly | Autonomous | Abnormal local spatial conditions, threats or rare discovery opportunities. |

Procedural availability, concurrent events and applicable enemy interference are supported. World activity can begin/resolve without the player. Optional trials/bargains cannot be secretly forced on a player merely by an NPC appearing. Events do not pause combat. Existing events may continue through Collapse; new optional events do not start after 25:00.

### 17.2 Stakes, support events and consequences

A challenge declares objectives, success rewards, possible failure penalties and scope before acceptance. Scope can be personal, eligible local participants or explicitly party/world-wide. Do not silently penalize remote players. Example objective families include survival/defense zones, harsh environmental conditions, hunts, holds, retrieval and timed/combat mechanisms; exact authored quests are not all finalized.

Direct support opportunities are distinct: temporary protection, buffs or a temporary enhancement of the **existing main weapon**, not an independent AI gun. A support effect with no completion objective has no completion reward/failure penalty. Its expiration restores the underlying current weapon and compatible inheritance. No new support event starts during Collapse; existing effects expire normally.

Older local-event participant-count difficulty scaling must not override the later approved **global run-initialized party-size baseline**. Encounters still have authored waves, but an extra dynamic participant-count coefficient is not silently multiplied on top. The disposition of old event-specific scaling is explicitly noted in the revision/open registers.

### 17.3 Meaningful tradeoffs

Benefits, costs, duration and affected party scope must be disclosed. HP costs can be lethal under approved rules and bypass barriers; ordinary purification cannot remove voluntarily accepted drawbacks. Temporary penalties have defined end conditions; run-long ones end with the run. No permanent account penalty or removal of unlocked content. No sacrifice imposed on another player without that player's consent. Capacity, Evolution and Fusion requirements remain intact.

Rewards can include XP/currency/Trade Shards, power selections/ranks/eligible transformation opportunities, temporary enhancements, bounded run-long enhancements, rare currency, permanent discoveries and access/shortcuts. A special reward is not permission to bypass prerequisite or slot rules. Recognizable authored bargains coexist with procedurally composed compatible benefit/cost pairs under authored constraints.

### 17.4 Ten quest archetypes

| Archetype | Objective identity | Potential approved reward categories |
|---|---|---|
| Exploration | Discover locations/chambers | Currency, Trade Shards, discovery. |
| Hunting | Defeat designated threats | XP, currency, power selections. |
| Investigation | Interpret clues/inscriptions/history | Codex knowledge, permanent discoveries. |
| Restoration | Reactivate structures/machinery | Access, contextual enhancement. |
| Combat Mastery | Perform eligible mechanical accomplishments | Achievements, cosmetics, specialized unlocks. |
| Build Discovery | Acquire/understand combinations | Permanent knowledge/content discovery. |
| Faction Conflict | Influence a real regional battle | Currency, exceptional enhancement. |
| Realm Expedition | Discover/investigate optional realms | Special currency, rare knowledge. |
| Character Journey | Recurring NPC history/objectives | Permanent unlock opportunity. |
| Catastrophe Hunt | Defeat Collapse threats | Exceptional currency, mastery. |

Signature authored quests, contextual objectives grounded in genuinely available content, and persistent multi-run questlines coexist. No mandatory quest to win. All discovered/accepted eligible quests can progress simultaneously; only limited chosen objectives are pinned on the HUD. Exact pin count remains UI tuning. Achievement tracking is independent across combat/exploration/challenges and integrates major quest milestones without asking players to repeat already completed accomplishments.

### 17.5 Quest lifecycle, persistence and attribution

NPC contracts, requests and sacrifices require explicit acceptance. Environmental mystery discoveries can create journal entries organically. Track legitimate progress automatically without interrupting combat or revealing hidden target locations. Ordinary completion rewards can grant automatically; NPC return is required only where narratively/mechanically meaningful. Power-choice rewards enter the frozen nonblocking queue. Persistent eligible progress survives defeat; run-specific unfinished objectives expire at run end. Explicit retroactive eligibility can count prior actions, rather than universally counting any historical event.

Contextual attribution distinguishes shared world knowledge/accomplishments, personal mastery and individually recorded character stages. V42.2 narrows encounter-specific reward participation to nearby participating members, including late non-damaging arrivals. Individual Evolution knowledge, hero mastery and voluntary bargains cannot be granted just by proximity. Shared geography/XP remain shared across dimensions. Remote credit for a particular non-encounter persistent world objective is an open objective-level rule, not blanket permission to award every local reward to all party members.

Repeatable rewards grant once per qualifying completion. Unique account rewards cannot be reclaimed indefinitely. Discovering content and owning it remain separate unless a direct unlock is explicitly designated. Challenge-exclusive gameplay content is disallowed. Failed runs keep committed permanent rewards under the latest economy, but not unearned victory-only payouts.

## 18. Friendly NPCs, services and bargains
<a id="gds-npcs"></a>

**Basis:** V36.1-V36.10; V41.8, V41.10. Six recognizable recurring characters coexist with procedural inhabitants/encounters. The recurring principals retain identity across manifestations and can recognize meaningful previous encounters, heroes and discoveries. Not every character appears in every run. No mandatory relationship, friendship or reputation grind, and recognition does not automatically grant discounts or combat benefits.

Friendly NPCs are protected from combat damage/hostile targeting and remain interactable around enemies. They do not make the player safe. Dialogue/service panels are short, dismissible and real time, with journal updates. NPC movement respects terrain; an NPC does not relocate during active interaction. Mobile NPC map locations can become stale and cannot reveal unexplored geography by moving. Accepted quests remain valid when the issuer relocates. Existing NPC services remain accessible during Collapse.

### N01. Wandering Merchant

**Presence/identity:** Travels between temporary camps; resourceful cross-manifestation trader, witty/opportunistic but dependable, motivated by unique discoveries.

Offers finite contextual restoration, protection, temporary empowerment, additional power selections, eligible rank improvement, knowledge/discovery and exceptional offers. Inventory depends on character, region, world time and authored rarity, not guaranteed recipe targeting. Prices are disclosed before purchase and do not change while actively considering the offer. Reopening does not reroll; relocation does not reset sold-out purchases. Selected ordinary services may restock through explicit bounded world activity/relocation conditions, not automatically infinitely. Power and rare/exceptional offers remain finite.

| Offer | Party availability |
|---|---|
| HP/resource restoration | Shared ordinary stock. |
| Temporary barrier | Shared ordinary stock. |
| Ordinary temporary enhancement | Shared ordinary stock. |
| Additional power selection | Individual purchase limit. |
| Power rank upgrade | Individual purchase limit. |
| Exceptional build enhancement | Individual eligibility/limit. |
| Permanent discovery | Individual eligibility. |

Each player pays their own **Trade Shards**. Invalid/no-benefit purchases consume neither wallet nor stock. Shared simultaneous purchase cannot duplicate inventory. Personal limits survive reopening and relocation for the run. Purchased power choices use the same frozen queue. No mandatory purchase, extra item inventory, pause or invulnerability. Exact stock reservation behavior while another player buys is an open UI/transaction detail, not permission to change already disclosed paid rewards.

### N02. Archivist

**Presence/identity:** Investigates ruins/inscriptions; patient, meticulous scholar preserving civilization's knowledge across Collapse.

| Service | Function |
|---|---|
| Power Research | Clues concerning undiscovered powers. |
| Evolution Research | Hints about catalysts and combinations. |
| Rune Research | Rune interaction knowledge. |
| Ancient History | Faction/world history and interpretations. |
| Location Research | Hidden locations and special realms. |
| Artifact Identification | Understand unusual found objects. |
| Lost Knowledge | Rare permanent discoveries. |

Use Progressive Knowledge Discovery through clues, research, experimentation and actual acquisitions. Ordinary knowledge may be direct; significant secrets are layered. Codex knowledge persists; exact procedural coordinates belong to the current run. Knowledge does not grant ownership when purchase/unlock prerequisites remain. Ordinary clues can be shared, while personal/secret revelation eligibility remains explicit. Standard Evolution verification and Fusion's separate knowledge stages must not be conflated.

### N03. Artisan

**Presence/identity:** Operates from workshops; inventive, eccentric and demanding craftsperson seeking forms the Creator never imagined.

| Service | Function |
|---|---|
| Reinforcement | Bounded weapon damage improvement. |
| Refinement | Improve compatible existing attack properties. |
| Attunement | Add a temporary compatible effect. |
| Reshaping | Modify actual weapon geometry. |
| Transformation | Temporary alternative attack behavior. |
| Masterwork | Rare specialized run-long enhancement. |

Trade Shards or explicitly disclosed alternative costs apply. Ordinary enhancements may be run-long; transformations are temporary, one active at a time, with duration/tradeoffs disclosed. Preserve compatible runes, powers, positive/negative inherited properties and underlying progression. Expiration restores the current original weapon state. No acquired-power slot, prerequisite bypass or permanent account mutation. Greatblade/Volley/Constellation were illustrative proposals, not finalized individual forms. Their detailed authoring is deferred.

### N04. Pathfinder

**Presence/identity:** Travels/explores regional paths; practical, observant adventurer investigating whether creation has a boundary.

| Service | Function |
|---|---|
| Regional Knowledge | Describe environments. |
| Landmark Clues | Suggest significant places. |
| Hidden Passages | Give shortcut clues. |
| Danger Reports | Report known threats, not live omniscient tracking. |
| Realm Research | Hint at special-realm entrances. |
| Exploration Requests | Optional discovery objectives. |
| Cartography | Approximate geography/search areas. |

Contextual Cartography combines environmental dialogue/journal clues and approximate marked search areas after learning the clue. Fog remains. Exact secret entrance discovery still requires physical exploration. Applicable knowledge is shared; procedural-location specifics reset next run, durable knowledge persists. No general fast travel, automatically completed objective or solved gateway route.

### N05. Restorer

**Presence/identity:** At shrines/temporary sanctuaries; compassionate, composed and resolute, repairing existing imperfect lives without erasing identity.

| Service | Effect |
|---|---|
| Vital Restoration | Restore current HP up to maximum. |
| Energy Restoration | Restore compatible combat resources. |
| Guardian's Protection | Temporary personal barrier. |
| Purification | Remove explicitly removable harmful statuses. |
| Renewed Spirit | Reduce explicitly compatible remaining cooldowns. |
| Recovery Blessing | Temporary received-healing amplification. |
| Sanctuary Blessing | Temporary mitigation enhancement. |

Services are limited and can require shards, objectives or disclosed sacrifices. No direct resurrection of dead teammates, ordinary purification of accepted covenant drawbacks/challenge conditions, automatic immunity or safe farming zone. Bounded blessing stacking and resource capacity apply. Stock is spent only on a valid benefit. Existing service access persists in Collapse.

### N06. Nameless Stranger

**Presence/identity:** Rare unusual locations/realms, enigmatic/calculating/unpredictable. Canonical hidden identity: **The Discarded Creation**, an early being that survived incomplete erasure, learned contradictions between manifestations and enables Unwritten defiance. Knowledge is vast but not unlimited; benevolence/malice and final motives remain nuanced. It does not defeat the Creator for the player or introduce undisclosed betrayal penalties.

| Signature bargain archetype | Benefit | Disclosed cost/challenge category |
|---|---|---|
| Blood Offering | Additional power selection | Current HP sacrifice. |
| Glass Covenant | Offensive amplification | Reduced maximum HP. |
| Burden of Strength | Increased damage | Reduced movement speed. |
| Forbidden Knowledge | Rare permanent discovery | Dangerous encounter. |
| Borrowed Time | Compatible attack-frequency enhancement | Longer manual ability cooldown. |
| Unstable Ascension | Eligible Evolution opportunity | Increased damage received. |
| Fractured Passage | Special-realm access | Dangerous environmental challenge. |
| Creator's Mark | Exceptional run-long enhancement | Additional hostile encounters. |

Recognizable covenants coexist with procedurally combined compatible benefits/costs. Exact percentages in examples were not final values. Multiple distinct pacts may coexist within authored bounds. State costs, duration and risks before acceptance. Do not consume teammates' HP/resources without consent, remove permanent unlocks, bypass capacity/recipe requirements or cleanse voluntary costs through ordinary purification. New enemies still obey safe spawn warnings. Temporary/run-long effects reset after the run.

## 19. Pickups, restoration and resource availability
<a id="gds-pickups"></a>

**Basis:** V35.7-V35.10; V36 economy; V39 recovery.

### 19.1 Eight pickup types

| Pickup | Effect | Recipient | Persistence / interaction |
|---|---|---|---|
| Vitality Fragment | HP recovery | Collector | Limited lifetime; immediate eligible collection. |
| Energy Fragment | Compatible resource recovery | Collector | Limited lifetime; no collection without compatible benefit. |
| Barrier Fragment | Temporary barrier | Collector | Limited lifetime; bounded same-source accumulation. |
| Haste Fragment | Temporary movement bonus | Collector | Limited lifetime. |
| Fury Fragment | Temporary offensive enhancement | Collector | Limited lifetime. |
| Experience Fragment | XP | Eligible shared party progression | Until collected/run ends. |
| Currency Fragment | Common currency | Eligible party members | Until collected/run ends. |
| Ancient Essence | Rare contextual enhancement | Individually eligible recipient | Until claimed/run ends; exceptional claim requires deliberate interaction. |

Ordinary pickups have limited attraction to eligible nearby players, with compatible collection-range modifiers. They cannot pass sealed walls or cross dimensions. Attraction does not consume a resource with no valid benefit. Pure HP pickups are not automatically consumed at full HP. Expiring pickups communicate expiry visibly. No consumable bag, stored potion inventory or extra consumable hotkeys.

Simultaneous collection cannot duplicate a limited drop. Personal combat enhancements do not automatically transfer to teammates. Dead teammates may retain shared progression but do not revive from ordinary pickups. A committed permanent reward cannot expire later because its visual pickup disappeared.

### 19.2 Four stationary resources

| Object | Effect | Capacity model |
|---|---|---|
| Restoration Fountain | HP restoration through deliberate interaction | Limited shared available restoration. |
| Guardian Shrine | Temporary barrier, no inherent HP restoration | Limited shared uses/capacity. |
| Resonance Shrine | Compatible resources or eligible cooldown recovery | Limited shared uses/capacity. |
| Empowerment Altar | Temporary contextual combat benefit | Limited shared uses/capacity. |

Each benefits the interacting eligible player and spends stock only when a valid benefit occurs. Do not automatically consume on walk-by. Locations can be left unused and revisited; discovered objects may be marked on the explored map. Exact capacity values/interaction time remain tuning.

### 19.3 Dynamic resources with finite landmarks

Containers/caches are finite and non-respawning. Fountains/shrines/altars do not automatically refill. Backtracking, reopening a panel or another player arrival does not reset them. Explicit restoration mechanisms can replenish designated resources when authored.

New qualifying kills and valid world activity may generate bounded resources without duplicating old entitlements. Combat drops continue during Collapse even though new optional events do not start. No elapsed-time free recovery or permanent safe farm location is created. Extended survival is possible through a strong build and genuine accomplishments, not guaranteed by resource regeneration.

## 20. Permanent progression, currencies and discovery
<a id="gds-progression"></a>

**Basis:** M15 preparation/discovery rules where not superseded; V33.8; V36; V37.9, V37.17, V37.22, V37.30; V40.3-V40.17; V42.

<a id="gds-durability"></a>

### 20.1 Three currency roles

| Currency | Purpose | End-of-run treatment |
|---|---|---|
| Common currency | Permanent unlocks and bounded upgrades | Earned amounts retained on victory or defeat. |
| Rare/special currency | Valuable permanent progression | Earned permanent amounts retained on victory or defeat under V40.13. |
| Trade Shards | In-run merchant/services economy | Start at zero, separate personal wallets; unspent shards expire at run end. |

The older M15 blanket rule that exploration special currency is unsecured until victory is **superseded by the later approved V40.13 permanent-currency retention rules**. Victory-only payouts are still unearned until victory; retaining earned currency does not award a lost run the Creator's completion bonus. No automatically assumed fourth banked/unsecured currency is added.

**Reward durability (OWNER-T03).** Record important permanent progression immediately, including eligible discoveries, personal recipe verification, purchases and victory entitlements. Ordinary enemy currency may accumulate briefly. The current **provisional maximum is five seconds** from the oldest pending earning during active play. Ordinary defeat and graceful completion settle all eligible earnings. An abrupt crash can lose ordinary earnings still awaiting durable commitment. For an outstanding authorized grant, reconcile the original issuer's record with the recipient's durable receipt after reconnect or in a later session. Redelivery applies each grant at most once. If all authoritative evidence needed for an award has been lost, disclose what cannot be recovered, including any unknown amount. [Persistence contract](TDS.md#tds-save)

Trade Shards arise from eligible enemy defeats, exploration and events. Eligible shared rewards credit individual wallets; one player cannot involuntarily spend another's. No conversion into permanent currencies. Permanent currencies do not directly buy extra power selections during an active run. Services may offer discovery opportunities without constituting shard-to-permanent-currency exchange.

### 20.2 Achievement-based economy with victory bonus

Reward genuine accomplishments, not survival time alone. Ordinary enemies offer low common rewards; elites moderate/possible rare; regional bosses high/rare; Unravelling high/possible rare; Erasure exceptional/rare; exploration, quests and discoveries contextual; optional realm objectives valuable; Creator victory and completion payout exceptional/substantial. Exact amounts/probabilities are delegated tuning.

No repeated-Hunter XP/currency penalty, no elapsed-time reward multiplier, no automatic time-based currency generation. A highly accomplished failed endurance run may legitimately earn more retained currency than a brief victory. The successful equivalent additionally receives its victory reward. One-time discoveries/achievements cannot be farmed as repeatable payouts. Fresh spawned enemies differ from repeated resurrection of the same entitlement.

### 20.3 Discovery then ownership

Heroes, weapons, expanded runes and the six expanded acquired powers follow approved discovery accomplishments followed by permanent-currency purchase, with explicitly designated direct-unlock exceptions. Discovery and partial persistent quest progress survive defeat where eligible. Ownership is permanent; actual run acquisition/ranks reset. No circular unlock dependency or mandatory challenge-exclusive gameplay item. Recipes, powers and currencies do not unlock merely because a teammate knows them.

| Content | Discovery condition |
|---|---|
| Chronomancer | Temporal knowledge in Inverted Archive. |
| Gravity Weaver | Genuine displacement and chained collision mastery. |
| Summoner | Sketch Familiar/companion mastery. |
| Bloodbound | Fulfilled qualifying HP-sacrifice covenant. |
| Alchemist | Status interactions plus related mastery. |
| Architect | Foundry construction-mechanism restoration. |
| Spear | Piercing Mastery through prior eligible attacks. |
| Warhammer | Crushing Force using environmental impacts. |
| Twin Daggers | Relentless Rhythm high-frequency qualifying hits. |
| Chakram | Returning-blade blueprint plus Artisan research. |
| Chain Whip | Converging Force through inward displacement. |
| Arcane Focus | Focused Energy Observatory mechanism. |
| Flame | Heart of the Furnace. |
| Frost | Trial of Stillness. |
| Ricochet Shard | Geometry of Impact. |
| Arcane Tether | Forgotten Connections. |
| Spatial Reach | Beyond the Boundary. |
| Lingering Essence | Enduring Influence. |
| Momentum Charge | Unbroken Motion. |
| Converging Strikes | Unified Offensive. |

The first twelve power designs are the initial catalog, but not all were explicitly granted to every new profile immediately: V30.1 described early availability plus discoveries across runs. PR02 makes their prototype availability explicit while preserving the distinct unlock conditions for P13–P18. [Provisional rules](#gds-rules)

### 20.4 Permanent statistical upgrades

Meaningful but bounded account advantages, with **15-25% per supported statistic** as an illustrative initial range, not a universal mandated cap of exactly 25%. Supported branches: maximum HP, base damage, physical defense, magical defense, movement, automatic attack frequency and manual cooldown recovery. They do not increase rune slots, acquired-power slots or maximum power rank, bypass recipe requirements or alter Hunter reward entitlement.

Each branch has finite ranks, progressively higher fixed prices and consistent incremental benefit within that branch. Earlier ranks use common currency; selected later ranks may use rare currency. Specific rank counts/price tables are tuning. Previous ranks prerequisite later ones, but independent branches have no mandatory global order. No automatic respec/refund or wealth-based dynamic pricing. Upgrades persist, apply consistently across heroes and never cause enemies to scale against the account.

### 20.5 Achievements and mastery

Track combat, exploration and challenges independently while recognizing major quest milestones. Unique accomplishments are one-time achievements; selected gameplay categories use multi-tier meaningful mastery tracks. Visible ordinary achievements/masteries coexist with secrets hidden or vaguely hinted until discovered/completed. Previously completed applicable accomplishments should not need repetition merely because another tracking surface became available, subject to explicit eligibility.

Personal mastery remains distinct from shared encounter rewards. No gameplay advantage is awarded merely for a personal performance record. Exact achievement names, thresholds, cosmetics and full challenge catalog remain deferred authoring.

## 21. XP, progression pacing and overflow
<a id="gds-xp"></a>

**Basis:** V40.1-V40.9, V40.11-V40.17; earlier frozen reward rules.

### 21.1 Normal Mode expectations

Ordinary coherent builds can defeat the Creator without permanent upgrades, maximum ranks, every region or mandatory Fusion. Exceptional synergies may trivialize bosses; this is legitimate power, not automatically a defect. Weak/incoherent builds can fail. Collapse is optional endurance for sufficiently powerful builds and capable players, not a promise that farming eventually rescues everyone.

The selected victory-ready expectation is synergy-focused, between the original A/B completion proposals: either **one Advanced Fusion made from its two required Evolutions**, or roughly **3-4 standard Evolutions**. Remaining powers may be Rank 1, 2, 3, 4 or 5; all ten slots and max ranks are not compulsory. This is a Normal Mode balance target around the 25-minute stage, **not an entrance requirement or a forced minimum for winning**. A Fusion's two ingredients are not two additional separate Evolutions required on top of it.

### 21.2 Hybrid progressive-exponential XP requirements

Early levels use progressive polynomial growth; advanced levels transition into exponential requirements based on **player level**, not the clock or Collapse activation. There is no fixed level cap. The transition level and coefficients were deliberately not approved numerically.

A continuous mathematical representation of the approved shape is DERIVED, not an additional tuned rule:

```text
P(L) = B + k * (L - 1)^p, with p > 1
XP_to_next(L) = P(L)                    for L <= L_transition
XP_to_next(L) = P(L_transition) * r^(L - L_transition) for L > L_transition, r > 1
```

The actual coefficients are delegated balancing. No extra penalty is triggered merely because world time passes 25:00. Higher authored enemies and exceptional encounters provide more XP; values are not calibrated to the individual player's current build. Shared levels, excess-XP carry, multiple earned choices and frozen queues remain. No XP reset across regions/realms/Collapse.

The WP19 prototype implementation uses provisional coefficients under OWNER-T04 and D1. They are recorded with the posting and transition witnesses and await owner playtesting. [WP19 tuning record](records/WP19.md#preparation-shared-experience-and-ordinary-offers-checkpoint)

### 21.3 Bounded overflow

When no eligible ordinary acquisition/rank progression remains, reward selections may provide minor run-long statistical improvements plus utility. Improvements diminish and have independent investment caps; examples include damage, maximum HP, defense and compatible frequency. No exact +15% aggregate or upgrade count from examples is locked.

XP-earned and exceptional additional selections share the same limits. Overflow takes no slots, resets each run, cannot reset its own limits or introduce a new transformation tier. Eligible Evolution/Fusion opportunities still operate. Eventually only utility remains, while levels can continue. Utility may include applicable recovery, temporary protection/enhancement and permitted currency compensation; exact pool is delegated/open. Extended survival does not guarantee unlimited lasting power.

### 21.4 Fair randomness and no hidden recipe steering

Contextual reward distribution considers open capacity and existing rank opportunities rather than forcing a new power at every reward or flooding a full build with invalid acquisitions. It does not boost the probability of a tracked desired recipe, guarantee a particular build, reroll pending choices or auto-select an Evolution. Explicit prepared-pool offer opportunities and wildcard boundaries remain. PR03 supplies provisional size, card budget and rotation. Unassigned weights remain delegated tuning. [Provisional rules](#gds-rules)

## 22. Challenges, records and balance validation
<a id="gds-challenges"></a>

**Basis:** V40.14-V40.17; V42.6 revision.

### 22.1 Challenge configuration

Normal Mode is the balance reference. Optional pre-run modifiers may address enemy strength, density, Hunter pressure, healing, attack complexity, XP progression, environmental danger or catastrophe escalation. These are approved design categories, not eight fully authored mandatory modifier names/effects. Combine compatible unlocked modifiers; disallow incompatible combinations. Party configuration is shared and cannot change mid-run.

Each modifier has authored difficulty/reward weight. Specifically demanding combinations may add bounded bonuses under an overall currency-reward limit. No default XP bonus. Increased difficulty does not automatically raise per-enemy authored XP; added eligible enemies retain normal rewards. No reward decay for replaying a challenge. No adaptive challenge adjustment to individual player skill/build.

First victory unlocks foundational challenges. Relevant accomplishments reveal specialized challenges without a sequential ladder; qualifying earlier accomplishments are remembered. Unlocks persist after defeat where eligible. No currency cost to enable, no challenge-only heroes/weapons/runes/powers/stat upgrades. Challenge-only recognition may be achievements, records or cosmetics. Cooperative shared-unlock access does not automatically grant permanent ownership to guests; exact selection/access rules beyond that principle are open where the source is incomplete.

### 22.2 Contextual Mastery Records

Record valid accomplishments across heroes, weapons, party sizes and challenge configurations. Preserve final record-setting builds with hero/weapon/runes/powers/ranks/Evolutions/Fusions/applicable upgrades. Normal/challenge and solo/co-op records are distinguishable. Individual survival and party survival are separate; final-arena duration is separate from Collapse endurance.

Record categories approved: victories/fastest completion; longest survival/Collapse endurance; highest individual hit, total damage and elimination chains; Unravelling/Erasure eliminations; highest level/Evolutions/Fusions; exploration/bosses/realms/discoveries; hero/weapon mastery; co-op victories/revivals; challenge configurations. These are passive records, not a mandatory full analytics post-run UI. No online competitive leaderboard is required, and records grant no extra combat advantage. Exact retention/record validation is open.

### 22.3 Viability-first acceptance

Correct defects first, improve ineffective alternatives, improve encounters/behavior, adjust progression, then tune specific numbers/interactions as needed. Legitimate high damage, fast boss kills, large chains and strong sustain are not automatically bugs. Infinite unintended loops, duplicate entitlements, false contact, unavoidable authored attacks, unviable core choices and a dominant choice invalidating meaningful alternatives are problems.

Fresh accounts, starter content and no-permanent-upgrade play must have viable Normal Mode victory paths. Fusions are optional. Global co-op scaling should preserve meaningful teamwork without erasing legitimate cooperation advantages. Completed builds need not sustain arbitrary future catastrophic tiers. A full-content prototype is evaluated for correct/viable interaction and repeatable play, not exact parity between every build.

## 23. World difficulty, regional and cooperative scaling
<a id="gds-scaling"></a>

**Basis:** V40.5, V40.10, V40.18.1-V40.18.16. All selected percentages are initial **Normal Mode balance targets**, not validated survival predictions. Difficulty depends on world time, enemy archetype, assigned region, initialized party size and selected challenge rules, never player level, account wealth, damage output, movement speed or detected build strength.

### 23.1 Pre-Collapse growth

Before 25:00, use accelerating progressive growth. The initial quadratic model targets **3x maximum HP and 2x damage immediately before Collapse**, relative to the same unmodified archetype at time zero:

```text
H_pre(t) = 1 + 2 * (t / 25)^2
A_pre(t) = 1 +     (t / 25)^2       for 0 <= t < 25 minutes
```

The exponent/coefficients remain tuning parameters consistent with the approved endpoints. Early pressure is modest, midgame encourages specialization and late pre-Collapse allows meaningful transformation opportunities. No specific Evolution, level or event is a time-gated requirement. Continuous pre-Collapse growth stops at 25:00; it is not multiplied by a still-growing polynomial afterward.

### 23.2 Catastrophic tiers

Tier 0 is the ordinary world before Collapse. Tier 1 begins **at 25:00**, followed by another tier every **2 minutes**:

```text
n(t) = 0                                      for t < 25
n(t) = 1 + floor((t - 25) / 2)                 for t >= 25
H_catastrophe(n) = 1.40^n
A_catastrophe(n) = 1.25^n
```

These latter multipliers use the **immediately pre-Collapse reference**. To compare to time-zero archetype stats, use `3 * 1.40^n` maximum HP and `2 * 1.25^n` damage. There is no maximum tier, HP multiplier or damage multiplier. Expanding control/speed/population does not share that unbounded model.

The tier is synchronized across regions/realms/party and never resets through travel, Hunter death or respawn. A brief non-blocking visual/audio notice accompanies escalation. Current tier and next escalation time are visible contextually in the HUD. No mandatory retreat, automatic death or shrinking world boundary.

### 23.3 Existing-enemy updates

Every eligible existing enemy receives updated maximum HP and offensive statistics, **without raising its absolute current HP**. New enemies spawn at current-tier full HP. Existing barrier capacity is not refilled. Previously committed attacks retain their snapshots; an already warned projectile cannot suddenly gain the new tier's damage after launch. Cooldowns/telegraphs/statuses remain; escalation is neither healing nor resurrection.

Actual enemy healing can recover toward the enlarged maximum. Changing maximum HP may alter HP-percentage-dependent conditions; exact phase/threshold reevaluation on world-tier changes is flagged for deep detail rather than an invented hidden phase reset. Approved reached boss phases never roll back.

This rule means the table's HP multipliers are **maximum capacity/new-spawn HP**, not a claim that every long-lived enemy has that much remaining health.

### 23.4 Bounded pressure alongside exponential strength

| Property | Approved progression |
|---|---|
| Enemy maximum HP | +40% each catastrophic tier, unbounded compounded target. |
| Enemy damage | +25% each tier, unbounded compounded target. |
| Ordinary population capacity | Progressive, finite separate limit. |
| Reinforcement frequency | Progressive, finite separate limit. |
| Hunter mix | Increasing Erasure dominance in future arrivals. |
| Hunter active allowance | Independently governed, finite within world limits. |
| Movement speed | Bounded, archetype-specific escalation. |
| Attack frequency | Bounded, archetype-specific escalation. |
| Physical/magical defense | Not raised by catastrophe. |
| Mass | Not raised by catastrophe. |
| Slow/displacement resistance and eligible stability | Selective bounded archetype-specific increases. |
| New immunity | Not automatically granted by tiers. |
| XP, currency and exceptional Hunter rewards | Full authored rewards; no repeat-kill penalty. |

Population Saturation increases capacity and reinforcement rate progressively. When the relevant limit is reached, additional ordinary spawns wait; do not delete living enemies to make room or bank missed opportunities into a later flood. All new spawns need valid warned locations; no unannounced spawn on top of a player. Saturation never stops HP/damage escalation. Exact regional/global allowances and spawn pacing are delegated tuning.

Hunter Dominance changes **new** composition toward Erasure, not transformation/deletion of surviving Unravelling. Independent types keep full rewards and permitted faction combat. Player-priority pursuit follows V42.1, not earlier target-independent behavior.

Movement/attack speed limits preserve archetype identity and minimum reaction windows. Frequency growth primarily reduces recovery intervals, not committed warning duration. Existing attack tells keep committed timing; projectile velocity, accuracy and homing do not automatically scale. The earlier +30% movement/+50% frequency figures were illustrative limits, not newly locked universal caps.

Control resistance cannot completely invalidate previously compatible control through scaling alone. Mass remains authored even when HP becomes enormous. Fracture/Structural Insight retain their effects. Damage and displacement eligibility remain separate; explicitly authored immunities are not silently removed or added.

### 23.5 Regional and global party multipliers

| Assigned region | HP | Damage |
|---|---:|---:|
| Primeval Wilds | 1.00 | 1.00 |
| Runic Expanse | 1.25 | 1.15 |
| Forgotten Lands | 1.50 | 1.30 |

Enemies retain their assigned regional coefficient when they cross boundaries. Universal Hunters have independent authored baselines rather than changing strength every time they enter a region. Optional realms use independently authored baselines. No required regional order or entry level.

For initialized party size `N`:

```text
H_party(N) = 1 + 0.50 * (N - 1)
A_party(N) = 1 + 0.10 * (N - 1)
Population_party(N) = 1 + 0.25 * (N - 1)
ReinforcementFrequency_party(N) = 1 + 0.25 * (N - 1)
```

| Players | HP | Damage | Population allowance | Reinforcement frequency |
|---|---:|---:|---:|---:|
| 1 | 1.00x | 1.00x | 1.00x | 1.00x |
| 2 | 1.50x | 1.10x | 1.25x | 1.25x |
| 3 | 2.00x | 1.20x | 1.50x | 1.50x |
| 4 | 2.50x | 1.30x | 1.75x | 1.75x |

These grow linearly per additional player, not compounded per player. Lock N at run initialization. Death, temporary disconnect and exploration separation do not reduce it. The four-player row is not a newly imposed maximum party size. Population/frequency still respect finite world/source limits; increased frequency is not the same as subtracting the percentage from a spawn interval.

Ordinary enemies, elites, Hunters and regional bosses use applicable party scaling. No automatic party increase to defense, mass, movement speed or control resistance. Hunter frequency and boss reinforcement allowances require authored tuning separate from merely multiplying every entity count. Shared XP and full rewards remain.

### 23.6 Combined stat calculation and exceptions

For an eligible overworld archetype:

```text
MaximumHP = ArchetypeBaseHP * AssignedRegionHP * PartyHP * ApplicableTimeHP * ChallengeHP
AttackDamageAtActivation = ArchetypeBaseDamage * AssignedRegionDamage
                           * PartyDamage * ApplicableTimeDamage * ChallengeDamage
```

Not every actor has an assigned regional multiplier; universal Hunters use their own baseline. Enemy defenses/target vulnerability still resolve normally after these offensive values. Additional explicitly authored modifiers remain distinct. Existing current HP preservation and offensive snapshot rules apply.

Regional bosses use full catastrophic rules; no free replacement HP or respawn. Forgotten Creator, its manifestations and final-arena hazards use independently authored encounter values with applicable party/challenge scaling **and no elapsed-time/catastrophic/region coefficient**. World time may continue for records, but cannot secretly make that arena harder.

### 23.7 Environmental escalation

Naturally occurring compatible damaging Collapse hazards use `HazardBaseDamage * 1.25^n`. Occurrence, simultaneous coverage, lifetime, gravity and movement impairment increase only within separate limits. Keep protected telegraphs and actual routes. Neutral hazards can affect enemies as well as players subject to compatibility/resistance, but do not award invented player ownership.

Player-owned attacks and displaced objects keep their own impact/damage calculations; they do not automatically gain the world's exponential hazard multiplier. Exact treatment when a neutral scaled device becomes deliberately activated/player-owned is listed as open. The final arena remains excluded. Overlap cannot multiply one hazard's damage merely because several visual layers intersect.

### 23.8 Calculated reference table

The following table is mechanically derived from the approved formulas. It separates catastrophic reference multipliers from total time-zero multipliers. Values are not claims about practical survival difficulty.

| World time | Tier | Catastrophic HP factor | Catastrophic damage factor | Total time HP factor | Total time damage factor |
|---|---:|---:|---:|---:|---:|
| 00:00 | 0 | 1.00x | 1.00x | 1.00x | 1.00x |
| 05:00 | 0 | 1.00x | 1.00x | 1.08x | 1.04x |
| 10:00 | 0 | 1.00x | 1.00x | 1.32x | 1.16x |
| 15:00 | 0 | 1.00x | 1.00x | 1.72x | 1.36x |
| 20:00 | 0 | 1.00x | 1.00x | 2.28x | 1.64x |
| 25:00 minus | 0 | 1.00x | 1.00x | 3.00x | 2.00x |
| 25:00 | 1 | 1.40x | 1.25x | 4.20x | 2.50x |
| 27:00 | 2 | 1.96x | 1.56x | 5.88x | 3.12x |
| 29:00 | 3 | 2.74x | 1.95x | 8.23x | 3.91x |
| 30:00 | 3 | 2.74x | 1.95x | 8.23x | 3.91x |
| 35:00 | 6 | 7.53x | 3.81x | 22.59x | 7.63x |
| 40:00 | 8 | 14.76x | 5.96x | 44.27x | 11.92x |
| 45:00 | 11 | 40.50x | 11.64x | 121.49x | 23.28x |
| 50:00 | 13 | 79.37x | 18.19x | 238.11x | 36.38x |
| 60:00 | 18 | 426.88x | 55.51x | 1,280.64x | 111.02x |

`25:00 minus` is the limiting reference immediately before Tier 1. Total time factors exclude regional, party, challenge and archetype modifiers. Rounding is for display only. These are maximum-HP/new-spawn references, not automatic restoration of existing current HP.

## 24. Visual direction, audio, HUD and accessibility
<a id="gds-presentation"></a>

**Basis:** M15 presentation; V21-V24; V40.18.3; V41.6; V42.5-V42.6. Presentation must make the simulation legible, not change it. Placeholder assets are acceptable for the prototype when they communicate the correct geometry and states.

### 24.1 Art and animation

Top-down/oblique 2.5D-feeling sprites use a coherent handmade graphite/pencil-on-white-paper identity. Keep the world predominantly monochrome, with restrained colored-pencil/watercolor accents for magic and elemental identity. Animation is expressive and fluid without sacrificing immediate movement responsiveness. Do not replace physical melee with sword-shaped ranged projectiles to simplify assets.

Attack impact uses adjustable restrained camera shake and automatic moderation of repeated effects. Large attacks/chain reactions may feel spectacular while cosmetic particles are reduced or grouped. Personal and teammate effects have separate customization. Maintain attack identities and enemy tells; do not secretly reduce damage, source counts or valid reactions when reducing visual clutter.

Use adaptive transparency, player silhouettes and building cutaways to preserve visibility without revealing concealed enemies/secrets. Preserve natural enemy overlap; a minimal player-position marker helps when obscured rather than forcing artificial enemy separation. Temporary physical obstacles and terrain must visibly match applicable collision; purely scenic fading does not invent passable terrain.

### 24.2 Audio

Adaptive music responds to exploration, combat, bosses and Collapse. The music direction is handcrafted fantasy: intimate acoustic exploration develops into epic layered combat/boss themes. Layered recognizable weapon/rune/elemental reaction sounds use adaptive mixing to keep large chains intelligible. Prioritize meaningful attack/danger cues over every repeated event.

Directional audio and prioritized nearby threat cues must not automatically reveal hidden enemies or create permanent HUD markers. Dialogue is primarily text with nonverbal character/creature sounds and minimal voice acting. Separate audio categories, optional subtitles/sound captions and reduced combat intensity are supported. Captions must not disclose hidden information unavailable through the underlying cue.

### 24.3 Contextual and customizable HUD

Essential combat information remains readable; secondary detail is contextual/customizable. Support scale, placement/layout presets, opacity and visibility where appropriate. Default layout and exact typography are open. Keyboard/mouse remapping, mouse-only/minimal-keyboard and keyboard-plus-mouse arrangements remain.

| Information | Required presentation behavior |
|---|---|
| HP / personal barriers | Persistent clear combat state. |
| Relevant combat resources | Visible when applicable, with critical low-resource state. |
| Manual hero ability | Persistent readiness/cooldown. |
| Critical statuses / danger | High priority, not buried among routine buffs. |
| Run time / level | Persistent compact readout. |
| XP | Compact progress indication. |
| Acquired powers / ranks | Compact build bar; deeper inspection on demand. |
| Minimap / expanded world map | Customizable, respects discovered geography and secrets. |
| Gateway | Compass/direction and approved reveal, no solved route. |
| Party | Compact adaptive health/essential states; prominent death/revive/disconnect alerts. |
| Quests | Limited user-pinned objectives, all eligible quests still progress. |
| Pending rewards | Nonblocking visible queue indicator, manually opened. |
| Catastrophic tier | During Collapse, show current tier/next escalation and brief notification. |
| Boss HP | Regional overhead; final screen-wide only. |
| Detailed build/stats | Expandable real-time panel, no pause. |
| Status stacks/cooldowns | Adaptive priority grouping, optional detailed analysis. |

No ordinary, elite, Unravelling or Erasure health bars, even when a creature equals/exceeds boss strength. Automatic targeting uses subtle temporary feedback rather than constant clutter; environmental targeting has distinct indications. E-key/default interaction prompts appear near recognizable interactables, not hidden secrets.

The build inspection panel exposes equipment, powers, stats, resource costs and **known** interactions. It must not reveal an unknown recipe simply because hidden compatibility is detectable. Passive recipe inspection is included; the fuller informational Build Tracker, reward recipe indicators and compatibility-warning planner are deferred.

### 24.4 Visual priority in dense combat

Prioritize: dangerous enemy telegraphs; player position/critical HP; environmental hazards; teammate death/revival; enemy silhouettes/movement; personal attack effects; teammate effects; decorative particles/damage numbers. Threats can remain deadly, but they cannot be concealed by gratuitous display noise. Damage numbers and nonessential effects may be hidden; critical warnings do not rely on color alone. Screen shake and flashing are adjustable.

Announcements remain minimal and critical: brief Collapse/tier changes and gateway information, not a scrolling feed of every proc. Frequent combat activations are grouped; optional detailed data supports analysis without requiring it.

### 24.5 Functional menu and interaction scope

The full-content prototype includes preparation, hero/weapon/rune selection, cooperative sessions, permanent upgrades, Codex, settings, in-run inspection/reward choices and simple results. Ordinary in-run panels/dialogue do not pause combat. The reward side panel leaves movement accessible on visible ground, and UI clicks cannot accidentally invoke attacks. No forced pause for level-up choices, quest text or routine discoveries.

Exact layouts, focus navigation, font sizing, detailed accessibility options, touch adaptation and controller support are not fully authored; preserve approved remapping/readability without fabricating final device coverage. No UI framework is prescribed.

## 25. Onboarding and post-run experience
<a id="gds-onboarding"></a>

**Basis:** V24.1-V24.6; V40.16; final V42.6 A.

### 25.1 Onboarding

Start in a normal run with short dismissible contextual guidance introduced progressively, and an option to disable tutorials. No mandatory separate campaign or prolonged instruction before play. Discovery-based learning offers optional explanations of mechanics actually encountered, preserving hidden recipes and secrets.

The starter roster offers suggested beginner combinations but does not lock heroes to weapons. The first run has a gentler opening that transitions into ordinary difficulty without altering bosses, Collapse, rewards or fundamental combat rules. Exact gentler-opening coefficients are tuning, not a permanent easier mode hidden from records.

A short skippable first-run summary explains retained rewards, permanent upgrades, equipment unlocks and Codex, without requiring a purchase. Co-op contextual hints cover shared XP, individual builds, revival and gateway behavior without pausing. Definitions such as damage versus barrier loss, valid contact and pending choices should be learnable through feedback, not required encyclopedic reading.

### 25.2 Simple Run Summary - final initial scope

V42.6 **A** supersedes the proposed detailed analysis/feedback screen. The initial post-run interface presents:

| Included | Required meaning |
|---|---|
| Victory or defeat | Actual terminal outcome. |
| Survival duration | Appropriate recorded duration. |
| Final level | Achieved shared progression level. |
| Enemies defeated | Correctly attributed/defined count, without cleanup kills. |
| Final build | Hero, weapon, runes and acquired development in readable form. |
| Earned rewards | Correct retained/permitted rewards, not an invented victory payout. |
| Newly unlocked content | Actual discoveries/unlocks distinguished as appropriate. |

Prior Contextual Mastery Records remain retained; choosing a simple results screen does not erase them. Detailed damage attribution screens, cause-of-death analytics, timelines, replay analysis and an integrated feedback form are deferred. A record-setting build can remain inspectable through personal records without requiring the rejected analytics product. No mandatory competitive leaderboard, replay infrastructure or external telemetry collection is authorized.

Players should be able to move promptly to preparation/another run. No automatic extra tutorial purchase, compulsory lore viewing or new reward-choice system is added to the results screen. Exact run-history retention is open.

## 26. Narrative foundation and content boundaries
<a id="gds-narrative"></a>

**Basis:** V41.1-V41.10, with explicit stop/defer instruction after V41.10. Detailed prose, histories, dialogue, names and further eras are deferred until prototype stability. These facts are canonical foundations, not a mandate for new gameplay systems.

### 26.1 The Unfinished World

The Creator never completed the laws of existence. Nature, civilization, magic and death developed through incomplete and contradictory rules, producing identities and histories beyond the original plan. Accumulating contradictions destabilize reality as the Collapse. Unravelling embody instability; Erasure embodies existential removal. The Unfinished Canvas is the underlying foundation, not an approved commercial game title.

### 26.2 The Unwritten

Heroes are beings whose identities developed beyond the Creator's design. They absorb/combine/transform creation's fragments, explaining mechanical experimentation and growth without being chosen saviors or fragments automatically destined to reunite. Each may resist for personal reasons; no compulsory morality, allegiance or save-the-world quest is imposed.

Powers, ranks, runes, Evolution and Fusion have narrative correspondence to acquiring/mastering/transforming laws, but this does not remove explicit gameplay compatibility/costs. Lore does not make Hunters omniscient or alter their approved targeting.

### 26.3 Faction philosophy

Wildborn embody **Instinct**: life must be free to evolve, adaptation/territory opposed to imposed artificial control. Runebound embody **Order**: existence requires structure, developed through constructs, arcane regulation and attempted repair. Hollow Legion embody **Memory**: incomplete death leaves civilizations persistent between life/death, resisting loss of identity and forgetting.

Ideological incompatibility sustains conflict despite the common Collapse threat. No faction is inherently good/evil. Bosses embody their beliefs; killing one does not exterminate the faction. No mandatory faction reputation, diplomacy or permanent player allegiance follows from this lore.

### 26.4 The Misguided Restoration

The Forgotten Creator genuinely seeks to preserve a dangerously unstable creation, but believes dismantling/rebuilding its laws is necessary. It fails to recognize evolved inhabitants' independent right to exist. Powerful but not omnipotent, it misunderstands the world. Destruction follows its restoration objective rather than cruelty alone. Players need not forgive it, converse, select a moral ending or complete secondary objectives: defeating it remains sufficient victory.

### 26.5 Echoes of Creation

Each run is a different fragmented manifestation. Winning genuinely preserves that manifestation; future runs do not undo earlier victories. Defeat is a failed attempt, not deletion of earned knowledge/mastery. Procedural geography and challenge contradictions can vary. Multiple Unwritten share a manifestation in co-op. No requirement to complete every manifestation, endless mandatory cosmic loop or hidden true ending invalidates the ordinary win.

### 26.6 Organic discovery and layered truth

Optional environmental evidence, artifacts, NPCs, inscriptions, bosses, realms and Codex fragments can be found in different orders over several runs. No mandatory extended dialogue, cutscene, chronological campaign, relationship grind or artificial repeated-victory gate. Ordinary dialogue is skippable and nonblocking. Detailed lore can be reviewed outside combat.

| Narrative layer | Resolution policy |
|---|---|
| Observable world | Combat/factions/regions/Collapse experienced directly. |
| Discoverable history | Civilizations, faction origins, lost technology and character histories have answers. |
| Hidden truths | Creator intent, Unwritten, manifestations and Erasure can be investigated. |
| Beyond known creation | Creator's own origin and the ultimate boundary/beyond the Canvas remain unresolved. |

Why Collapse occurs, faction hostility, hero origins, restoration motive and Unravelling/Erasure nature are discoverable. Why creation was unfinished and how manifestations originated are partly discoverable. Stranger identity is a hidden revelation. Conflicting character interpretations may coexist without rewriting established facts. Future lore must preserve previous accomplishments.

### 26.7 Recurring characters and the Stranger

The six primary NPC personalities/origins are specified in section 18 and persist across manifestations. They may acknowledge heroes, discoveries/victories and past encounters without automatic relationship benefits.

The Stranger is **The Discarded Creation**: rejected as flawed, incompletely erased, surviving between manifestations and understanding contradictions. Its support for Unwritten blends curiosity and defiance, not guaranteed benevolence. No secret betrayal system or undisclosed bargain punishment. Its ultimate motive may remain partly ambiguous. Detailed chronology, dialogue and the missing approved hero-origin descriptions are deferred/source gaps, not completed story content.

## 27. Full-content prototype scope and acceptance
<a id="gds-prototype"></a>

**Basis:** Latest V42.3 C, V42.4 B, V42.5 B and V42.6 A. Full-content scope supersedes the earlier compact/reduced-content acceptance target. Individual mechanics may still be tested before the full roster is complete; this is not an implementation sequence or a reason to delay playtesting until final polish.

### 27.1 Required approved content breadth

| Content | Full-content prototype requirement |
|---|---:|
| Heroes | 9 |
| Main weapons | 9 |
| Global runes | 5 |
| Rune-pair interactions | 10 |
| Acquired powers | 18, six in each category |
| Ordinary power ranks | 5 each; 90 catalog rank states |
| Authored signature rank milestones | 36, two per power |
| Standard Evolution forms | 36, two per power |
| Advanced Fusion recipes | 6 |
| Core regions / faction territories | 3 with transitional areas |
| Ordinary regional archetypes | 18 |
| Regional elite counterparts | 18 |
| Regional bosses / blessings | 3 / 3 |
| Universal Hunter archetypes | 2 |
| Friendly NPC principal archetypes | 6 |
| Optional realms | 4 |
| Landmark types | 12: 3 guaranteed anchors, 9 variable |
| Final boss / core abilities | 1 / 7 |
| Primordial Manifestation types | 4 |
| Optional world-event archetypes | 6 |
| Quest archetypes | 10 |
| Destructible categories / movable types | 6 / 6 |
| Environmental hazard / mechanism types | 7 / 8 |
| Pickups / stationary restoration types | 8 / 4 |
| Named bargain archetypes | 8, plus compatible variable composition |

Include the core world, progression, co-op, environmental, NPC, discovery, combat, Collapse, victory/defeat, persistent progression and functional UI systems described here. Full content means functional distinct mechanics, not mere icons or menu entries. It does not make every procedural landmark or NPC appear in one run, make locked content immediately owned by a fresh account, or require finishing every future dialogue/quest variant before acceptance.

<a id="gds-acceptance"></a>

### 27.2 Stable, Complete and Replayable

Acceptance requires repeated solo and cooperative complete runs with consistent combat/progression/revival/outcomes and playable performance. Approved content must be genuinely obtainable under its requirements, not only accessible through a developer-only shortcut. Fresh-account victory and viable starter builds remain design goals. Different coherent builds must be playable; not every combination must have equal effectiveness.

The owner reconfirmed the following V42.4 category names and coverage. The examples describe player-observable outcomes. The QAS governs the evidence and pass criteria. [Acceptance categories](QAS.md#qas-acceptance)

| ID | Confirmed acceptance category | Gameplay outcome |
|---|---|---|
| AC01 | Content completeness | Every approved entry has a legal acquisition or encounter path and its distinct behavior works. |
| AC02 | Core combat | Geometry, costs, timing, ownership and defenses resolve consistently. |
| AC03 | Build freedom | Heroes, weapons, runes, ranks, frozen offers, Evolutions, Fusions and overflow support different coherent builds. |
| AC04 | Synergy consistency | Eligible reactions and long chains work. Each qualifying effect spends or grants its resource once. |
| AC05 | World exploration | Traversable routes connect regions, secrets, puzzles, objects and optional realms. |
| AC06 | Enemy behavior | Factions, ordinary enemies, elites, bosses, manifestations and Hunters express their authored behaviors and warnings. |
| AC07 | Catastrophic escalation | The clock, tier escalation and Hunter rewards hold throughout extended play. Final-boss difficulty remains independent of tier. |
| AC08 | Victory and defeat | Preparation, final transition, terminal result, settlement and return to preparation form a complete loop. |
| AC09 | Cooperative gameplay | Players can separate, share XP, earn local rewards, rescue, reconnect and finish together. |
| AC10 | Persistence and recovery | Settled progress survives interruptions. Recoverable grants reach the correct recipient once. |
| AC11 | Gameplay stability | Repeated sessions remain responsive with readable hazards, remapped controls, an operable HUD and non-blocking choices. |
| AC12 | Replayability | Subsequent runs offer varied routes and coherent builds with the proper persistent and run-scoped state. |

Seven complete-run conditions are required across the evidence set. A run can cover several conditions when its observed path meets each one. [Complete-run evidence](QAS.md#qas-runs)

| ID | Confirmed condition | ID | Confirmed condition |
|---|---|---|---|
| CR1 | Fresh-account solo victory | CR5 | Advanced build development |
| CR2 | Cooperative victory | CR6 | Defeat followed by subsequent runs |
| CR3 | Early final victory | CR7 | Disconnection and recovery |
| CR4 | Extended Collapse survival | | |

The category names and coverage are owner-confirmed. QAS IDs, test methods and device measurements belong to the working verification specification. Historical table wording and thresholds remain unrecovered (S04).

### 27.3 Acceptance blockers and non-blockers

**Blockers:** reproducible game-breaking crashes; progression loss or duplicated entitlements; a defect making final victory impossible; an approved Evolution/Fusion unreachable through any legal prerequisites; broken co-op combat/revival; unintended infinite combat/resource loops; missing essential mechanics presented as complete; unreadable essential danger that prevents intended counterplay.

**Not automatically blockers:** a legitimate overwhelming build; some unequal weapon performance without unviable choices; readable placeholder artwork; minor visual defects; unfinished detailed storytelling; provisional numerical balance; deferred analytics/feedback UI. A supposedly overpowered interaction must first be compared against its actual permissions rather than nerfed by default.

### 27.4 Derived gameplay verification scenarios

These describe observable behavior to verify, not tests already executed or a technical implementation mandate.

| ID | Scenario | Required observation |
|---|---|---|
| QA01 | Fill a preparation pool completely | No forced unknown wildcard insertion. |
| QA02 | Leave a wildcard blank and earn rewards at different times | Broader eligible opportunities are generated at reward time, not a hidden fixed run-start list. |
| QA03 | Earn choices, change build, open old reward | Original options remain frozen; invalid choices do not reroll. |
| QA04 | Invalidate every saved option | Applicable non-power compensation, no choice duplication. |
| QA05 | Fill ten slots then rank/evolve/fuse | No eleventh distinct power; ranks stay one slot, Fusion stays two. |
| QA06 | Decline eligible Evolution/Fusion | It can return via future eligible rotation; no automatic acquisition. |
| QA07 | Try incompatible standard forms | One standard form per base; saved conflicting choices become invalid. |
| QA08 | Try Seismic Arsenal with Thermal Equilibrium | Reject ordinary two-rune recipe impossibility, not the entire Fusion system. |
| QA09 | Attack multiple enemies with an activation cost | Pay once for that cost scope; real per-target exceptions only when authored. |
| QA10 | Miss after valid activation / fail placement before activation | Miss keeps costs; failed validation spends nothing. |
| QA11 | Pay a lethal HP activation cost | Death, no hostile retaliation, affected cast ends. |
| QA12 | Remove a temporary buff after projectile launch | Existing committed snapshot remains; future activations use new stats. |
| QA13 | Change target defense during a DoT | Subsequent tick mitigation changes; source offensive snapshot does not. |
| QA14 | Refresh Burn/stack Bleed just before a tick | Existing cadence continues; no immediate duplicated tick. |
| QA15 | Tick exactly at natural expiry | Scheduled tick first, then eligible one-time expiry reaction. |
| QA16 | Replace a barrier or expire it naturally | No false hostile-depletion Aegis Release. |
| QA17 | Hit multiple compatible barriers | Shortest lifetime first; residual damage flows to next barrier then HP. |
| QA18 | Deal only barrier damage / overkill | No ordinary Vital Exchange recovery from either amount. |
| QA19 | Fully absorb a hostile hit in a barrier | Eligible Reprisal Pulse occurs; evasion and HP sacrifice do not qualify. |
| QA20 | Generate an enhanced Aegis barrier then deplete it | Only its absorbed hostile damage charges one release; no reservoir/barrier self-loop. |
| QA21 | Have two players apply Bleed/Burn/Chill/Fracture | Independent damage/status ownership; category-specific combined control/defense. |
| QA22 | Trigger a personal pair using only teammate status | No default permission; explicit cooperative exceptions only. |
| QA23 | Try a same-hit newly applied status reaction | Pre-existing-state rule respected. |
| QA24 | Consume all Bleed then kill | A current-Bleed-at-death condition cannot use historical consumed Bleed. |
| QA25 | Keep a valid Death Bloom chain at amplification cap | Further genuine kills continue at the cap. |
| QA26 | Sustain Endless Reverberation then miss one branch | Successful branches persist; missing branch cannot continue itself. |
| QA27 | Hit target with two darts from one Familiar | They do not count as two Converging sources. |
| QA28 | Damage target with three genuinely different sources | Convergence/Third Vector obey windows, cooldowns and one-use events. |
| QA29 | Launch enemy into another enemy and a wall | Real momentum, resistance, impacts and ownership; no stationary contact loop. |
| QA30 | Apply opposing forces from several owners | Primary cause follows remaining impact contribution, not last touch alone. |
| QA31 | Hit a burrowed/intangible creature with incompatible delivery | No false hit; exposed phases remain beatable. |
| QA32 | Bow/Ink Dart targets move after firing | Base projectile can miss; no free homing/prediction. |
| QA33 | Move after launching Chakram / during Arcane Focus | Chakram returns toward moving owner; beam origin follows but direction stays committed. |
| QA34 | Warhammer wave or Whip retraction moves enemies | Innate force works without automatically granting unequipped rune-pair reactions. |
| QA35 | Rebound a shard into an armed mine, wave contacts shard | Reciprocal Seismic Resonance requires actual contacts and consumes bounded charge. |
| QA36 | Break/obstruct Infinite Domain triangle | Interior pulse suspends; real eligible link behavior persists. |
| QA37 | Conduct Thermal Shock and Eternal Ember heat | Only the designated heat-pulse path transfers Burn; no infinite conductive copies. |
| QA38 | Generate Chorus from blade convergence | Next nonparticipant source spends it; Chorus blades cannot recharge it themselves. |
| QA39 | Kill Grave-Imprinted enemy with independent source | One empowered blossom replaces ordinary one; residual strength does not compound. |
| QA40 | Owner dies with mines/DoTs/companions active | Committed effects persist; ordinary/autonomous attack starts suspend. |
| QA41 | Owner dies then their Bleed kills while teammate lives | Eligible owned kill reactions may resolve, healing cannot revive owner. |
| QA42 | Last player and Creator die in one causal group | Victory; no waiting for future projectiles/ticks if Creator survives. |
| QA43 | Interrupt a revive channel and resume with allies | Progress retained, shared meter, diminishing extra-rescuer speed. |
| QA44 | Revive low-HP player with a fatal automatic HP cost | Suppress the lethal auto-cast only during protection; affordable costs still paid. |
| QA45 | Disconnect last controlled survivor | Stationary vulnerable character, limited survivor grace, no immortality/AI pilot. |
| QA46 | Split teammates across realms | Shared clock/XP; local combat/revival and personal choices remain spatial/individual. |
| QA47 | Join a regional encounter late without damage | Nearby valid participation qualifies; no minimum-damage or last-hit gate. |
| QA48 | Remain remotely absent from encounter | No automatic local blessing/quest encounter reward; shared XP remains. |
| QA49 | Enter final gateway with dead/remote teammates | Entire party/bodies transfer, no auto-revival or free resource reset. |
| QA50 | Start/continue events at Collapse | New optional starts blocked; already active content follows approved continuation rules. |
| QA51 | Advance catastrophic tier on injured enemies | Max HP/offense rise, absolute current HP and committed attacks preserved. |
| QA52 | Delay final arena entry to extreme tier | Creator/arena retain authored difficulty with only applicable party/challenges. |
| QA53 | Kill many fresh Hunters | Full authored XP/exceptional rewards, no repeat penalty; Essence/overflow own caps still apply. |
| QA54 | Resurrect/re-kill one enemy | One progression entitlement total, valid repeat kill reactions. |
| QA55 | Destroy a neutral object by faction combat | No invented player damage/kill ownership. |
| QA56 | Deplete shared service stock / purchase personal upgrade | Correct shared versus personal scope; no duplicated resource/currency spending. |
| QA57 | Return to an exhausted fountain/merchant | No automatic refill/reroll/rare-offer reset. |
| QA58 | Raise/lower maximum HP | Current HP preserved/clamped; no heal/damage/sacrifice trigger. |
| QA59 | Reach completed build / overflow cap | Levels can continue; only bounded permitted improvements then utility. |
| QA60 | Open reward/menu while moving | Real-time world continues; UI clicks do not miscast, movement remains available. |
| QA61 | Dense personal/party attack effects | Critical enemy tells/player position remain readable; cosmetic reduction does not delete combat. |
| QA62 | Finish or lose a run | Simple correct summary, retained earned permanent rewards, no unearned victory payout. |

QA01–QA62 define required behavior. Production verdicts require evidence from the build under test. [QAS scenario mappings](QAS.md#qas-scenarios)

## 28. Revision and supersession register
<a id="gds-revisions"></a>

This register prevents older files or assistant alternatives from reintroducing rejected rules. Only supported replacements are resolved here; ambiguous boundaries remain in section 29.

| Earlier / rejected direction | Current governing decision |
|---|---|
| Mobile-first Diep-like tank PvP product | New PC-prioritized top-down fantasy PvE/co-op product; platform distribution open. |
| Short mobile session / exact 25-minute run end | Typical 25-40 minutes; gateway/Collapse at 25; no maximum duration. |
| Runes acquired as ordinary random cards or expandable slots | Pre-run global equipment, two fixed distinct slots, no meta capacity growth. |
| Approximate 10-12 acquired capacity | Initial target 10, V40.7. |
| Variable per-power rank caps/ordinary branching | Five ranks, authored fixed progression with Rank 3/5 milestones. |
| 12 total powers / 24 Evolutions | 18 powers / 36 Evolutions after V37 expansion. |
| Six or nine runes including Hex | Five runes; Flame and Frost added, Hex excluded. |
| Multiple compatible standard Evolutions of same base | One mutually exclusive standard form per power per run. |
| Further recursive Fusion tiers | Parallel disjoint two-component Fusions, no recursive stages. |
| Automatic Fusion / rare Fusion Essence | Subsequent reward selection, no additional consumable catalyst. |
| Expanded build tracking/recipe reward indicators | Passive Codex/build inspection initially; richer assistance deferred. |
| Polynomial XP indefinitely | Hybrid progressive-exponential transition by player level. |
| Repeat Hunter XP reductions / reward suppression | Full authored rewards on every eligible fresh kill, V40.5 D. |
| Fixed individual Hunter strength forever | No encounter-specific phases, but later global tier stats apply. |
| Six-role ordinary Unravelling faction | One powerful independent Unravelling archetype plus Erasure. |
| No player priority / Erasure primarily seeks powerful NPCs | V42.1: detected-player priority with faction combat, no omniscience. |
| All co-op encounters scaled locally | Global initialized party-size baseline; separation does not weaken enemies. |
| Unbounded enemy speed/resistance with HP | HP/damage unbounded; speed/control/population separately bounded. |
| Final boss inherits catastrophic tier | Authored final difficulty independent of elapsed time/tier. |
| Existing enemies heal proportionally at tier transitions | Preserve absolute current HP. |
| All teammate statuses automatically available for personal reactions | Independent ownership and explicit cooperative compatibility. |
| Every reaction/DoT can proc everything | Contextual event/source eligibility and authored continuation. |
| Owner death suppresses all newly caused reactions | Committed lifecycles may cause eligible secondary reactions while run active. |
| Immediate terminal loss before simultaneous lethal response resolves | Immediate character death, then causal group completion; mutual Creator kill can win. |
| Earlier victory-only banking of all special currency | Later V40.13 earned permanent currencies retained; victory bonus requires victory. |
| Remote party automatically receives all boss/event/quest rewards | V42.2 nearby inclusive participants for encounter-specific rewards; shared XP/final victory exceptions. |
| Prototype compact/reduced roster | Full-content prototype, V42.3 C. |
| Prototype must be release-polished | Stable, Complete and Replayable; tuning/story/polish can remain provisional. |
| Detailed post-run analytics/feedback form | Simple Run Summary, V42.6 A. |
| Continue detailed historical eras/biographies now | Narrative foundation only; further story deferred until prototype stable. |
| Universal baseline healing / auto level-stat growth | No regen, no starting barrier, no level heal/damage/speed growth by default. |
| Universal random crit/miss rolls | Conditional precision and actual geometry. |
| All Spectral Lance hits always equal through every rank | Base consistent piercing; Rank 5 explicitly adds Ascending Pierce. |

Names such as Blood Spiral, Frost Circuit, Blood Cleaver, Eternal Spiral, Crimson Tempest, Storm Cyclone, Greatblade Form, Volley Form and Constellation Form were examples or earlier concepts unless a distinct approved definition here says otherwise. Do not add them as extra required powers/transformations merely because a historical note used them.

## 29. Open-detail and source-gap register
<a id="gds-open"></a>

These entries are deliberately separated from confirmed behavior. They do not reopen every approved choice. Low-level numbers can be provisionally tuned under the owner's delegation; unresolved gameplay semantics require explicit labeling/review rather than being presented as past approvals.

### 29.1 Eight deferred design groups

| Group | Deferred content |
|---|---|
| D1 - Numerical balancing | Nonselected coefficients, limits, cooldowns, XP transition, prices, enemy base stats and feedback-driven tuning. |
| D2 - Procedural geography | World dimensions, generation distributions, detailed interiors, entrance paths, traversal and encounter placements. |
| D3 - Cooperative edges | Reward proximity/absence/death/disconnection details, session joins/leaves and exact cooperative eligibility. |
| D4 - Rare combat interactions | Lifecycle/ancestry/geometry conflicts and explicit per-effect exceptions. |
| D5 - Individual authored content | Concrete quests, puzzle variants, inventories, treasure tables, transformation forms and missing source-specific behaviors. |
| D6 - Challenges/mastery | Individual challenge effects/unlocks, achievement thresholds/cosmetics and weighted reward tables. |
| D7 - Detailed UX/accessibility | Final layouts, accessibility refinements, history retention and optional later informational assistance. |
| D8 - Detailed story | Character biographies, names, eras, inscriptions, dialogue and deeper revelations after stable prototype. |

### 29.2 Mechanical boundaries from the R1 open register

The O IDs preserve the original questions. Read each alongside any applicable PR in §29.4 and the owner decisions. A rule can resolve one part for the prototype while other parts remain open. For essential uncovered details, record a compatible choice and test before use. [Prototype rules](#gds-rules) · [Owner decisions](#gds-owner)

| ID | Open point | What is already fixed |
|---|---|---|
| O01 | Must both rune slots be filled, or may a player intentionally use fewer? | Two fixed slots, no duplicate or third rune, pre-run selection. |
| O02 | Candidate-pool size, ordinary card count, wildcard weights and eventual-offer scheduling | Separate pool/owned capacity; no forced wildcards in a full pool; freeze at earning. |
| O03 | Seeing an unknown expanded power versus satisfying its named discovery condition | Encounter knowledge and permanent purchase ownership are distinct; named conditions cannot silently disappear. |
| O04 | Exact availability/unlocks of the original twelve powers on a new profile | Full-content catalog exists; early versus discovered availability was intended, not every power automatically granted. |
| O05 | Bonus slot presentation/rotation when both Evolution and Fusion qualify | One total selection; ordinary Evolution has one rotating bonus; Fusion appears through later rewards. |
| O06 | Standard Evolution clues versus complete pre-acquisition requirement disclosure | Successful personal acquisition verifies the standard recipe; Fusion has its own identified-before-verified stages. |
| O07 | Exact main-weapon transformation/Evolution content beyond Artisan examples | Nine base weapons approved; 36 named Evolutions belong to acquired powers. |
| O08 | Continuous Spinning Blade activation/cost/counter cadence and full weapon inheritance | Physical contacts have intervals; shared every-third rule cannot self-trigger or charge per frame by accident. |
| O09 | Exact counter-granting source for the Sword/Spinning Blade bonus slash | Preserve established shared-counter behavior, not an invented mandatory innate Sword status. |
| O10 | Parent-hit status application visibility to separately generated child lightning | No same-hit exploitation of newly applied status by default; authored causal state capture. |
| O11 | Echo count per parent activation, parent hit-count sampling and each delivery's copy origin | Copy attacks, not permanent powers; explicit geometry/identity; Resonant Fidelity distinct targets. |
| O12 | Reapplication snapshot policy for mixed-potency Bleed stacks and Burn refresh | Cadence preserved, owner separation, no implicit extra tick; live target defenses. |
| O13 | Exact Temporal Compression clock treatment for refreshed DoTs/Burn intensity/mine arming | No duplicate scheduled damage, global time change or automatic teammate acceleration. |
| O14 | Temporal Echo's coefficient input before/after mitigation and damage footprint | Delayed impact-location repetition, not guaranteed hit or full Echo Strike delivery. |
| O15 | Crimson Reservoir restoration release trigger/rate | Capped eligible excess, not barrier or direct HP-cost payment. |
| O16 | Fortification selection when a weaker/new barrier would otherwise be rejected | Real reserve consumption, strongest replacement rules, no manufactured depletion. |
| O17 | Exact output categories for Collision Burst, Impact Cadence and some spectral blade manifestations | Their approved hit/force behaviors remain; names do not settle damage type. |
| O18 | Outer Edge reference geometry under several static/dynamic spatial modifiers | Bonus only for actual added coverage, no free damage on ordinary interior hits. |
| O19 | Bloom Convergence overlap accounting for many simultaneous explosions | Genuine damage-area/time overlap, concentrated extra burst, no purely visual triggers. |
| O20 | Hero zero-charge Harmonic Burst, detailed starter active delivery and omitted manual numbers | Selected identities and zero-charge usability remain; no invented basic spell. |
| O21 | Specific Catalyst Mark compatibility, all Alchemist reaction entries | Authored status combinations, no universal every-status reaction. |
| O22 | Dormant Guardian shield/passive-structure behavior after owner death | No new autonomous/ordinary attacks; committed lifetimes and physical structures persist. |
| O23 | Friendly-fire, player-versus-hazard and movable-object damage matrix | Protected NPCs, no ordinary hostile player collisions, causal ownership and approved exceptions. |
| O24 | Slow/force contributions from enemies' voluntary motion and moving obstacles at ambiguous impacts | Dominant remaining cause, real momentum, no last-touch theft or duplicate ownership. |
| O25 | Natural scaled hazard activated by a player | Neutral hazards scale; player attacks/objects do not automatically gain that multiplier. |
| O26 | Shield durability, shield contact trigger permissions and ground/AoE obstruction classes | Real interception distinct from defense/barriers; no automatic omnidirectional immunity. |
| O27 | Exact projectile/beam overlap rules at extreme attack frequency and active-entity limits | No arbitrary loss of valid attacks; authored source limits and real per-target cadence. |
| O28 | Fate of pending costs/child events at rare same-time death, expiry and revive boundaries | Immediate death; current causal-group completion; no ordinary healing resurrection. |
| O29 | Guest recasting, survivor grace and reconnect races | Vulnerable guest and finite survivor grace are confirmed. PR06 supplies the prototype window and boundary rule. Original-host recovery is settled by OWNER-T01. |
| O30 | Maximum party size, late join/permanent leave and challenge access | Party scaling locked at initialization; four is an example, not approved cap. |
| O31 | V42.2 participation radius, late exit, dead/disconnected eligibility and claim timing | Nearby inclusion with no damage minimum; shared XP and final victory distinct. |
| O32 | Local-event participant wave adaptation after global party-scaling adoption | Do not replace or weaken global baseline; no hidden duplicate scaling. |
| O33 | Incomplete puzzle abandonment when teammates occupy different places | Completed shortcuts persist; one departure must not silently wipe active teammate progress. |
| O34 | Dormant/newly discovered puzzles and realm trials after 25:00 | No new optional starts, existing mechanisms/events usable, escape routes always remain. |
| O35 | Early gateway discovery chain, preparation duration and effect transport exceptions | Intentional optional early access; normal gateway at 25; party/corpses transfer; no free recovery. |
| O36 | Max-HP tier changes interacting with boss phase/low-health predicates | Current HP preserved, no phase rollback, no free healing. |
| O37 | Exact source-specific immunity/airborne/underground/spectral matrices | Capability independent of damage type; readable exposure for every starter build. |
| O38 | Detailed Primordial Manifestation and player construct/familiar lifecycle attributes | Four independent summon identities and approved core mechanics; no invented boss damage gate. |
| O39 | Event-specific failure scope, gateway abandonment and local quest retroactive credit | Declared stakes/consent, optional content, contextual lifecycle/ownership. |
| O40 | Expanded statistics, difficulty tiers, permanent shop costs, tutorial gentleness and stock values | Approved formulas/reference targets are not erased; additional numbers provisional. |
| O41 | Exact content/feedback/reference menus beyond functional scope | Simple post-run screen, passive recipes, customizable readable HUD; analytics deferred. |
| O42 | Device/performance budgets and practical execution treatment of very large valid chains | Stable playable sessions, no silent gameplay deletion or arbitrary new chain prohibition. |

### 29.3 Source gaps that cannot be reconstructed as approvals

| Gap | Evidence limitation | Treatment |
|---|---|---|
| S01 | Full early V0-V10 transcript and V15.2-V20 decision sequence unavailable | Use directly inspected handoff rules and later explicit approvals; no fabricated version ledger or missing session policy. |
| S02 | V41.7 approved a nine-hero origin table not actually rendered in the visible record | Preserve characterization decision; do not invent biographies or pretend all origins were recovered. |
| S03 | V40.19.8 manual-ability numeric table not visible | Retain contextual 6-24-second typical category and visible passive targets; actual ability numbers remain tuning/source gap. |
| S04 | The original V42.4 tables were absent from the historical compilation. The owner reconfirmed the 12 category names and seven complete-run conditions. | Use AC01–AC12 and CR1–CR7 in §27.2. Original phrasing, table structure and any unstated thresholds remain unrecovered. |
| S05 | Multiple historical interactive charts/sliders rendered empty | Use selected textual formulas/values only; do not treat unavailable widget state as a decision. |
| S06 | P27 retained partial host-loss and shared challenge-access references. OWNER-T01 now supplies the working original-host policy. | Apply the 180/30-second recovery policy prospectively. Other historical terms and precise shared challenge-access terms remain unrecovered. Preserve §22.1 personal ownership boundaries. |

The rejected last consolidated Markdown is intentionally not used to fill these gaps. Recovered source text can close a historical gap. New owner decisions or provisional behaviors take effect under their own provenance.

<a id="gds-rules"></a>
<a id="gds-provisional"></a>

### 29.4 Provisional prototype rules under OWNER-T04

**Register revision 1 for the planning baseline.** Each row carries the status **provisional, awaiting owner playtesting**. The choices below apply to the named gaps for the prototype. The O and S entries preserve their provenance. Verify the selected behavior against its confirmed constraint before relying on it. Pin the rules revision to the run, recovery data and test evidence. Record changes to a choice, rationale or adjustment point in this register, increment its revision and rerun the affected witnesses. Preserve already-issued entitlements on existing profiles. [Owner decisions](#gds-owner) · [QAS triage](QAS.md#qas-triage)

| ID and source | Selected behavior and adjustment point | Rationale and confirmed constraint | Required witnesses |
|---|---|---|---|
| <a id="pr01"></a> PR01 · O01, §1.2 | Permit zero, one or two filled slots in preparation. Adjust the empty-slot policy. | Resolves conflicting historical wording while preserving two fixed slots, distinct runes and pre-run selection. | Accept all three counts. Reject duplicates, a third slot and ordinary mid-run replacement. |
| <a id="pr02"></a> PR02 · O03–O04, §§9.1, 20.3 | P01–P12 start known and eligible to prepare. P13–P18 require named discovery plus purchase or an expressly authorized direct unlock. Adjust starter eligibility by ID. | Provides viable fresh builds while preserving expanded power gates and separate knowledge, ownership and run acquisition. | Fresh profile shows twelve available and zero acquired. A mere sighting cannot unlock an expanded power. Exercise its actual discovery and later legal acquisition. |
| <a id="pr03"></a> PR03 · O02, O05, §§1.3–1.4, 9–10 | Ten candidate spaces. Offer up to three distinct legal ordinary choices. When eligible, add the single rotating Standard Evolution card. If Fusions qualify, also show one separately rotating Fusion card. Each queue advances at eligible reward generation. Every offer permits one total pick. Adjust pool size, ordinary count, combined presentation and seeded fair scheduling for continuously eligible prepared entries. | Preserves earn-time freezing, eventual eligible offers, declines and actual retained catalyst properties. Wildcards draw only in blank spaces at earning. A simultaneous Fusion opportunity leaves the confirmed Evolution rotation intact. | Earn successive rewards with multiple eligible forms, with both bonus types and with exhausted pools. Decline, open saved offers out of order and recheck newly incompatible components without a reroll. Exercise a preserved evolved catalyst and a lost required property. |
| <a id="pr04"></a> PR04 · O35, §§1, 11.2–11.5 | In one in eight **eligible Silent Observatory layouts**, a discoverable inscription and two reachable rotating conduits can reveal an early gateway. Align both and intentionally enter before 25:00. Adjust conditional module weight, clues and mechanism composition. | Makes early access rare, reachable by ordinary movement and interaction, discoverable without a marker and optional. The Observatory itself is variable. The ordinary gateway still opens at 25:00. | Play a baseline starter on a qualifying seed using visible clues. Contrast a seed without the module. Demonstrate legal early entry and victory, whole-party transfer, carried corpses and no Collapse escape. |
| <a id="pr05"></a> PR05 · O31, O39, §§5.2, 15.7 | Use the encounter footprint plus a 200-movement-unit margin in its realm, inclusive at completion. A nearby living connected arrival qualifies immediately. Previously present participants whose bodies remain inside qualify through death or temporary disconnect, through guest grace if disconnected. A departing participant must return by settlement. For final victory, include the initialized roster, including disconnected members, and deliver personal grants as needed. Adjust the local margin, settlement membership and disconnected-victory policy separately. | V42.2 includes late arrivals with zero damage. Geography, shared XP, personal mastery and party-wide victory have different eligibility. Confirmed final victory includes eligible dead teammates. | Test boundary/just outside, late arrival, support only, departure/return, dead and disconnected body, remote absence, party-wide victory and later delivery exactly once. |
| <a id="pr06"></a> PR06 · O29, M15 §§21.2–21.3, §5.5 | Give a disconnected guest 60 seconds of active logical run time from recorded loss for survival eligibility. Stop new automatic/manual commitments. Continue already committed effects. An accepted valid reconnect exactly at the deadline precedes the survivor check. Adjust grace and tie order independently of OWNER-T01. | Preserves the stationary, damageable guest, ordinary corpse/rescue, finite wipe protection and alive/dead return. Expiry leaves physical state and earned entitlements intact. A still-active run can accept a later reconnect. | Test lethal damage during grace, expiry with/without another survivor, alive/dead return and exact boundary. Original-host suspension freezes the guest's logical clock. |
| <a id="pr07"></a> PR07 · O30, O42, §§5.1, 23.5 | Verify native solo and two, three and four initialized players. During the run reconnects may reclaim existing seats. New entrants can join a subsequent run. Version the tested envelope and admission policy separately. | Four enables split-realm and multi-rescuer tests. The permanent product limit stays open. Global scaling uses initialized party size. | Independent profiles/processes at each size, locked party scaling after loss, two rescuers, cross-realm outcomes and later admission of a new player. |
| <a id="pr08"></a> PR08 · O15–O16, E07A, F06 | Every logical second a living injured Reservoir owner restores the least of reserve, missing HP and 5% of max HP. Debit actual restoration. Check a new Mirror Guard barrier's whole-instance replacement eligibility before spending reserve to fortify it. Adjust cadence, rate and replacement comparator. | Gives eligible stored excess a bounded recovery use. Preserve paid HP costs, lethal outcomes and strongest replacement rules. A rejected barrier spends nothing. | Test injured, full and dead owners, partial reserve, accepted/rejected barriers, hostile depletion and Aegis healing without reserve recursion. |
| <a id="pr09"></a> PR09 · O20, S03, H03 | At zero charges, Harmonic Burst can cast its normal first local magical link toward one legally reached target, with zero bonus links. A legally committed empty cast spends the applicable cost/cooldown and may miss. Adjust base geometry/potency and charged additions. | Preserves confirmed zero-charge usability, optional charges and a single authored ability. The original numeric table is unavailable. | Test zero/positive charge, clear and blocked lines, empty cast, retained cooldown and non-negative charge. |
| <a id="pr10"></a> PR10 · O10, O12, O18, §§3.4, 8, E15B, F03 | For a child lightning hit on the parent's target, use its pre-parent-impact status set and recheck ownership/consumption. For other targets use their pre-child state. Keep each accepted Bleed stack's snapshot to cap. On ordinary Burn refresh preserve owned snapshot, intensity and cadence. Compare same-owner Burn transfer by next unmitigated tick at current intensity. Only a strictly stronger transfer can replace potency for its bounded remaining duration. Outer Edge compares the same pose/time and other modifiers with and without the coverage expansion tested. Version each comparator separately. | Preserves ownership, cadence, actual added coverage and pre-existing status conditions. Weaker/equal transfer cannot refresh Burn. | Test same/different target, consumed stacks, weaker/equal/stronger transfer per owner, and interior/edge contacts while other geometry changes. |
| <a id="pr11"></a> PR11 · O33–O34, §§11.3–11.6 | An incomplete resettable puzzle resets when the last relevant occupant leaves its authored area. A dormant optional trial cannot start during Collapse. Existing mechanisms, active trials and all exits remain usable. Adjust area and start/continuation classifications per module. | Preserves a split teammate's ongoing activity, persistent completed shortcuts and safe route availability. | Have two occupants leave separately. Revisit a completed shortcut, compare dormant/active trials across 25:00 and leave through the ordinary exit. |
| <a id="pr12"></a> PR12 · O28, §3.4 | Resolve competing same-instant finite claims by authored priority, earlier logical commitment, then persisted canonical origin (preparation seat or authored world spawn provenance, source slot, activation ordinal, delivery sub-index). Normalize the admitted root set before debiting it. Adjust only genuinely tied claim priorities. | Assigns one expenditure/lethal owner while preserving independently committed mutual outcomes. Runtime IDs, traversal and packet order cannot decide a tied claim. | Reverse traversal/arrival, renumber runtime instances, exhaust one barrier/charge and reproduce the same per-origin debits, single elimination and mutual-lethal verdict. |

<a id="gds-reconciliation"></a>

### 29.5 Gameplay-facing reconciliation register

| Affected sections | Prior wording or gap | Authority and disposition |
|---|---|---|
| GDD §§1, 10, 17–18 and GDS §§1, 5, 30 | Initial delivery, host loss and technical ownership appeared open. | OWNER-T01/T02 establish original-host recovery and native LAN/direct IP. GDD keeps commercial launch and the eventual party maximum open. The TDS owns the approved working architecture and AGENTS the phase. |
| GDD §§10, 12 and GDS §§5, 15, 20 | Retention at victory/defeat was explicit, but crash exposure, lost acknowledgments and later delivery were absent. | OWNER-T03 adds immediate important settlement, bounded ordinary batches, full graceful settlement and cross-session recovery. Five seconds is provisional. PR05 covers disconnected membership. |
| GDD §§3, 6 and GDS §§1, 9–10, 20–21 | Pool size, empty slots, starting powers and simultaneous bonus cards appeared wholly undecided. | OWNER-T04, O01–O05 and PR01–PR03 supply prototype settings. M15 §§15–16 and later recipes retain frozen rotation, one choice, catalyst legality and personal unlocks. |
| GDD §10 and GDS §§5, 13, 15, 23 | Local eligibility, grace, late joining and the status of the four-player example were ambiguous for the prototype. | V42.2 and M15 §21 govern inclusion and guest behavior. PR05–PR07 fill only the adjustable boundaries. The partial S06 record remains separate. |
| GDS §§1, 11, 29 | Early access, puzzle abandonment and dormant trials during Collapse lacked a specific playable rule. | OWNER-T04, O33–O35 and PR04/PR11 select a reachable conditional layout and a split-party lifecycle. Gateway availability, body transfer and essential paths stay governed by §11. |
| GDS §§3, 6, 8–10, 29 | Open edge cases covered zero-charge Burst, reserve release, status/geometry comparators and finite claims. | OWNER-T04 and PR08–PR10/PR12 supply testable defaults. GDS §3.4 and source-specific damage, barriers, status ownership and recipe inheritance remain binding. S03's original ability values are missing. |
| GDD §17 and GDS §§27, 29 | A derived list stood in for missing V42.4 names. | Owner reconfirmation restores twelve categories and seven complete-run conditions. S04 retains its historical limitation. QA01–QA62 remain derived gameplay scenarios. |
| GDD §18 and GDS authority, §§28–30 | Historical edition statements and the two-document authority map predated the planning mandate. | Use the six-document authority split and record future changes with source and scope. Remaining historical gaps are S01–S03, S05 and the residual parts of S04/S06. |

## 30. Decision coverage map and glossary
<a id="gds-traceability"></a>

### 30.1 Coverage map

| Source range | Main specification coverage |
|---|---|
| E010 / M15 foundations | Product separation, true geometry, cost scopes, preparation, wildcard/frozen rewards, exploration, gateway, revival, disconnect, ownership and explicit supersessions. |
| V21 | Adaptive HUD, essential states, nonblocking reward panel, maps, interactions and teammate visibility. |
| V22 | Music, layered audio, direction, dialogue sounds and accessible category controls. |
| V23 | Hand-drawn animation/color restraint, customizable controls, reduced impact/clutter and occlusion. |
| V24-V26 | Contextual learning/co-op guidance, deferred broader accessibility work, solo/co-op stability; later prototype scope overrides reduced breadth. |
| V27-V29 | Starter heroes, three starter weapons, global rune capacity/effects and three initial pair reactions. |
| V30.1-V30.77 | Twelve initial powers, 24 signature milestones and 24 standard Evolution forms. |
| V31 | Three faction rosters/elites/bosses/blessings, underground/spectral and resurrection rules. |
| V32 | Independent invader redesign, Erasure, rewards and Collapse pressure with later targeting/scaling revisions. |
| V33 | Creator, seven abilities, four manifestations, Living Geometry, phases, arena and victory. |
| V34 | Region/landmark generation, discovery/events/realms, connectivity and environmental Collapse. |
| V35 | Causal objects, momentum, hazards, mechanisms, pickups/ownership/persistence. |
| V36 | NPCs, inventories, services, bargains, knowledge, quests and reward structure. |
| V37 | Six added heroes/weapons, two runes/seven pairs, six powers/twelve Evolutions and discovery unlocks. |
| V38 | Six Fusion recipes, inheritance/capacity/limits, knowledge and passive planning. |
| V39.1-V39.21 | Damage, barriers, status timing, eligibility, causal resolution, death, physical/ownership/recovery/resource/stat rules. |
| V40.1-V40.17 | Viability, pacing, XP/overflow, full Hunter rewards, capacity, progression, economy/challenges/records. |
| V40.18.1-V40.18.16 | Tier clock, exponential/bounded properties, regional/final exceptions, hazard/pre-Collapse/party formulas. |
| V40.19.1-V40.19.8 and delegation | Shared baseline, defense K, mobility/offense, weapon targets, contextual hero balance and deferred further coefficients. |
| V41.1-V41.10 | Unfinished World, Unwritten, factions, Creator, manifestations, delivery, NPCs and Stranger; later story deferred. |
| V42.1-V42.2 | Latest player-priority Hunter pursuit and nearby inclusive encounter rewards. |
| V42.3-V42.6 | Full-content prototype, stable/replayable standard, customizable HUD and Simple Run Summary. |

### 30.2 Terminology

| Term | Meaning |
|---|---|
| Main weapon | Independently selected automatic core delivery, outside power capacity. |
| Acquired power | An in-run independent attack, passive modifier or trigger power occupying one slot. |
| Candidate pool | Prepared future reward candidates; not already owned powers. |
| Wildcard | A blank preparation opportunity drawing eligible broader content at reward generation. |
| Global rune | Pre-run compatible attack modifier, outside power capacity. |
| Rune-pair reaction | Authored additional interaction requiring both relevant runes. |
| Rank | Ordinary power development; five states, signature milestones at 3 and 5. |
| Evolution | One selected major standard transformation at Rank 5 plus catalyst. |
| Fusion | Authored hybrid of two specific Evolutions retaining two original slots. |
| Catalyst | Eligible owned/equipped prerequisite, not automatically consumed. |
| Combat owner | Primary source recipient of damage/kill and compatible personal triggers. |
| Source identity | Attack family identity, distinct from owner or number of projectiles. |
| Participant | Locally eligible encounter contributor; latest rules include late non-damaging presence. |
| Ordinary progression entitlement | Single XP/loot/currency entitlement associated with an enemy identity. |
| Combat lifecycle | One alive-to-eliminated enemy life; resurrection can renew it without renewing progression. |
| Barrier | Personal damage-absorption capacity with source/lifetime, distinct from physical shield collision. |
| Reserve | Stored healing/charge resource, not inherently HP or barrier. |
| Snapshot | Relevant committed offensive properties at activation/application. |
| Unravelling | One versatile independent invader archetype, not a conventional region roster. |
| Erasure | Catastrophe-only Hunter, no HP bar, fully defeatable. |
| World Collapse | Global 25-minute escalation and gateway stage, not a hard run timer. |
| Catastrophic tier | Two-minute exponential HP/damage step, globally synchronized. |
| The Unfinished Canvas | Final arena and narrative foundation, not the finalized product name. |
| Simple Run Summary | Initial concise results interface; detailed analytics is not required. |

### 30.3 Documentation change boundary

Preserve the versioned decision basis when changing a mechanic. Identify whether a change is numerical tuning, a resolved open detail, a recovered source, a content addition or an actual superseding design decision. Update the GDD when experience/vision changes and the GDS when behavior changes. Do not treat old research, a technical agent's preferred architecture or this document's derived QA checklist as permission to alter approved gameplay.

The design baseline comprises V42.6 and the recorded owner supplement. The current mandate covers technical finalization, documentation reconciliation and implementation planning. Beginning production requires further owner authorization. [Current phase](../AGENTS.md#agents-phase)
