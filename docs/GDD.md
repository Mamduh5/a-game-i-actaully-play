# Game Design Document (GDD)

**Project:** New Unwritten / unfinished-world fantasy game; final commercial title open.  
**Approved design baseline:** Through V42.6, with latest revisions taking precedence.  
**Document edition:** Rebuilt V42.6 / R1, 2026-11-25.  
**Companion specification:** [GDS.md](GDS.md).  
**Purpose:** Preserve the game's vision, intended player experience, content identities, design rationale, scope and quality priorities. The GDS defines exact gameplay behavior, interactions and provisional numerical targets.

> This GDD and its companion GDS are newly written from the recoverable approved discussion and inspected earlier handoffs. The previous `game-design-specification.md` is not the source for this rebuild. These documents are a design baseline, not a statement that the game has been implemented or tested.


## Contents

- [1. Game identity and creative direction](#gdd-identity)
- [2. Design pillars and anti-goals](#gdd-pillars)
- [3. The player journey and core loops](#gdd-loop)
- [4. Build architecture as a player experience](#gdd-builds)
- [5. Playable heroes and weapon identity](#gdd-playable)
- [6. Runes, acquired powers and transformations](#gdd-powers)
- [7. The world and exploration experience](#gdd-world)
- [8. Enemies, factions and encounter diversity](#gdd-enemies)
- [9. The final encounter and the meaning of victory](#gdd-final)
- [10. Cooperative play without compulsory roles](#gdd-coop)
- [11. Inhabitants, events and meaningful optional work](#gdd-inhabitants)
- [12. Progression, economy and replay motivation](#gdd-progression)
- [13. Difficulty and the optional catastrophic battlefield](#gdd-balance)
- [14. Art, animation, audio and presentation identity](#gdd-presentation)
- [15. Interface, controls and learning](#gdd-interface)
- [16. Narrative foundation and deliberate limits](#gdd-narrative)
- [17. Full-content prototype and quality standard](#gdd-prototype)
- [18. Document ownership, open work and change discipline](#gdd-authority)

## 1. Game identity and creative direction
<a id="gdd-identity"></a>

### 1.1 The game being designed

A top-down fantasy PvE roguelite about discovering, assembling and playing extraordinarily powerful combat builds within a large, interconnected, procedurally varied world. Routine attacks are automatic. The player expresses skill through movement, positioning, manual hero abilities, route choices, voluntary challenges and decisions about how their build develops.

Play solo or with friends sharing one world and its progression clock. The world contains distinct hostile ecosystems, landmarks, secrets, NPCs, environmental mechanisms, optional realms and autonomous invading threats. Regional bosses provide optional run-long blessings. A final gateway leads to the Forgotten Creator and a complete victory. Remaining in the collapsing overworld instead becomes an increasingly extreme endurance choice.

The visual identity is expressive hand-drawn graphite on white paper, with restrained colored-pencil or watercolor accents for magic. The world is incomplete not only in its appearance but in its fiction: its inhabitants have grown beyond the Forgotten Creator's original design. The playable heroes, the **Unwritten**, embody that independence.

This is a separate product direction from the old Jangan Lari reference project and the earlier mobile-first Diep-like tank/PvP concept. Historical prototypes can inform deliberate reuse, but they do not determine the new game's weapons, controls, multiplayer scope or technical architecture. The project should remain one coherent design rather than an accumulation of unrelated feature experiments.

### 1.2 Platform and presentation direction

PC is the stronger first priority. PC browser delivery is acceptable, mobile support remains desired, and the exact launch platforms are not finalized. The camera is top-down or oblique top-down with a 2.5D impression. Sprites and layered artwork can express that appearance; the design does not require a true 3D engine.

A commercially finalized title has not been approved. **The Unfinished World** is the narrative foundation; **The Unfinished Canvas** is the final arena. Neither should silently become the game's official name merely because it appears prominently in mock text.

### 1.3 Creative references and exclusions

The owner's reference points include the build spectacle and meaningful development of *League of Legends: Swarm*, the weapon/hero/event inspiration of *Jotunnslayer: Hordes of Hel*, and the compositional interactions and resource consequences of *Mages of Mystralia*. These are recorded inspirations, not approvals to copy characters, exact mechanics, interfaces or technology.

In particular, do not reproduce a manual rune-placement board or spell-wiring editor. The desired depth comes from coherent rules working together during a run, not from making the player manually operate every weapon or edit a graph while being attacked.

### 1.4 The desired player response

The game should support four complementary reactions:

- "That combat felt excellent; I want another run."
- "That was difficult, but I learned how to handle it."
- "I found an interaction I did not expect, and my build became absurdly strong."
- "This risk came from a choice I understood, not from a hidden rule."

These responses must coexist. Powerful builds are not allowed only in a scripted showcase, and skill is not meaningful only before powers begin interacting. Players should feel both the consequences of poor positioning and the satisfaction of genuinely outgrowing a previously dangerous encounter.

## 2. Design pillars and anti-goals
<a id="gdd-pillars"></a>

### 2.1 Systemic power with explicit rules

Builds should change what attacks do: geometry, timing, targeting, inheritance, status application, displacement, resource conversion and conditional reactions. Numerical improvement supports that identity but does not replace it. A sword cleave, orbital blade, mine, autonomous companion and magical tether should remain mechanically distinct even when all benefit from the same equipped rune.

Large legitimate chains are part of the fantasy. The game may allow a carefully built character to kill a boss almost immediately. The distinction is between **earned power** and an invalid loop that duplicates an event, spends a resource twice, creates free lifecycles or ignores collision. Readability and computational safeguards must preserve legitimate outcomes rather than silently deleting damage.

### 2.2 Movement is central, not an inconvenience

Routine attacks do not stop movement or require individual fire inputs. A player can reposition while attacking, operate one defining hero ability and inspect choices without pausing the world. Specialized pursuers can exceed baseline player speed, so survival uses terrain, attacks, control and judgment rather than always outrunning every enemy in a straight line.

Dodging is primarily geometric. No mandatory universal dodge-roll is added. The Acrobat's Vault is one hero's capability; the world must remain navigable and attacks avoidable for heroes without it. Knock-up, slow, stun, force, materialization and damage remain different mechanics.

### 2.3 A world worth exploring

The world is larger in content than a normal run is expected to exhaust. It is not merely a circular arena with three visual skins. Distinct regions, transitional territory, recognizable anchor landmarks, variable sites, physical shortcuts and independent realms make route decisions meaningful.

Secrets should emerge through observation, experimentation, knowledge and sometimes enemy actions. A familiar landmark can offer a new interior or opportunity on another run. Optional puzzles can reward specialized builds, but essential progression cannot require a particular hero or rune. The player is free to ignore lore and still win.

### 2.4 Real consequences, disclosed risks

A risky build can genuinely hurt its owner through HP costs. A bargain may reduce maximum HP or movement. A player may enter an advanced region early or split away from a globally scaled co-op party. These are meaningful choices, not situations that must be normalized into safety.

Costs, changes and failure scope must be disclosed. Temporary transformations cannot secretly remove permanent ownership, and a local event cannot silently penalize uninvolved teammates. Death and defeat matter, but earned permanent currency and legitimate discoveries survive according to the latest economy. There is no repeat-Hunter punishment for succeeding too often.

### 2.5 Horizontal choice, exceptional synergy

Unlockable heroes, weapons, runes and powers introduce different mechanics, not an automatic superior tier. Starter content must remain viable. Every hero can use every weapon, and there is no compulsory tank/healer/damage role. Permanent upgrades provide noticeable but bounded advantages without becoming a required grind before Normal Mode victory.

Choices should be evaluated in context. A short-range weapon may offer hit frequency, a heavy attack may provide force, a weaker raw-DPS tool may gather enemies, and a passive may make another attack substantially more valuable. Equal theoretical DPS is not the universal definition of balance.

### 2.6 Cooperation without forced proximity

Friends can explore different regions or dimensions while sharing the world clock, XP and discovered geography. Their builds and personal discoveries remain individual. Global party scaling makes separation riskier rather than secretly granting solo difficulty elsewhere.

The latest local-reward principle is inclusive: nearby participants qualify even with tiny contributions or late arrival before dealing damage. This avoids last-hit competition while preserving the difference between participating and remaining entirely elsewhere. Shared XP, personal combat ownership and final party victory remain distinct concepts.

### 2.7 Explicit anti-goals

The game is not a tank with many cosmetically different bullets, a hero-locked weapon system, a manual multiweapon shooter, an MMO, a compulsory narrative campaign or a universal random-critical-stat contest. It does not use hidden boss damage caps, mandatory phase HP gates, artificially unavoidable attack patterns, a shrinking Collapse arena or a fixed death deadline.

No automatic respec removes acquired-power commitment. Fusion is not a slot-compression trick. No prepared pool is silently overridden to force discovery. No secret earns full visibility just because an interface could infer its position. No online leaderboard, advanced replay platform, detailed analytics screen or integrated feedback form is required for the initial prototype.

## 3. The player journey and core loops
<a id="gdd-loop"></a>

### 3.1 Before a run: intention without a guaranteed outcome

Preparation gives the player a hero, an independently selected main weapon, two fixed global rune slots and a candidate power pool. The candidate pool defines ordinary opportunities, not starting ownership. Leaving wildcard space permits broader discoveries; filling the pool deliberately avoids forced unknown substitutions. Exact pool size remains open.

Knowledge and permanent ownership are different. A player may know an Evolution clue without having verified its recipe, discover a hero without purchasing it yet, or unlock a power for future reward eligibility without starting a run with it. This separation supports curiosity, planning and progression without promising a predetermined build.

The initial recipe interface is passive Codex and build-panel inspection. Richer informational tracking remains a possible later usability improvement, not an automatic reward-weighting system.

### 3.2 Opening play: readable threats and a build foundation

The opening introduces modest enemy pressure, responsive movement, the main weapon's real delivery and the hero's passive/active identity. Early progression should be accessible enough to establish a direction. It does not automatically grant damage, attack speed or healing simply because a level increases.

The player notices usable terrain, recoverable resources, hints, NPC opportunities and paths into more dangerous regions. A first-time player receives short optional contextual explanations, not a required separate tutorial campaign. A gentler first-run opening transitions into the ordinary game without altering the core boss, reward or Collapse rules.

### 3.3 Mid-run: acquire, improve and transform

Kills, exploration and encounters create XP, resources and power opportunities. Each player chooses between new sources and upgrading existing powers. Acquired powers cannot be removed to reclaim a slot; rank investment and future catalyst availability matter.

Five-rank development includes mechanical milestones, not only stat increments. At Rank 5 plus an authored catalyst, a standard Evolution can become an additional reward option. It is chosen, not automatically granted. Later, two specific acquired Evolutions may form an Advanced Fusion through another reward selection. These transformations retain capacity commitment and may fundamentally change positioning, attack shapes or reactive behavior.

The real-time reward queue allows postponing choices, but choices are frozen when earned. Waiting for a better build state cannot reroll them. The player can continue moving while choosing, making battlefield safety a tactical concern rather than a pause reward.

### 3.4 Optional objectives: worthwhile, not mandatory

Regional bosses grant distinct blessings. Events may offer power selections, discoveries, currency or disclosed tradeoffs. Realms provide substantial side adventures rather than compulsory detours. NPCs can restore resources, alter a weapon temporarily, offer research or open unusual opportunities.

A player is not expected to see every landmark, finish every quest, acquire every Evolution or produce a Fusion in every run. Persistent questlines and knowledge can span attempts. A player's reasons to take a detour include enjoyment, a useful immediate benefit, a permanent discovery or an unusually suitable synergy.

### 3.5 At 25:00: a meaningful strategic fork

World Collapse begins and the normal final gateway becomes available. The map reveals its location and major regional connections, while minor unexplored geography and secrets remain concealed. A compass points toward it without solving the route. The player must physically reach it through an increasingly hostile world.

The player can leave for the Forgotten Creator or deliberately continue. Staying is optional endurance, not ordinary progression guaranteed to remain accessible. A build surviving past 30 minutes is already intended to be significant, but no particular duration is a forced achievement gate. Exponential enemy durability/damage, bounded population/speed/control escalation and increasing Erasure presence challenge a completed build.

Players deserve full rewards for genuinely defeating these threats. Difficulty does not come from reducing Hunter XP after repeated kills. Advanced XP requirements and bounded overflow already limit unlimited player growth, while escalating enemies can eventually exceed ordinary builds.

### 3.6 Final encounter and another run

One living teammate entering the final gateway brings the entire party and fallen bodies into the Unfinished Canvas. Dead teammates do not automatically revive. A short preparation opportunity precedes the battle; the world outside does not continue sending Hunters into the arena.

The Forgotten Creator is an authored final encounter independent of catastrophic tier. It remains a practical alternative to prolonged Collapse survival. Earned powers and blessings remain useful, and an extraordinary build may legitimately produce a fast final victory.

A simple results screen shows outcome, duration, final level, defeats, build, rewards and unlocks. It does not require a combat analytics investigation before another run. Permanent knowledge, currency, unlocks and applicable quest/mastery progress sustain the longer loop; temporary build development resets.

## 4. Build architecture as a player experience
<a id="gdd-builds"></a>

See [GDS preparation and capacity](GDS.md#gds-session), [power catalog](GDS.md#gds-powers) and [Fusion recipes](GDS.md#gds-fusions) for behavior.

### 4.1 Different layers have different jobs

| Layer | Experience it creates |
|---|---|
| Hero | A stable personal rule twist and one manual tactical tool. |
| Main weapon | Core delivery, range, rhythm and spatial relationship with threats. |
| Global runes | Compatible attack properties and a pair-specific interaction. |
| Independent powers | Additional real attack sources and geometries. |
| Passive traits | Specialization in timing, precision, recovery, defense erosion, size or duration. |
| Trigger powers | Meaningful responses to hits, kills, collisions, incoming damage, movement or multiple sources. |
| Rank milestones | Recognizable development within a power's original identity. |
| Standard Evolution | A chosen major transformation with a specific catalyst. |
| Advanced Fusion | An exceptional authored relationship between two evolved mechanics. |
| Blessings / bargains | Run-specific advantages and explicit tradeoffs outside power capacity. |
| Permanent progression | More choices and bounded preparation advantages across runs. |

### 4.2 Ten slots make investment meaningful

Ten distinct acquired powers can coexist from the eighteen-power catalog. Every category shares this capacity; no hidden half-slot taxonomy. Rank upgrades and standard Evolutions retain the original slot. Fusion keeps two component slots, rather than making a large build cheaper. Hero, weapon, runes, blessings and bounded overflow are outside this capacity.

The limit is an initial tuning target, not a requirement to fill every slot before winning. Remaining Rank 1 powers can still provide useful catalysts or functions. The intended Normal Mode victory-ready target is approximately one Fusion with its two evolved ingredients, or three to four standard Evolutions, with flexible other ranks. This describes expected strength, not a hard rule enforced at the gateway.

### 4.3 Interaction freedom is not implicit permission for everything

A power can inherit compatible weapon properties and their costs without becoming a duplicate of the weapon's whole delivery. A physical impact can cause a crystal explosion that retains the player's causal ownership. A DoT can kill and trigger explicitly eligible elimination effects. A slowed enemy can be positioned into a mine, and a reflected projectile can empower that mine's interactions.

However, damaging a wall is not killing a creature, naming an attack "spectral" does not make it hit intangible targets, and a generated effect does not automatically become a new independent attack source. These distinctions make surprising outcomes learnable and fair rather than arbitrary.

### 4.4 Powerful outcomes should remain earned

No universal chain-depth cap removes a valid cascade simply because it is impressive. The bounds belong to actual mechanics: finite statuses/charges, costs, lifetimes, contact intervals, source restrictions, geometry, declared maximum amplification and valid targets. A high-tempo build can produce many legitimate events. A resource-free, zero-time self-replication bug is not the intended power fantasy.

Build inspection and the Codex explain known costs and interactions. New transformations disclose meaningful replacements and drawbacks. A player should be able to understand why a build works, why a shot missed or why a barrier did not heal them, without being forced to memorize implementation terminology.

## 5. Playable heroes and weapon identity
<a id="gdd-playable"></a>

See [GDS heroes](GDS.md#gds-heroes) and [GDS weapons](GDS.md#gds-weapons) for full mechanics and numerical references.

### 5.1 Nine heroes, equal baseline opportunity

Every hero shares the same unmodified core starting statistics. Identity comes from abilities and build choices, not an automatically better unlock-tier health/damage package. Every hero can equip every weapon and remain solo-capable. The names are archetype identities; detailed personal biographies are deferred where source text is missing.

| Hero | Availability | Passive and active identity |
|---|---|---|
| **The Undying** | Starter | Life Harvest accumulates persistent protection through personal kills; Siphon Pulse converts eligible damage into separate temporary protection. |
| **The Acrobat** | Starter | Close Call rewards genuine near misses; Vault provides directional airborne repositioning with explicit attack-height compatibility. |
| **The Conductor** | Starter | Qualifying interactions build Resonance; Harmonic Burst converts charges into linked offense. |
| **The Chronomancer** | Unlockable | Temporal Echo repeats impact-location damage; Time Fracture compresses compatible delayed delivery inside a localized field. |
| **The Gravity Weaver** | Unlockable | Stronger compatible force; Singularity gathers enemies/objects then reverses into an outward wave. |
| **The Summoner** | Unlockable | Weapon hits empower compatible summons; Living Guardian provides independent offense and real physical interception. |
| **The Bloodbound** | Unlockable | Low actual HP strengthens offense; Crimson Offering deliberately spends HP for temporary empowerment. |
| **The Alchemist** | Unlockable | Authored status combinations react; Transmutation propagates compatible states and applies Catalyst Mark. |
| **The Architect** | Unlockable | Construct impacts accumulate offensive Resonance; Living Formation creates three separated physical structures. |

These provide different answers to a dangerous encounter. Undying can manage protection, Acrobat can reposition, Gravity Weaver can rearrange a crowd, Summoner can create a separate attacker/interceptor, and Architect can introduce geometry. None automatically replaces movement skill, and no one is a mandatory healer for co-op.

The six unlocks connect to relevant discovery/mastery: temporal research, real collision control, companion mastery, HP-sacrifice bargains, status combinations and restored construction machinery. Unlocking introduces a new style rather than announcing a superior hero.

### 5.2 Nine weapons, genuine delivery differences

| Weapon | Availability | Core experience |
|---|---|---|
| **Sword** | Starter | Broad mobile frontal melee cleave with no innate status or force. |
| **Bow** | Starter | Single physical arrow, direct nonpredictive aim, no reload and no baseline homing. |
| **Magic Staff** | Starter | Neutral magical sigils placed at current target positions and activated after a delay. |
| **Spear** | Unlockable | Narrow long melee thrust through aligned enemies at consistent base damage. |
| **Warhammer** | Unlockable | Heavy compact impact plus a traveling outward-displacing shockwave. |
| **Twin Daggers** | Unlockable | Rapid independently aimed alternating short-range strikes. |
| **Chakram** | Unlockable | Outbound commitment followed by a return toward the moving player. |
| **Chain Whip** | Unlockable | Extended curved strike, then inward pull of eligible struck enemies. |
| **Arcane Focus** | Unlockable | Sustained fixed-direction magical ray whose origin follows player movement. |

Weapons support distinct range/coverage tradeoffs rather than identical attacks with different icons. Warhammer and Whip provide innate force in opposite directions; Bow emphasizes long-range single-hit delivery; Focus and Spear reward alignment; Chakram turns post-launch movement into offense. The same rune pair can therefore play differently on every weapon.

Range, projectile speed, accuracy, coverage and cadence are separate. Earned predictive aim and guided projectiles do not erase walls, make all shots guaranteed or increase range without the corresponding property. Artisan transformations can temporarily alter a weapon while preserving the underlying build; their exact forms are not finalized.

## 6. Runes, acquired powers and transformations
<a id="gdd-powers"></a>

### 6.1 Five global runes and ten combinations

Runes are selected before the run and apply to compatible owned attacks. They are not randomly equipped from level-up cards and do not require manual assignment to each weapon. Two fixed distinct slots create a deliberate combination choice. Permanent progression expands rune choices, not slot count. Whether the preparation interface must require both slots filled is an explicitly recorded wording gap, not a third-slot opportunity.

| Rune | Identity | Availability |
|---|---|---|
| Bleed | Capped stacks build sustained physical damage through repeated eligible hits. | Starter |
| Lightning | Successful hits distribute electrical damage through finite nearby chains. | Starter |
| Force | Directional displacement creates space and physical interactions. | Starter |
| Flame | Non-stacking Burn grows stronger through sustained active duration. | Unlockable |
| Frost | Immediate movement suppression maintained through refreshed Chill. | Unlockable |

The differing status rhythms matter: Bleed rewards accumulation, Burn rewards persistence, and Chill provides immediate control. Runes do not automatically change the base weapon's damage classification. Statuses and reactions use explicit source/ownership rules, so cooperative proximity does not silently consume a teammate's build resources.

| Pair | Additional interaction | Tactical meaning |
|---|---|---|
| Bleed + Lightning | Thunder Rupture | Trade accumulated Bleed for immediate electrical damage. |
| Bleed + Force | Blood Wake | Movement of Bleeding enemies leaves damaging trails. |
| Lightning + Force | Storm Relay | New enemy positions extend lightning opportunities. |
| Bleed + Flame | Bloodfire | Qualifying kills turn death locations into temporary damage zones. |
| Bleed + Frost | Frozen Wounds | Movement suppression strengthens eligible Bleed damage. |
| Lightning + Flame | Flashfire | Lightning exploits existing Burn with localized explosions. |
| Lightning + Frost | Conductive Rime | Existing Chill supplies additional chaining opportunities. |
| Force + Flame | Cinder Transfer | Genuine collisions propagate bounded Burn. |
| Force + Frost | Glacial Impact | Chilled victims receive additional real-impact damage. |
| Flame + Frost | Thermal Shock | Opposing pre-existing statuses support bounded burst reactions. |

Each pair supplements both base effects rather than replacing them. A reaction's name does not authorize unlimited propagation, status-duration generation or same-hit shortcuts. For exact triggering, consumption and ownership, see [the GDS rune catalog](GDS.md#gds-runes).

### 6.2 Eighteen powers across three equally represented categories

Six independent attacks, six passive modifiers and six triggered effects support distinct investments. A player can emphasize additional attack sources, improve a smaller number of attacks, construct a defensive engine or combine several reaction families. Category is not a separate capacity budget.

| Power | Core identity | Rank 3 / Rank 5 milestone | Standard Evolution choices |
|---|---|---|---|
| Spinning Blade | Continuous real-contact orbit | Twin Blades / Razor Momentum | Blade Tempest / Phantom Circuit |
| Sketch Familiar | Independent graphite projectile companion | Twin Quill / Piercing Quill | Margin Hunter / Ink Squadron |
| Runic Mine | Automatically prepared proximity traps | Twin Runes / Pressure Charge | Runic Web / Seismic Mine |
| Spectral Lance | Straight piercing magical spear | Crescent Lance / Ascending Pierce | Sunderline / Skewer Drive |
| Ricochet Shard | Piercing surface-reflected projectiles | Rebound Momentum / Splinter Reflection | Mirror Trajectory / Siege Shard |
| Arcane Tether | Dynamic contact-damage links | Elastic Conduit / Resonant Current | Triune Circuit / Binding Circuit |
| Battle Tempo | Successful offense accelerates compatible automatic sources | Unbroken Rhythm / Peak Performance | Overdrive Chorus / Impact Cadence |
| Sharpsight | Earned predictive targeting | Adaptive Prediction / Convergent Aim | Guided Flight / Weakpoint Atlas |
| Vital Exchange | Owned offense becomes bounded HP recovery | Survival Instinct / Recovery Surge | Crimson Reservoir / Sanguine Fury |
| Fracture | Progressive physical/magical defense erosion | Deepening Cracks / Total Exposure | Shatter Cascade / Sunder Pulse |
| Spatial Reach | Contextual real geometry amplification | Adaptive Coverage / Outer Edge | Kinetic Expansion / Expanding Domain |
| Lingering Essence | Contextual effect duration | Enduring Potency / Final Resonance | Eternal Ember / Residual Echo |
| Death Bloom | Growing kill-triggered explosion cascades | Expanding Bloom / Bloom Convergence | Bloom Reserve / Gravegarden |
| Echo Strike | Delayed genuine attack copies | Resonant Fidelity / Adaptive Echo | Endless Reverberation / Mirror Array |
| Collision Burst | Shockwaves from genuine forced impacts | Impact Velocity / Compression Burst | Momentum Relay / Aftershock Field |
| Reprisal Pulse | Counterattack after hostile HP/barrier damage | Proportional Wrath / Expanding Wrath | Mirror Guard / Vengeful Halo |
| Momentum Charge | Voluntary movement fuels an extra attack | Momentum Reserve / Flow State | Kinetic Breaker / Crosscurrent |
| Converging Strikes | Distinct owned attack sources combine | Convergent Shock / Third Vector | Unified Assault / Convergence Circuit |

Every power has five ranks. The 36 named milestones create visible behavior changes before Evolution. Their significance is not just that a number becomes larger: the familiar gains multiple piercing darts, mine placement doubles then rewards preparation, the lance widens then builds penetration momentum, or a counterattack gains proportional damage and larger repeated-hit coverage.

### 6.3 Why two Evolution paths per power matter

A standard Evolution requires its base at Rank 5 and an authored catalyst, then a reward choice. The two forms are mutually exclusive for that base within a run. Catalysts remain available as independent mechanics and are not consumed by standard Evolution.

The paired identities should give a genuine decision. Blade Tempest concentrates mobile orbital offense; Phantom Circuit leaves stationary afterimages. Margin Hunter improves one companion's position and precision; Ink Squadron distributes multiple attack origins. Sunderline leaves a magical path; Skewer Drive carries enemies into physical danger. Mirror Guard creates protection through retaliation; Vengeful Halo creates continuing contact offense.

Neither path is a universal next-tier replacement for a different power. Players should choose according to the run's geometry, other mechanics, desired playstyle and actual opportunities. The GDS lists each exact recipe, inheritance and relevant restrictions so the descriptions remain mechanically testable.

### 6.4 Six Advanced Fusions

| Fusion | Components | Distinct new relationship |
|---|---|---|
| **Seismic Arsenal** | Seismic Mine + Siege Shard | Rebound shockwaves detonate armed mines; mine waves charge real subsequent rebounds. |
| **Infinite Domain** | Triune Circuit + Expanding Domain | Expanding perimeter links create periodic interior damage only when real enclosure is valid. |
| **Thermal Equilibrium** | Eternal Ember + Binding Circuit | Thermal Shock conducts along links, while eligible heat pulses transfer bounded Burn to Chilled enemies. |
| **Relentless Chorus** | Blade Tempest + Unified Assault | Orbital convergence charges a coordinated strike released by another independent source. |
| **Grave Resonance** | Gravegarden + Residual Echo | Residual damage marks enemies for independently earned empowered blossom fields. |
| **Sanguine Aegis** | Crimson Reservoir + Mirror Guard | Stored healing fortifies barriers; genuine hostile absorption fuels a depletion retaliation. |

Fusion is not merely the sum of every previous positive property. Recipes explicitly preserve, combine, transform or replace mechanics, with meaningful changes disclosed. It retains both slots, no recursive higher-Fusion tier and no automatic resource/cooldown reset. Multiple disjoint Fusions can coexist when their rune requirements are jointly possible.

This matters for actual build planning: Seismic Arsenal requires Force, while Thermal Equilibrium requires Flame and Frost. Those exact recipes cannot coexist in an ordinary two-rune build even though their base components are different. Infinite Domain and Thermal Equilibrium cannot coexist because both consume Arcane Tether. Constraints should be understandable, not hidden after investment.

### 6.5 Discovery has different levels of certainty

Ordinary power knowledge can begin when a player sees content; permanent ownership follows applicable unlock requirements. Standard Evolution verification comes from actual acquisition. Fusion knowledge progresses from Unknown through rumor, partial identification and identified recipe to experimentally verified acquisition. A player may discover a Fusion spontaneously without first completing all research stages.

Information should help experimentation without granting the build for free. The Archivist and world clues provide useful connections; the Codex preserves discoveries. Players who ignore this narrative layer still have mechanically valid opportunities through rewards.

## 7. The world and exploration experience
<a id="gdd-world"></a>

See [GDS world rules](GDS.md#gds-world) for exact traversal, discovery and transition behavior.

### 7.1 Three cores with organic transitions

The **Primeval Wilds** express natural growth and hunting pressure: forests, grassland, giant roots, caves, ravines and reclaimed ruins. The **Runic Expanse** expresses ordered machinery and forgotten civilization: arcane cities, foundries, conduits, observatories and geometric structures. The **Forgotten Lands** express memory, incomplete death and lost inhabitants: castles, burial spaces, silent villages, shrines and spectral remnants.

Their borders contain mixed terrain and contested landmarks rather than hard isolated levels. Physical routes, alternate entrances and hidden shortcuts encourage learning geography. Returning to an earlier region does not reset time, enemies or catastrophic pressure. Later regional baselines are moderately stronger, but there is no compulsory route or level gate.

### 7.2 Signature anchors and variable destinations

Each region guarantees one recognizable anchor while selecting other landmarks variably. Guaranteeing an anchor gives a region identity; procedural placement/interiors and variable reward content prevent it becoming a solved checklist every run.

| Region | Guaranteed landmark | Variable landmarks |
|---|---|---|
| Primeval Wilds | Ancient Worldtree | Beast's Den; Overgrown Sanctuary; Whispering Falls |
| Runic Expanse | Ancient Foundry | Runic Archive; Silent Observatory; Sealed Vault |
| Forgotten Lands | Fallen Citadel | Endless Catacombs; Abandoned Village; Veiled Shrine |

The Worldtree offers roots and concealed natural spaces; the Foundry gives machinery meaningful exploration functions; the Citadel provides substantial architectural exploration. Other sites connect combat, knowledge, mechanisms, hidden content or optional challenges. A landmark is not merely scenery or a guaranteed identical chest.

### 7.3 Layered discovery without automatic secret markers

Observation can reveal a crack, unusual vegetation or sounds behind a structure. Experimentation can test a mechanism or break a weakened wall. Knowledge can connect an inscription, NPC clue and a place encountered in another region. Emergent combat can accidentally expose a passage when an enemy breaks compatible terrain.

The world does not automatically mark undiscovered entrances. Pathfinder information gives approximate geography and environmental clues, not a solved path. Fog-of-war knowledge is shared in co-op, but secret rewards and personal discoveries retain eligibility rules. The map reveals the normal gateway and major connections at Collapse without revealing every local route or optional secret.

### 7.4 Four independent optional realms

The **Inverted Archive** supports strange architecture, spatial puzzles and magical knowledge. The **Silent Garden** supports restorative mystery, inhabitants and bargains. The **Fractured Beyond** supports high-risk spatial exploration and powerful anomalies. The **Hall of Echoes** supports specialized battles and mastery.

Each is an interconnected optional adventure with valid accessible exits, not a trap that requires completing a mandatory trial to leave. Teammates can enter independently while shared time and XP continue. Their identities can support exceptional discoveries and some content unlocks, but no run needs to visit all four.

The world clock does not pause inside a realm. Collapse affects them too, with valid exits/rescue routes preserved. They cannot become indefinite safe refuges from the endurance challenge.

### 7.5 A selectively reactive environment

Destructible containers, barricades, pillars, crystals, machinery and caches provide loot, routes and combat opportunities. Movable crates, boulders, broken constructs, sarcophagi, volatile vessels and fallen pillars can become physical participants when genuinely displaced. Hazards include spikes, vents, toxic ground, energy barriers, gravity wells, collapses and cursed areas.

The important principle is universal compatibility: a regional enemy or Hunter is not immune merely because a hazard was placed in its region. Real player-caused chains can preserve causal ownership, while independent faction damage remains theirs. A stationary object is not an infinite impact source, and destroying an object is not killing a creature.

Interconnected levers, plates, conduits, sequences, restoration devices, keystones, energy nodes and resonance mechanisms reuse combat and physical rules. A puzzle can support several valid solutions. Mandatory progression stays solo-capable and build-independent; specialized optional solutions remain valuable.

## 8. Enemies, factions and encounter diversity
<a id="gdd-enemies"></a>

### 8.1 Different ecosystems, different movement problems

The three regional factions each have six ordinary enemies, corresponding elites and a boss. Their purpose is to create distinct tactical environments rather than reskin one set of combat statistics.

| Faction | Ordinary roster | Elite roster |
|---|---|---|
| Wildborn | Fangling, Prowler, Thornback, Ironhide, Howler, Burrowmaw | Razorfang, Dreadstalker, Quillstorm, Siegebreaker, Alpha Howler, Earthshaker |
| Runebound | Rune Sentinel, Bulwark, Rune Artillery, Stone Colossus, Rune Mender, Arc Conduit | Rune Praetorian, Aegis Bastion, Siege Oracle, Worldbreaker, Rune Architect, Nexus Conduit |
| Hollow Legion | Hollow Soldier, Wraith, Grave Archer, Bone Reaver, Soul Weaver, Hexbinder | Deathguard, Phantom Reaper, Deathmark Archer, Dread Executioner, Grave Sovereign, Maledictor |

Wildborn pressure movement through pack approaches, committed pounces, projectile gaps, charges, buffs and visible underground pursuit. Runebound make formation, cover, support targeting and space between linked enemies important. Hollow Legion combine persistent pursuit, materialization windows, curses, low-HP danger and limited resurrection.

Elites add recognizable advanced behavior: successive attacks, prediction, delayed eruptions, coordinated hunting, projected shields, multiple repair links, stronger curse combinations or area rituals. They do not gain untelegraphed guaranteed hits or universal immunity simply because they are elites.

### 8.2 Three optional regional bosses

**Primal Sovereign** is a mobile antlered apex predator combining broad melee, committed pounce, ground shockwave, bite and adaptive pack command. Its phases evolve from Territorial Hunt to Apex Dominance and Primal Fury. Defeating it ends its pack/aggression influence and grants **Primal Instinct**, rewarding genuine evasion with temporary speed and compatible attack frequency.

**Eternal Architect** is a deliberate construct commander combining bombardment, branching rupture, rotating beams, directional Aegis, dynamic energy networks and interruptible allied repair. Guardian, Dominion and Cataclysm Protocols emphasize increasingly complex arrangements. Defeating it removes its regional enhancement and grants **Structural Insight**, applicable physical/magical penetration without immunity or shield bypass.

**Eternal Reaper** is a spectral scythe threat combining physical sweeps, traversal, actual-damage lifesteal, low-HP execution pressure, ranged crescents and earned Soul-charge eruption. Soul Pursuit, Insatiable Hunger and Final Reckoning develop its aggression. Defeating it removes its regional enhancement and grants the player's **Soul Harvest** recovery blessing.

Boss victory never exterminates the whole faction. Existing enemies retain their ordinary abilities. All three blessings can coexist during the run, without consuming power slots. Bosses receive full overworld catastrophe scaling if left alive, preserving a strategic reason to pursue them early.

### 8.3 Invaders are exceptional individuals

The owner's correction rejected a conventional six-role Unravelling faction. The Unravelling instead consists of one independent, self-sufficient, versatile invader archetype. One is much stronger than an ordinary elite; two may credibly challenge a regional boss through actual combat. It needs no healer/support squad or territory to function.

Its extended fragment melee, warned relocation, distorted projectiles, multi-direction ruptures and pull-then-explode ability threaten different distances and groups. It roams, repositions and may disengage without automatically healing. **Fractured Power** gives a qualifying defeat substantial ordinary rewards and one extra power choice.

The **Erasure** is an even stronger catastrophe-only predator. It brings a huge sweep, singularity, branching World Fracture, warned arrival, distorted storm and committed sustained Annihilation Beam. All are available immediately; it has no personal phase progression. It remains defeatable and has no HP bar. **Catastrophe Essence** provides exceptional rewards and bounded stacking run-long offensive strength.

The latest approved pursuit rule gives both types priority toward detected living players while retaining faction combat. Earlier no-player-priority or pure dominant-target interpretations are superseded. Detection is not omniscience, and players can use terrain and mobility. Independent invaders may still meet a regional boss or temporarily fight other threats, creating a living battlefield rather than a guaranteed scripted event.

### 8.4 Fairness does not mean low difficulty

Enemy telegraphs, commitment and recovery are readable, and delivered damage follows actual geometry. Fully burrowed or intangible states require explicit delivery compatibility, not simply a magical damage label. Every starting build retains exposure windows against ordinary specialists. Heavy resistance can reduce force without preventing otherwise compatible damage.

These constraints allow extreme danger without arbitrary outcomes. A highly scaled hit can be lethal, but that is different from making attacks follow the player perfectly or removing every escape path. Defenses and crowd control retain useful identities even at advanced catastrophe tiers.

## 9. The final encounter and the meaning of victory
<a id="gdd-final"></a>

**Authority:** V33.1-V33.8; V39.11; V40.18.11. Detailed behavior: [GDS - Forgotten Creator](GDS.md#gds-final-boss).

### 9.1 The Forgotten Creator

The final boss is an ancient creator-like entity capable of shaping reality, not simply a larger regional creature. Its continuous adaptive encounter combines weapons forged from reality, faction-inspired attacks, independent manifestations and localized physical transformations. The fight should communicate mastery over the laws the player has spent the run learning to combine.

| Ability | Intended encounter experience |
|---|---|
| Creation's Edge | Successive weapon shapes test close-range spacing and directional evasion. |
| Genesis Rupture | Branching fractures and delayed eruptions test path recognition. |
| Celestial Mechanism | Rotating beams and committed projectiles test movement through changing gaps. |
| Essence Reclamation | A warned, geometrically delivered life-stealing pulse rewards avoiding actual contact. |
| Echoes of Creation | Temporary attack origins require awareness beyond the boss's body. |
| Reality Rewrite | Temporary structures and hazardous ground change local tactics. |
| Genesis Cataclysm | An extended combination of independently warned patterns creates the climactic spatial challenge. |

The four **Primordial Manifestations** express Instinct, Order, Mortality and Chaos. Each is an independent combat entity with its own HP and attacks, roughly in the powerful-regional-elite category. They summarize the world's combat languages: pursuit, protection, spectral pressure and spatial manipulation. Killing them reduces pressure; it never unlocks permission to hurt the Creator.

**Echoes of Creation and Primordial Manifestations are different.** Echoes are temporary attack sources, whereas manifestations are independently fighting creatures. Neither creates a mandatory secondary objective or an invulnerability gate.

### 9.2 The Unfinished Canvas

The arena begins as a vast open white-paper battlefield bordered by incomplete graphite scenery. This emptiness makes the Creator's act of shaping the environment legible. Living Geometry creates temporary walls, pillars, barriers and hazardous ground with real collision, rather than merely drawing decorative danger circles.

The same geometry can help or harm either side. A player can use a pillar as cover, knock an enemy into a new wall or exploit a reflected projectile path. Structures cannot appear through creatures to cause unavoidable damage, seal every escape route or erase the player's build. Attacks and movement respect their explicit compatibility.

Final-gateway entry brings the participating party, including revivable corpses and members in optional realms, into the final encounter. The transfer is irreversible. Overworld enemies do not enter. A short preparation window permits immediate preparation without requiring every teammate to be alive before combat. Precise timings remain balance details.

### 9.3 The Cycle of Creation

| Phase | Experience emphasis |
|---|---|
| Genesis | Learn the fundamental weapon, rupture and projectile vocabulary. |
| Manifestation | Manage independent threats and distributed attack origins. |
| Reconstruction | Reassess positions as physical geometry and magical attacks combine. |
| Unmaking | Face aggressive complete-repertoire combinations and Genesis Cataclysm. |

These are HP-based tactical emphases, not four mandatory health bars. Healing cannot reset achieved phases. Existing manifestations and structures do not automatically disappear between phases. The boss has no forced invulnerability transition, minimum fight length, damage cap or obligation to demonstrate every attack before dying.

### 9.4 Victory is an alternative to endurance

The Creator does not inherit overworld time or catastrophic-tier multipliers. Its authored difficulty can be modified by the initial party size and selected challenges, not by how long the player waited in the collapsing world or how strong their build became.

This separation is deliberate. A player whose build cannot sustain further catastrophe has a reason to seek final victory rather than an ever-receding objective. A player who legitimately survives extreme tiers may arrive overwhelmingly strong and defeat the Creator immediately. That is an earned outcome.

**Legacy of Creation** combines repeatable victory currency, a completion bonus, first-victory recognition and challenge/content access, and individually eligible accomplishment rewards. Victory includes eligible dead teammates. If the final living player and Creator die within the same completed simultaneous combat group, victory takes precedence; the game does not wait for later projectiles or future ticks to invent a post-wipe victory.

In the fiction, victory preserves this manifestation of the world. Subsequent journeys do not revoke that accomplishment. Narrative discovery is optional, and no hidden true ending is required to make the victory valid.

## 10. Cooperative play without compulsory roles
<a id="gdd-coop"></a>

**Authority:** Earlier shared-world/revival decisions in M15; V34.8; V39.11-V39.12; V40.10; V40.18.16; V42.2. Detailed rules: [GDS - cooperative play](GDS.md#gds-coop).

### 10.1 Shared world, individual builds

Cooperation means occupying one persistent run with shared time, shared eligible XP and applicable exploration knowledge, not controlling an identical build. Each player chooses their own hero, weapon and runes; earns and selects their own power choices; maintains their own combat ownership; and spends their own Trade Shards.

Players may separate across ordinary regions or special realms. They can explore different opportunities and reunite, but separation does not lower encounter difficulty. **Global Party Scaling is locked to the initial party size.** A lone explorer in a larger party faces that party's scaling; death or temporary disconnection does not weaken the surviving enemies. The maximum supported party size remains an open product detail; the four-player balance examples are not a newly imposed cap.

There are no compulsory tank, healer or damage-dealer roles. Protective heroes, support interactions and varied builds should help cooperation, while every hero remains independently viable in solo play. Beneficial cooperation is not automatically compensated by increasing enemies to match a strong party's damage output.

### 10.2 Participation is inclusive, not last-hit competition

The latest approved encounter policy gives nearby participating party members event, regional-boss, quest and similar encounter rewards even when their contribution is tiny. Late arrival before resolution can count without first dealing damage. Evasion, support and control are legitimate forms of participation. A remote player who did not participate does not automatically receive that encounter reward.

This is separate from global shared XP and from final-boss party victory. It is also separate from personal mastery: a teammate cannot automatically discover an Evolution for someone who never acquired it, or complete another player's individual weapon technique by dealing the killing blow.

Combat attribution still needs one legitimate damage or elimination owner for personal effects such as Life Harvest or Death Bloom. An ally's entitlement to encounter loot is not permission to duplicate that ally's kill-trigger reactions. Exact proximity boundaries, departed participants and disconnection/death edge cases are deliberately open.

### 10.3 Revival should create rescue decisions

A defeated player leaves a body at its actual location. Teammates need physical access, including entering the correct special realm, to revive them. The established design separates a revival eligibility wait from the active interaction channel; repeated deaths increase the wait within a cap. Earned channel progress is retained under the approved rules, and multiple rescuers help with diminishing contribution rather than producing unlimited instant revival.

Revival returns partial HP and temporary protection. It is not a full resource reset or a way to make expensive HP-cost attacks free. A limited safe recovery window should make the rescue meaningful without removing subsequent risk. Exact durations, caps and protection details follow the specification's open-detail register where the recoverable record is incomplete.

Spectating should keep the defeated player oriented around the party or body, not reveal unexplored secrets. Dead players may retain eligible shared progression and inspect pending choices. Ordinary healing does not revive them.

### 10.4 A defeated build leaves consequences, not a second active player

Committed projectiles, statuses, mines and damaging fields can finish their valid lifecycles while the run remains active. Their legitimate reactions and ownership survive. A lingering Burn can kill an enemy and produce a Death Bloom even after its owner dies.

By contrast, ordinary automatic attacks and autonomous companion attacks stop while their owner is dead. Permanent companions become dormant; temporary effects keep aging. Reviving does not recreate expired fields, duplicate companions or refill cooldowns. When the whole party is defeated, only the current immediate causal combat group finishes; there is no indefinite waiting for delayed effects.

### 10.5 Connection and session clarity

A temporary disconnect is not free protection. The character remains vulnerable under the established grace rules rather than receiving an autonomous fighting AI. Reconnection, host loss, late joining and final timeout details are documented as open where the available historical contract is not complete. This design pair does not prescribe networking topology or convert those unanswered product questions into technical assumptions.

## 11. Inhabitants, events and meaningful optional work
<a id="gdd-inhabitants"></a>

**Authority:** V34.5-V34.6; V36.1-V36.14; V41.8; V42.2. Detailed services and catalogs: [GDS - NPCs](GDS.md#gds-npcs), [events and quests](GDS.md#gds-events).

### 11.1 Recurring people in a variable world

The six principal NPC identities persist across manifestations and can remember important discoveries and encounters. Procedural inhabitants supplement them; the world is not restricted to six physical service points. Availability and location vary by run.

| Character | Personality and motivation | Gameplay purpose |
|---|---|---|
| Wandering Merchant | Witty, opportunistic and dependable; seeks discoveries unavailable anywhere else. | Limited run-specific purchases and unusual opportunities. |
| Archivist | Patient and meticulous; preserves knowledge from threatened civilizations. | Research, history, identification and progressive discovery clues. |
| Artisan | Inventive, eccentric and demanding; wants to create beyond the Creator's imagination. | Bounded enhancements and temporary alternative weapon forms. |
| Pathfinder | Practical and adventurous; investigates the boundaries of creation. | Approximate cartography, danger reports and exploration requests. |
| Restorer | Compassionate and resolute; repairs existing life without replacing its identity. | Limited healing, purification, protection and compatible resource services. |
| Nameless Stranger | Enigmatic and calculating; understands forbidden exchanges, with partly ambiguous motives. | Disclosed covenants, unusual challenges and rare knowledge. |

They inhabit appropriate contexts. Merchants travel between temporary camps, Archivists examine ruins, Artisans work at workshops, Pathfinders explore routes and Restorers occupy shrines or temporary sanctuaries. Mobile characters do not relocate during active interactions. Previously known locations can become outdated without revealing their entire route through unexplored terrain.

Friendly NPCs are protected from damage and hostile targeting. Their presence does not protect the player. Dialogue and service panels remain real time, so the player must manage their own surroundings. They remain usable amid nearby enemies and during Collapse under the approved interaction rules.

### 11.2 Services should support rather than replace exploration

Merchants offer limited restoration, protection, empowerment, additional power selections, eligible rank improvements, discoveries and exceptional offers. Ordinary services have limited shared stock; individual build opportunities retain personal purchase eligibility. Contextual inventories can depend on identity, region, time and rarity. Reopening a panel does not reroll it, relocation does not automatically replenish it, and rare progression purchases remain finite.

The Archivist's seven service categories develop knowledge through clues and experiments rather than reveal every recipe immediately. Knowing a secret's concept is different from finding its procedural location, owning its unlock or acquiring its power during a run.

The Pathfinder offers environmental descriptions and approximate search information. Fog of exploration remains, secret entrances require discovery, and danger reports are knowledge rather than live omniscient tracking. No fast travel is introduced.

The Artisan can reinforce, refine, attune, reshape, temporarily transform and exceptionally enhance weapons. The underlying build survives temporary transformations; compatible rune and power effects continue. Only one weapon transformation is active at a time. Specific transformation forms remain open: previously suggested Greatblade, Volley and Constellation examples were not finalized as a required catalog.

The Restorer's seven approved services cover HP, resources, barriers, eligible purification, compatible cooldown reduction, received-healing bonuses and mitigation. They cannot revive a teammate directly, erase a voluntarily accepted bargain or create invulnerability. Limited stock is consumed only for a valid benefit.

### 11.3 Living events

| Event archetype | Player-facing purpose |
|---|---|
| Contested Treasure | Decide whether to fight, exploit faction conflict or seize an opportunity. |
| Ancient Trial | Voluntarily test a build against a specialized challenge. |
| Forgotten Mechanism | Investigate interconnected environmental machinery. |
| Wandering Stranger | Discover a character, rumor, trade or quest that may not recur next run. |
| Forbidden Bargain | Choose a powerful benefit with a clearly explained cost. |
| Reality Anomaly | Investigate unusual spatial conditions and rare possibilities. |

Some events develop without the player. Others require explicit activation. Their existence should support the impression of a living world, not force everyone through scripted objectives. Ongoing events and mechanisms remain relevant during the Collapse, but new optional events do not begin after 25:00. Hunter arrivals and Collapse hazard generation are not optional-event starts and continue under their own rules.

### 11.4 Bargains are decisions, not concealed punishments

Recognizable authored covenants coexist with procedurally selected compatible combinations. The eight approved archetypes are Blood Offering, Glass Covenant, Burden of Strength, Forbidden Knowledge, Borrowed Time, Unstable Ascension, Fractured Passage and Creator's Mark.

Their purpose is to make an apparent disadvantage attractive to a particular build. A player with strong recovery might sacrifice HP; a protected low-HP build might accept less maximum health. The game must explain benefit, cost, duration and relevant restrictions before acceptance. There is no undisclosed betrayal, automatic cost on teammates or loss of permanent account ownership.

The bargain system does not bypass acquired-power capacity or Evolution requirements. A nominal Evolution opportunity still requires a valid recipe. Ordinary purification cannot erase accepted disadvantages. HP costs cannot be paid by barriers and may be lethal under their approved rules.

### 11.5 Quest variety without compulsory errands

The ten approved quest archetypes cover Exploration, Hunting, Investigation, Restoration, Combat Mastery, Build Discovery, Faction Conflict, Realm Expedition, Character Journey and Catastrophe Hunt.

Authored signature quests, contextual objectives based on genuinely available world content and persistent multi-run questlines coexist. Discovered compatible objectives can progress simultaneously; limited HUD pins are for visibility rather than exclusive activation. NPC contracts and sacrifices require acceptance, while organic discoveries may enter the journal automatically.

Ordinary completion rewards are automatic where appropriate. Returning to an NPC is required only when narratively or mechanically relevant. Power rewards join the non-blocking queue. Persistent committed progress survives defeat; unfinished run-specific tasks do not carry an imaginary copy of the old procedural world into a new run.

Repeatable objectives offer currency, XP, Trade Shards and compatible run benefits. Exceptional accomplishments can offer rare rewards or power opportunities. Unique discoveries open permanent ownership opportunities, and mastery can grant achievements or cosmetics. No quest is mandatory for defeating the Creator, and challenge modifiers do not gate exclusive gameplay content.

## 12. Progression, economy and replay motivation
<a id="gdd-progression"></a>

**Authority:** V37 discovery decisions; V38 knowledge decisions; V40.3-V40.17. Detailed rules: [GDS - progression](GDS.md#gds-progression), [XP](GDS.md#gds-xp), [challenges](GDS.md#gds-challenges).

### 12.1 Three currencies, different purposes

| Currency | Purpose | End-of-run treatment |
|---|---|---|
| Common currency | Permanent upgrades and ownership unlocks | Earned currency retained on victory and defeat. |
| Rare/special currency | Appropriately valuable permanent progression | Earned currency retained on victory and defeat; victory can add more. |
| Trade Shards | Personal in-run merchant and compatible service spending | Starts at zero and expires at run end. |

The latest approved economy rewards actual accomplishments throughout a run. Time alone produces no currency multiplier. Someone who achieves exceptional endurance and eventually loses can earn more than someone who completes a short victory. The winner still receives substantial additional completion benefits.

Repeated genuine Hunter kills retain full authored XP, currency and exceptional rewards. The design explicitly rejected anti-farming reductions based on kill count. Repeated resurrection of the same enemy remains different: it preserves one progression entitlement while permitting qualifying kill reactions on new combat lives.

### 12.2 Discovery before ownership

Expanded heroes, weapons, runes and powers generally follow **Discovery and Permanent Unlock**. A related accomplishment or exploration discovery makes the content available to purchase using permanent currency. Explicit exceptional accomplishments may grant direct ownership. Discovery persists after defeat; purchasing does not insert the content into an already active run.

Requirements must be achievable through previously available content, with no circular dependencies. Unlocking a power admits it to eligible future candidate pools; it does not grant its Rank 5 version or reveal all Evolution recipes. Knowledge and ownership are separate states.

This system ties mastery to mechanical identity. Piercing mastery discovers Spear, environmental impacts discover Warhammer, companion mastery discovers Summoner, and restoring the Foundry's furnace discovers Flame. The exact thresholds and prices remain tuning, not reasons to invent additional mandatory objectives.

### 12.3 Permanent benefits should matter without becoming an admission fee

Permanent upgrades provide meaningful but bounded advantages. The approved initial direction is approximately 15-25% total improvement per supported statistic, not a guarantee that every branch uses the same percentage. Supported branches include maximum HP, damage, physical/magical defense, movement, automatic attack frequency and manual cooldown recovery.

Costs increase progressively while per-rank benefits within each branch remain consistent. Players choose between unlocking different experiences and strengthening existing foundations. Finite rank caps prevent endless account power growth. No permanent purchase adds acquired-power slots, rune slots, higher ordinary power ranks or shortcuts around Evolution and Fusion requirements.

Normal Mode remains completable on a fresh account. Enemy strength does not secretly adapt to account upgrades. The improvements are real, but they do not guarantee extended Collapse survival.

### 12.4 Run progression and the long tail

Early XP requirements use progressive growth; advanced requirements transition to exponential growth by **player level**, not time. A strong early player reaches demanding requirements early, while a slower player is not suddenly penalized solely because the world clock reached 25:00.

Every level provides a reward choice, with excess XP carried forward and multiple earned choices queued. Contextual distribution balances new acquisitions with improvements to owned powers. It does not favor specific recipes, change frozen rewards or automatically complete a tracked plan.

When ordinary acquisitions and ranks are exhausted, bounded overflow offers diminishing, individually limited run-long stat improvements alongside utility. All reward-selection sources share those limits, including Hunter choices. After the limits are exhausted, further levels can still provide utility. The level number has no hard cap, but it is not an unlimited source of automatic damage.

### 12.5 Challenge and mastery motivation

Normal Mode is the primary balance reference. Optional challenges are chosen before the run, shared by the party and cannot be changed mid-run. Their reward bonuses are difficulty-weighted and bounded, including explicitly authored demanding combinations. They do not automatically increase individual enemy XP or give players extra combat strength.

First victory opens foundational challenges. Additional specialized challenges unlock through relevant accomplishments rather than a mandatory ladder. No hero, weapon, rune, power or permanent gameplay upgrade requires challenge-exclusive progression. Challenge-exclusive recognition is limited to records, achievements and cosmetics.

Contextual personal mastery records distinguish hero, weapon, build, party size and challenge configuration. They may preserve remarkable victory, endurance, combat, Hunter, exploration and cooperation accomplishments with the associated build. A public leaderboard or competitive ranking is not required.

The **post-run screen remains simple**. The existence of permanent records is not approval of a detailed mandatory analytics interface, replay system or feedback submission platform.

## 13. Difficulty and the optional catastrophic battlefield
<a id="gdd-balance"></a>

**Authority:** V40.1-V40.19.8, especially the user's replacement of Hunter reward penalties; V42 full-content scope. Formula authority: [GDS - scaling](GDS.md#gds-scaling).

### 13.1 Viability first, not parity at all costs

A coherent ordinary build can win Normal Mode. Exceptional synergy can produce dramatically greater power, including almost instant boss kills. The balance objective is neither universal equal DPS nor a game in which most choices fail unless the player finds a jackpot recipe.

Every hero and weapon pairing should support viable builds. Starter choices remain useful after all unlocks. Ordinary Evolution builds remain valid without Advanced Fusion, and account upgrades are not required for victory. A weak or incoherent build may fail; viability does not mean every possible collection succeeds.

When a problem appears, first distinguish a valid powerful combination from a defect. The preferred response is to correct unintended behavior, improve ineffective alternatives, improve encounter variety, reconsider progression pacing, then adjust necessary values or specific interactions. Do not automatically nerf a dramatic but legitimate result.

Actual defects include duplicate rewards, unintended infinite conversion, source-identity multiplication, unavoidable attacks caused by broken warnings, permanently inaccessible essential routes and mechanics that make meaningful alternatives consistently nonviable. No design pillar protects an exploit simply because it produces large numbers.

### 13.2 Early development and late pressure

Typical successful runs target 25-40 minutes, but this is not a minimum or maximum. Early victories remain possible through legitimate final-access opportunities. Optional exploration can extend a run, and exceptional players can remain in the Collapse indefinitely in principle.

The first 25 minutes allow build development with accelerating pressure. The approved initial quadratic model reaches 3x maximum HP and 2x enemy damage immediately before the Collapse. These are time multipliers relative to the same archetype's starting baseline, not replacements for distinct regional or enemy identities.

At 25:00, Tier 1 begins. A new catastrophic tier arrives every two minutes. Initial Normal Mode targets compound maximum HP by 40% and damage by 25% per tier. The pre-Collapse curve stops rather than continuing to multiply independently after the transition.

Existing enemies gain maximum HP and new offensive statistics without receiving free current HP. Newly spawned enemies begin at their latest-tier full HP. Committed attacks keep their snapshots, so a warned projectile does not secretly become stronger halfway to the player. Real healing can subsequently restore an enemy toward its increased maximum.

### 13.3 Why the Collapse is not accessible to every build

The Collapse is optional endurance for sufficiently powerful builds and capable players. The game is not required to provide enough leveling or healing to rescue a build that has fallen behind. The final gateway remains the alternative path to completion.

Difficulty comes from increasingly powerful enemies and hazards, not diminished rewards. Population capacity and reinforcement frequency rise within limits. Hunter composition shifts toward Erasure. Existing Unravelling are not erased to make that transition. Natural environmental damage escalates while warning duration, essential connectivity and usable gaps remain protected.

Enemy movement and attack frequency rise only within archetype-specific limits. Control resistance can increase selectively, but mass and ordinary physical/magical defense do not automatically rise with catastrophe. New immunities cannot appear solely to invalidate a control build. Enemy projectile speed and aim do not automatically become perfect.

These separations are essential. Unbounded HP and damage pressure can coexist with finite population, readable attacks and meaningful evasion. The design does not rely on a shrinking map, omniscient pursuers, automatic defeat timer or ability deletion.

### 13.4 Geography and cooperation change risk

The initial regional multipliers are moderate: Primeval Wilds 1x HP/1x damage; Runic Expanse 1.25x/1.15x; Forgotten Lands 1.5x/1.3x. Regions remain accessible without level gates or a compulsory sequence. Enemies retain their assigned regional multiplier across boundaries, while universal Hunters use their own baseline.

Co-op applies global linear party-size modifiers to durability, damage, population allowance and reinforcement frequency. The initial targets are +50% HP, +10% damage and +25% population/frequency per additional player. Their purpose is to challenge cooperation without cancelling the benefits of coordinated builds and revival. A separated player accepts the increased risk voluntarily.

These selected coefficients are initial balance targets, not validated claims about how long players will survive. Spawn density, encounter design, resource supply and achievable build power must be evaluated together. The document does not claim that a particular time necessarily proves mastery before playtesting exists.

### 13.5 Numerical delegation without mechanical drift

The owner asked to stop deciding every numerical detail individually. Remaining coefficients, prices, durations, spawn rates, rank increments and limits may receive reasonable provisional tuning, then change through gameplay and player feedback.

That delegation is not permission to change a mechanic silently. Replacing a real projectile with guaranteed damage, consuming statuses that were approved to persist, making Fusion compulsory or changing personal rewards into global rewards is a design revision, not numerical balancing. The GDS separates approved targets, unassigned tuning and actual open design questions.

## 14. Art, animation, audio and presentation identity
<a id="gdd-presentation"></a>

**Authority:** Visible V22-V23 decisions and earlier inspected presentation notes. Functional requirements: [GDS - presentation](GDS.md#gds-presentation).

### 14.1 An expressive graphite fantasy

The world is predominantly monochrome graphite on white paper. Forms should feel hand-drawn rather than like generic polished vector assets placed on a paper texture. Restrained colored-pencil or watercolor accents distinguish magic, elements and meaningful interactions without turning the battlefield into a fully saturated visual field.

The style accommodates natural creatures, geometric constructs, undead silhouettes, incomplete invading entities and the Creator's unfinished arena within one visual language. Fragmentation, erasure, disconnected strokes and incomplete geometry express world instability. They should not conceal collision boundaries or turn attacks into deceptive decoration.

Expressive animation must remain fluid and responsive. Character movement does not lock when automatic weapons fire. Distinct silhouettes, preparation poses, attack paths and recovery states matter more than decorative frame count. A recognizable Prowler crouch, raised Thornback quills and a Colossus preparing a ground strike provide actionable information without ordinary enemy HP bars.

### 14.2 The player must remain visible

Adaptive transparency, silhouettes and building cutaways preserve the player's position around scenery. They do not reveal hidden enemies or secret content. Natural enemy overlap remains; enemies are not spread apart by invented hard body-blocking just to improve readability. When obscured, the player receives only the approved minimal position marker rather than a new permanent combat overlay.

Repeated impact effects and camera shake are automatically moderated and player-adjustable. Important personal attacks retain their identities, while decorative details can reduce under heavy load. Personal and teammate effects have separate controls. This allows a spectacular build to remain playable instead of making spectacle its own unavoidable penalty.

### 14.3 Music and sound

Adaptive handcrafted fantasy music moves from intimate acoustic exploration toward layered combat, regional boss and Collapse intensity. The goal is musical development connected to the player's current experience, not a constant maximum-intensity track.

Weapons, runes and elemental reactions need recognizable layered sounds. Mixing prioritizes essential events when many reactions occur together rather than playing every repeated trigger at full prominence. Directional danger cues assist local awareness but cannot expose hidden enemies or create omniscient information.

Dialogue is primarily text with nonverbal character and creature sounds and minimal voice acting. Separate audio category controls, optional subtitles and sound captions, and reduced combat audio intensity support different needs. Captions preserve the same information limits as the sound they represent.

### 14.4 Functional art before final polish

The prototype may use readable placeholders. This does not waive genuine hit geometry, clear telegraphs, distinguishable enemy types, functional interaction feedback or visible player states. Full-content scope describes the required mechanics and catalog, not a requirement to complete every final illustration or cinematic before useful playtesting.

## 15. Interface, controls and learning
<a id="gdd-interface"></a>

**Authority:** V21-V24 visible decisions; V38.14; V42.5-V42.6. Detailed requirements: [GDS - presentation](GDS.md#gds-presentation) and [onboarding](GDS.md#gds-onboarding).

### 15.1 Contextual and customizable HUD

Essential information stays available; secondary information appears contextually or in expandable panels. Players can customize scale, placement, opacity and appropriate visibility. The HUD should support both a quiet battlefield and a more analytical player without making either mode a separate game.

HP, barriers, relevant resources, manual ability readiness and critical status warnings are immediately readable. Timer, level, XP, acquired-power ranks, minimap, pending choices, co-op health/revival state, pinned objectives and catastrophic tier appear in their approved compact forms. Detailed statistics and known interactions can be inspected in real time without pausing.

The final boss alone receives a wide screen-level HP bar. Regional bosses receive overhead bars. Ordinary enemies, elites, Unravelling and Erasure remain without HP bars, even when they rival or exceed boss combat strength. Enemy information does not expand simply because an enemy is difficult.

The minimap and expandable world map preserve fog and undiscovered secrets. Gateway direction is communicated without an automatic route. Temporary automatic-target feedback differs from environmental interaction indicators. Recognizable interactables can show a subtle prompt for the current interaction binding; undiscovered secrets remain unmarked.

### 15.2 Visual information priority

| Priority | Information that must remain readable |
|---|---|
| 1 | Dangerous enemy attack telegraphs |
| 2 | Player position and critical HP warnings |
| 3 | Environmental hazards |
| 4 | Teammate death and revival indicators |
| 5 | Enemy silhouettes and movement |
| 6 | Player attack effects |
| 7 | Teammate attack effects |
| 8 | Damage numbers and decorative particles |

Critical status effects appear prominently; secondary buffs, debuffs, stacks and cooldowns group compactly. Frequent combat events are summarized or grouped, with optional detail for build inspection. Warnings do not rely solely on color. Adjusting shake, flashes and effect intensity should not remove the ability to understand what threatens the player.

### 15.3 Control freedom and safe panel interaction

Movement is independently controlled from automatic weapon direction. The approved direction supports mouse-focused play with minimal keyboard use as well as keyboard movement plus mouse. Bindings are configurable, including left/right mouse preference and alternative movement keys. The reference scheme uses right-click movement, a distinct interaction key such as E, and left-click for appropriate aimed manual action or interface selection.

Opening the reward side panel must not stop the character from moving through visible ground commands. Selecting a reward must not accidentally activate an ability. The player may configure controls differently without losing this separation of world input from panel input.

Manual hero abilities, interaction and deliberate environmental targeting remain separate semantic actions even when bindings are changed. Detailed device layouts, touch/controller support and accessibility refinements remain open rather than silently becoming fixed by one prototype mockup.

### 15.4 Passive recipe knowledge, not a guided optimizer

The initial recipe experience is **Passive Recipe Tracking**: inspect known recipes in the Codex or build panel. Active recipe pins, reward-option indicators, compatibility warnings and guided build assistance are deferred until player need is demonstrated. The reward system never weights specific recipes because the player inspected them.

This distinction preserves experimentation without requiring memorization of every discovered recipe. It also prevents a later UI mockup from inadvertently becoming a new progression advantage.

### 15.5 Learning during normal play

A first run begins in a normal run, not a mandatory detached tutorial campaign. Brief dismissible contextual guidance arrives as needed and can be disabled. Discovery-based learning offers explanations for encountered mechanics while preserving unknown recipes and secrets.

The starter roster offers distinct choices and suggested beginner combinations without prohibiting free use of available equipment. The first opening is gentler before joining normal difficulty; bosses, Collapse timing, rewards and fundamental combat rules do not change. Co-op guidance explains shared XP, independent builds, revival and gateway behavior without interruption.

A brief skippable post-first-run explanation covers retained rewards, upgrades, equipment unlocks and the Codex. It does not force a purchase. Existing mastered information need not be repeatedly presented as a new accomplishment.

### 15.6 Simple post-run experience

The initial results screen contains outcome, survival duration, final level, enemies defeated, final build, earned rewards and newly unlocked content. It should let a player understand the run and move to another attempt quickly.

Detailed damage breakdowns, combat timelines, replay analysis and integrated feedback forms are deferred. Personal mastery records remain approved as a separate progression feature, but do not justify turning the simple results screen into a mandatory statistical dashboard. Detailed retention and navigation remain open.

## 16. Narrative foundation and deliberate limits
<a id="gdd-narrative"></a>

**Authority:** V41.1-V41.10, followed by the user's request to defer further story until prototype stability. Canonical summary: [GDS - narrative](GDS.md#gds-narrative).

### 16.1 The Unfinished World

The Creator never completed the world's laws. Nature, civilization, magic and death developed through incomplete and contradictory principles, eventually forming independent histories and identities. The Collapse is the destabilization of those laws, not simply a villain activating a countdown.

The Unravelling expresses instability. Erasure expresses existential removal. The Unfinished Canvas is the underlying foundation of reality. Graphite structure and restrained magical color make these ideas visible without requiring the player to read lore before understanding attacks.

### 16.2 The Unwritten

The heroes are not selected saviors or predetermined fragments required to reunite. They are beings whose identities developed beyond the Creator's design. Their ability to absorb, combine, evolve and fuse fragments of creation represents adaptation beyond original intent.

Each has an independent origin, personality and motivation and is not permanently allied to a hostile faction. Character-specific dialogue and discoverable histories may enrich journeys without restricting weapons, runes or powers, or imposing a mandatory personal campaign.

The record references approved individual hero origins but does not expose the complete proposed table. Their precise biographies must remain marked as a source gap rather than invented here. Their approved mechanical identities and collective narrative identity are preserved in full.

### 16.3 Three incompatible visions

| Faction | Principle | Conflict |
|---|---|---|
| Wildborn | Life must remain free to evolve. | Artificial regulation and compulsory preservation threaten adaptation. |
| Runebound | Existence requires structure. | Uncontrolled growth and contradictory persistence threaten coherent laws. |
| Hollow Legion | Nothing that once existed should be forgotten. | Erasure and replacement threaten remaining identity and memory. |

These are ideological incompatibilities, not a hierarchy of good and evil. The common threat of Collapse does not automatically reconcile their beliefs. Regional bosses embody their faction's values. Defeating one does not mean exterminating its inhabitants or introducing a mandatory allegiance system.

### 16.4 Misguided Restoration

The Forgotten Creator returns believing that dismantling and rebuilding creation is the only way to save it. Its destructive actions follow that restoration objective rather than a commitment to cruelty. It misunderstands the identities that emerged without its control and does not accept the Unwritten as legitimate extensions of creation.

The Creator is powerful, not omnipotent. The player is not required to sympathize, forgive or select a moral ending. Defeating it is sufficient for victory. Boss complexity is expressed through fighting, not mandatory extended dialogue or alternative objectives.

### 16.5 Echoes of Creation

Each run explores a different manifestation of the unfinished world. Procedural variation, repeated encounters and permanent knowledge have an in-world foundation without forcing a literal reset that makes every previous victory meaningless.

Victory preserves that manifestation. Defeat is a failed attempt, not deletion of the player's accumulated knowledge and eligible permanent progression. Other manifestations remain, and the player is not obligated to complete every possible one. Optional realms are exceptional locations within the active run, not separate independent clocks or free safety from Collapse.

### 16.6 The Discarded Creation

The Nameless Stranger is an early creation the Creator deemed flawed and attempted to erase. That erasure was incomplete. It survived between manifestations and learned to manipulate contradictions in creation.

The Stranger's bargains help the Unwritten test limits and challenge authority. It is neither purely benevolent nor malicious, has extensive but incomplete knowledge, and cannot defeat the Creator for the player. Its actual identity is gradually discoverable; its ultimate motives can remain partly ambiguous. Mechanical costs remain honestly disclosed despite narrative mystery.

### 16.7 Layered truth

The player encounters observable facts, discoverable history, hidden truths and deliberately unresolved existential questions. The Collapse, faction hostility, Creator motivation and nature of universal threats can yield meaningful answers. Why creation was unfinished and how manifestations originated can be partially revealed. The Creator's own origin and what lies beyond the Canvas remain unresolved.

NPCs can disagree without rendering every canonical fact arbitrary. Lore discovery is organic, optional and persistent through the Codex. No chronological checklist, repeated-win quota or secret true ending is required. Detailed eras, dialogue, character histories and further mysteries are deferred until the prototype is stable; this document does not expand that work without approval.

## 17. Full-content prototype and quality standard
<a id="gdd-prototype"></a>

**Authority:** V42.3-V42.4 supersede the earlier reduced-content prototype proposals. Exact acceptance contract and derived checks: [GDS - prototype](GDS.md#gds-prototype).

### 17.1 The selected scope

The owner selected a **Full-Content Prototype**, not a representative slice. The acceptance target contains the complete approved catalog and the gameplay systems that connect it.

| Content | Approved total |
|---|---:|
| Heroes | 9 |
| Main weapons | 9 |
| Global runes | 5 |
| Dedicated rune-pair interactions | 10 |
| Acquired powers | 18 |
| Ordinary ranks per acquired power | 5 |
| Authored Rank 3 / Rank 5 milestones | 36 |
| Standard Evolution forms | 36 |
| Advanced Fusions | 6 |
| Core regions and regional factions | 3 each |
| Ordinary regional enemy types | 18 |
| Regional elite counterparts | 18 |
| Regional bosses | 3 |
| Universal invader / hunter archetypes | 2 |
| Principal friendly NPC archetypes | 6 |
| Optional realms | 4 |
| Approved landmark types | 12, including 3 guaranteed anchors |
| Final boss | 1 |
| Primordial Manifestation types | 4 |

Environmental catalogs, optional-event archetypes, NPC service systems, progression, real-time interfaces, co-op, Collapse and final victory are within scope. This does not make every unwritten quest, secret, dialogue or challenge-modifier example a finished authored asset requirement. Approved families must be functional and meaningfully represented; exact remaining content instances are open.

All content must be reachable through legitimate progression. It need not be unlocked on a fresh profile or appear simultaneously in every run. A rare Fusion that has impossible prerequisites is not complete merely because its name is in a menu.

### 17.2 Stable, complete and replayable

Acceptance requires repeatable solo and co-op runs with consistent gameplay and no critical failures. Defects that block acceptance include reproducible game-breaking crashes, lost or duplicated progression, impossible victory caused by a bug, unobtainable approved Evolutions/Fusions, broken revival/co-op and unintended infinite interactions.

Provisional balance, readable placeholder art, limited narrative detail, minor visual defects and legitimately overpowered builds do not automatically block prototype acceptance. Unequal weapon performance is not inherently a defect, though consistently nonviable choices or invalidated alternatives require attention under viability-first balance.

The available discussion references twelve approved acceptance categories and a coverage table whose full contents are not recoverable. The GDS therefore provides **explicitly labeled derived operational checks**, not a fabricated quotation of the missing twelve-item list. These checks test the approved mechanics and make the prototype expectation useful without misrepresenting the source.

### 17.3 What the prototype should demonstrate

A player can prepare a build, enter a genuinely varied world, move and fight responsively, use environmental interactions, acquire meaningful upgrades, encounter factions and independent threats, explore optional content, reach either victory or defeat, retain legitimate permanent rewards and start again.

A party can separate, share eligible progression, preserve personal build ownership, rescue defeated members and enter the final encounter together. The world escalates according to the selected clock without secretly adapting to strong builds or suppressing earned rewards.

Different hero, weapon and rune foundations must feel mechanically different. At least actual experiences across all approved content, including complete Evolution and Fusion prerequisite paths, must be demonstrable; adding a placeholder label for an unimplemented system is not full-content completeness.

Useful playtesting may occur before full scope is complete. The full-content acceptance standard is not an instruction to withhold all intermediate play or create a technical roadmap here. Developers and agents decide implementation sequencing separately.

## 18. Document ownership, open work and change discipline
<a id="gdd-authority"></a>

### 18.1 Read this pair together

| Document | Authority |
|---|---|
| GDD | Game identity, intended experience, philosophies, thematic content and scope. |
| GDS | Specific gameplay behavior, complete mechanical catalogs, formulas, eligibility, provisional targets and open-detail register. |
| Technical designs and code | Implement approved behavior; they do not silently redefine it. |
| Old research, project notes and previous specifications | Historical context only where not superseded; conflicts must be reviewed rather than merged blindly. |

These are freshly authored documents based on recoverable decisions, not a split copy of the rejected previous Markdown. The GDS records named earlier handoffs and decision IDs so future agents can distinguish direct approval, provisional balance and incomplete source detail.

This pair does not choose an engine, network stack, repository structure, technical roadmap or sprint backlog. It also does not assert implementation status, completed testing or perfect coverage of conversation turns absent from the recoverable record.

### 18.2 The eight deferred groups

| Group | Deferred work |
|---|---|
| Numerical balancing | Unassigned coefficients, costs, limits, reward quantities and tuning after play. |
| Procedural content parameters | World dimensions, concrete layouts, distribution and generation guarantees. |
| Cooperative reward edge cases | Exact proximity, lapsed participation, disconnected/dead eligibility and unusual event boundaries. |
| Rare combat/session interactions | Remaining ownership, timing, persistence, placement and multiplayer lifecycle ambiguities. |
| Detailed world-content authoring | Individual quests, puzzle instances, NPC offers, bargains and reward tables. |
| Challenge/achievement details | Specific modifier catalogs, thresholds, records, cosmetics and unlock accomplishments. |
| UI/UX/accessibility refinement | Exact layout, device support, display limits and optional advanced assistance. |
| Detailed narrative | Personal histories, dialogue, historical eras and additional revelations after prototype stability. |

The GDS expands these into individually identifiable open questions, including source gaps. These items are not permission to revisit already approved fundamentals without agreement, nor a claim that every one must block initial implementation. Technical agents should record necessary provisional assumptions rather than present them as owner-approved design.

### 18.3 Preserve decisions while allowing learning

A future change should state whether it changes a number, fills an open detail or revises approved behavior. Numerical adjustments can be made under the delegated balancing policy. A gameplay revision must identify the affected mechanics, source decisions and downstream interactions, including progression and cooperative rewards.

Keep one current rule in the authoritative section and a brief supersession record. Do not leave opposite rules in separate documents for implementers to choose between. Examples that were declined, illustrative statistics that were never accepted and missing source tables must not be promoted into mandatory content merely because they sound plausible.

The purpose of this baseline is to let the game be built and played with a coherent identity: **a responsive, explorable world in which players earn extraordinary power through legitimate combinations, choose how much danger to face, and retain the meaning of their discoveries and victories.**
