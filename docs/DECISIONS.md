# Decision log

Every design or technical decision we agree on is recorded here with its reason, so we can
revisit it later without relitigating from memory. Newest entries go at the bottom of each
section. Status is one of: **Agreed**, **Proposed** (awaiting your yes/no), **Open** (question
not yet answered).

## Design decisions

| # | Date | Decision | Why | Status |
|---|------|----------|-----|--------|
| D-01 | 2026-11-14 | Top-down perspective. | Fits farming, missions, generated levels and 360° weapon variety; avoids platform-aware enemy AI and jump-safe level generation. | Agreed |
| D-02 | 2026-11-14 | World is a hub plus instanced, repeatable missions. No persistent open world. | Keeps the loop tight and repeatable; avoids chunk streaming, world saves and terrain systems. | Agreed |
| D-03 | 2026-11-14 | No mining. All resources come from enemy drops. | Your call. Keeps every resource tied to combat, which is the game's strongest part. | Agreed |
| D-04 | 2026-11-14 | Multiplayer is wanted. | Your call. Scope (co-op only? how many players? online, local, or both?) still needs confirming. | Agreed, scope **Open** |
| D-05 | 2026-11-14 | Controls: WASD to move, mouse to aim. Gamepad support later. | Mouse aim gives precise 360° combat; gamepad can map onto the same input layer. | Agreed |
| D-06 | 2026-11-14 | Setting: cyberpunk sci-fi blended with fantasy. | Your call. Gives a distinct identity (neon tech plus magic). | Agreed |
| D-07 | 2026-11-14 | You draw the art. Placeholder shapes until then. | Lets us judge feel before investing in art. | Agreed |
| D-08 | 2026-11-14 | On death the player loses XP and a revive token. Materials are kept. | Your call. Death stings without wiping farming progress. | Agreed, details **Open** (see below) |
| D-09 | 2026-11-14 | Target: commercial release on Steam. | Sets the quality bar and means scope discipline matters. | Agreed |
| D-10 | 2026-11-14 | Rare drops are shortcuts, not gates: drop chance rises after each miss, and bosses give a guaranteed token tradeable for their rare material. | Keeps rare drops exciting while capping worst-case grind. | Proposed |
| D-11 | 2026-11-14 | "Momentum" meter: kill chains and well-timed dodges raise drop quantity; getting hit lowers it. | Makes skill pay out in farming speed, not only survival. To be trialled, not assumed. | Proposed |
| D-12 | 2026-11-14 | Base resolution 480x270 on a 16-pixel grid, scaled up in whole multiples. | 480x270 shows about 30x17 tiles: enough room to read fights. Scales cleanly to 1080p and 4K. Confirm before drawing real art, because it fixes sprite sizes. | Proposed |
| D-13 | 2026-11-14 | A Scrap Hound's windup is committed: hitting it during the windup deals damage and pushes it but does not cancel the lunge. Hitting it during the lunge itself does knock it out of the attack. | Measured, not guessed. When any hit cancelled the attack, a bot that only walked up and swung reached wave 11 in 90 s taking 8 hits, because enemies were permanently stun-locked. With this rule the same bot dies 4 to 5 times in 120 s, and a bot that dodges takes 0 to 3 hits. It is one switch per enemy (`committed_windup`), so weak fodder can still be made interruptible. | Agreed (you played it on 2026-11-14 and said it feels good) |
| D-14 | 2026-11-14 | The first craftable weapon is the Breaker, a heavy hammer: slow windup, wide arc, high damage. Q swaps between owned weapons. | It plays differently from the blade (commit and time it, rather than dart in and out) and needs no new code, only a new data file. Ranged and energy weapons come in Phase 4 because they need new behaviours. | Agreed (playtested 2026-11-14: "loop is fun") |
| D-15 | 2026-11-14 | Armour removes a flat amount from every hit, and a hit always deals at least 1. | One simple rule makes weapon choice matter: many light hits lose most of their damage, a few heavy hits lose little. No special "armour piercing" stat needed. | Agreed (playtested 2026-11-14) |
| D-16 | 2026-11-14 | Milestone 2 has two materials: Scrap (common, every kill) and Volt Core (uncommon: a chance from hounds, guaranteed from brutes). The Breaker costs both. | The smallest set that shows the whole loop: steady progress from common drops, a moment of excitement from a rarer one, and a reason to fight the harder enemy. | Agreed (playtested 2026-11-14). The amounts are prototype numbers, not final. |
| D-17 | 2026-11-14 | Dying keeps your materials and crafted weapons. | Follows D-08 (death costs XP and a revive token, not loot). XP and tokens do not exist yet, so for now death only resets the wave. | Agreed |

### Open questions

- **Multiplayer scope (D-04).** My recommendation: 2 to 4 player online co-op, no PvP, one player
  hosts (no paid servers), each player keeps their own character and inventory.
- **XP (D-08).** What does XP level up: the character, each weapon (Warframe-style mastery), or
  both? This is a new system we have not designed yet.
- **Revive tokens (D-08).** How are they earned (crafted, per-mission allowance, daily refill)?
  What happens at zero tokens: mission failed, return to hub with or without the loot gathered?

## Technical decisions

| # | Date | Decision | Why |
|---|------|----------|-----|
| T-01 | 2026-11-14 | Godot 4 with typed GDScript. Starting on 4.4.1 (already downloaded); moving to a newer 4.x later is low-risk. | Scenes, data and scripts are plain text that can be edited and checked from the command line; strong 2D tools; free; ships native builds. |
| T-02 | 2026-11-14 | Content is data. A weapon is a `WeaponData` resource file that points at a reusable behaviour scene (swing, projectile, ...). Enemies follow the same pattern with `EnemyData`. | A new weapon or enemy is a new data file, not new code. New code is only needed for a new *kind* of behaviour. |
| T-03 | 2026-11-14 | One damage pipeline: `Hitbox` (attack area) finds `Hurtbox` (hittable area), which forwards a `HitInfo` to a `HealthComponent`. | Every source of damage goes through the same three small pieces, for players and enemies alike. |
| T-04 | 2026-11-14 | Multiplayer-ready rules from day one (see `CLAUDE.md`): input lives in its own node, enemies find targets through the `players` group, no code assumes a single player. | Makes adding networking a contained job instead of a rewrite. |
| T-05 | 2026-11-14 | Hit-stop (the brief freeze on impact) is per character, not a global slow-down of the whole game. | A global freeze would stall every player in a co-op session whenever anyone lands a hit. |
| T-06 | 2026-11-14 | Compatibility (OpenGL) renderer, nearest-neighbour filtering, viewport stretch with integer scaling. | Lightest renderer, crisp pixels, runs on almost any PC. |
| T-07 | 2026-11-14 | Automated tests are plain Godot scenes run headless (`tools/test.cmd`). No third-party test framework. | No dependency to maintain. The smoke test drives the real game with scripted input. |
| T-08 | 2026-11-14 | Physics layers: 1 world, 2 player body, 3 enemy body, 4 player hurtbox, 5 enemy hurtbox. Player and enemy bodies do not block each other. | The player must be able to dash through enemies. Damage uses hurtbox layers so it never depends on bodies touching. |
| T-09 | 2026-11-14 | Enemy movement is "walk straight at the target; if a wall blocks you, walk along it briefly". Enemies also need a clear line of sight before attacking. No pathfinding yet. | Found by testing: an enemy and a player on opposite sides of a pillar pushed at each other forever. The detour fixes open rooms cheaply. Real pathfinding is deferred to Phase 6, when generated layouts need it. Amended the same day: an enemy that hits the same wall again shortly after a detour keeps going the same way round. Without that, slow Plated Brutes got stuck behind pillars (2 stalls in 8 bot runs before, 0 in 24 after). No scripted test reproduces the stall on demand, so the probe's stall report is the guard. |
| T-10 | 2026-11-14 | A balance probe (`tests/bot_probe.tscn`) plays the game with two scripted bots: one that only swings, one that also dodges. It prints a position snapshot if nothing dies for 45 s. | Feel cannot be automated, but "does dodging pay off?" and "does the upgrade matter?" can be counted. Baseline over 180 s after Milestone 2: swing-only with the blade stalls at wave 3, kills no brutes, dies 7 to 8 times. Dodging with the blade reaches wave 6 to 7, kills 4 to 5 brutes, no deaths, and can afford the Breaker after 30 to 55 s. Swing-only with the Breaker reaches wave 5 and still dies 4 times. Dodging with the Breaker reaches wave 11 to 12 and kills 17 to 18 brutes. Re-run after tuning changes. |
| T-11 | 2026-11-14 | Each player carries their own `Inventory` node and list of owned weapons. Nothing about loot is stored globally. | In co-op every player needs their own loot and gear, so it has to belong to the player from the start. |
| T-12 | 2026-11-14 | Loot is rolled from `DropEntry` lines on the enemy's data file. Recipes are `Recipe` data files listing `ItemAmount` costs. | Same rule as weapons and enemies: new materials, drops and recipes are data files, not code. |

## Deferred tuning notes

These are known rough edges to revisit, not decisions.

- Pixel snapping and camera smoothing need a pass once real sprites exist (placeholder shapes hide the issue).
- On monitors faster than 60 Hz, movement may look slightly uneven; Godot's physics interpolation is the fix if so.
- The default font is not a pixel font; the HUD text is placeholder.
