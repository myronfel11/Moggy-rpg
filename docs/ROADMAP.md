# Roadmap

Rule: each phase ends with something playable and a decision about whether to continue as
planned. Nothing from a later phase is built early without discussing it first.

Status key: ✅ done · 🟡 built, awaiting playtest · ⬜ not started

## Phase 0: Setup ✅

- ✅ Godot 4.4.1 in `tools/godot/`, launch scripts in `tools/`
- ✅ Git repository, project settings, input map, physics layers
- ✅ Decision log and this roadmap

## Phase 1: Feel prototype (Milestone 1) ✅

Goal: fighting in one room with placeholder art is fun on its own.
Playtested 2026-11-14: "feels good".

- ✅ Movement with acceleration and friction
- ✅ Dash with invulnerability frames, cooldown, input buffering, afterimages
- ✅ Mouse aim
- ✅ One data-driven weapon: Pulse Blade (fast melee swing)
- ✅ One enemy: Scrap Hound (chases, walks around walls, telegraphs, lunges)
- ✅ Committed windup: hits no longer stun-lock the hound; a hit during the lunge counters it
- ✅ Impact feedback: hit flash, knockback, hit-stop, screen shake
- ✅ Endless waves, death and respawn, minimal HUD
- ✅ Automated tests and a bot-driven balance probe

## Phase 2: Loop prototype (Milestone 2) ✅

Goal: prove fight, loot, craft, fight harder.
Playtested 2026-11-14: "loop is fun". **Decision: go.**

- ✅ Material drops (Scrap, Volt Core) that fly to the player when close
- ✅ Per-player inventory, shown on the HUD
- ✅ Crafting station (the Fabricator) with one recipe
- ✅ Goal tracker on the HUD showing progress toward the next craft
- ✅ Second weapon: the Breaker (heavy hammer), swapped with Q
- ✅ Armoured enemy: the Plated Brute, appearing from wave 3
- ✅ Enemies commit to one way round an obstacle (fixes brutes stuck behind pillars)

Known rough edges carried forward:

- The first craft comes quickly (a dodging bot can afford it within about a minute). Fine
  for a prototype; real recipe costs get set once there are several tiers.
- Dying and replaying waves 1 and 2 is an efficient way to farm. Missions with their own
  rewards (Phase 5) replace the endless-wave room.

## Phase 3: Co-op foundation ⬜

Placed here on purpose: the game is still tiny, so adding networking touches little code, and
everything after this point is built networked from the start. Needs the multiplayer scope
confirmed first (decision D-04).

- ⬜ Host and join a session, players see each other move and fight
- ⬜ Host-controlled enemies, damage and drops
- ⬜ Per-player loot and inventory

## Phase 4: Combat depth ⬜

- ⬜ Three to four weapon behaviours (heavy, ranged, energy/magic)
- ⬜ Four to five enemy types with distinct attack patterns
- ⬜ Status effects
- ⬜ First boss
- ⬜ Trial of the Momentum mechanic (decision D-11)

## Phase 5: Structure ⬜

- ⬜ Hub and mission select
- ⬜ Mission objective types
- ⬜ Saving and loading
- ⬜ Pinned crafting goals shown on the HUD
- ⬜ Drop tables with bad-luck protection
- ⬜ XP and revive tokens (decision D-08)

## Phase 6: World and content ⬜

- ⬜ Generated mission layouts
- ⬜ Second biome and its materials
- ⬜ Gear tiers, armour
- ⬜ Movement abilities unlocked through progression

## Phase 7: Long-term progression ⬜

- ⬜ Difficulty tiers and opt-in modifiers
- ⬜ Weapon upgrades
- ⬜ A boss per biome with exclusive materials

## Phase 8: Release ⬜

- ⬜ Real art and audio
- ⬜ Gamepad support, settings, accessibility
- ⬜ Balance and performance passes
- ⬜ Steam page, demo, external playtests
