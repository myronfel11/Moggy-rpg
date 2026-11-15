# Action RPG Prototype

A top-down pixel art action RPG: movement-first combat, loot from enemies, crafting, and
long-term gear progression. Working title only.

- Where we are and what is next: [docs/ROADMAP.md](docs/ROADMAP.md)
- What we decided and why: [docs/DECISIONS.md](docs/DECISIONS.md)

## Running it

Everything runs from the `tools` folder (double-click, or run from a terminal):

| Script | What it does |
|--------|--------------|
| `tools\play.cmd` | Runs the game. |
| `tools\editor.cmd` | Opens the project in the Godot editor. Press F5 there to play. |
| `tools\test.cmd` | Runs all automated tests without opening a window. |
| `tools\play_venza.cmd` | Playtest shortcut: solo as Venza, on a separate "dev" save. |
| `tools\host.cmd` | Starts a co-op game as host. |
| `tools\join.cmd [address]` | Joins a co-op game (this PC if no address is given). |

### Co-op

`play.cmd` opens a menu: play solo, host, or join by IP address. To try co-op on one PC,
run `host.cmd`, then `join.cmd`; two windows open and each controls its own character
(click a window to give it the keyboard). Over a LAN, the joiner types the host PC's IP
address in the menu. The host's firewall must allow the game on UDP port 24565.
Across the internet (different homes), a normal IP address does not work. Use **Host with
Steam** and **Find Steam games** in the menu (both players need Steam running), or
Tailscale, as described in [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

The engine itself lives in `tools/godot/` and is not committed to git. On a new machine,
run `tools\setup.cmd` once: it downloads Godot 4.4.1 there and checks it is the official build.

Working together on GitHub and playing online from different homes: [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Controls

| Action | Input |
|--------|-------|
| Move | W A S D |
| Aim | Mouse |
| Attack | Left mouse button (hold to keep swinging) |
| Dash | Space |
| Skate (Venza only) | Hold Shift while moving |
| Abilities (Venza: Boost, Fade, Rush) | 1, 2, 3 |
| Zenith ultimate (when the bar is full) | 4 |
| Grapple (everyone) | Hold right mouse button; let go to launch |
| Use a station (Navigation, Fabricator, Armory) | E (while standing next to it) |
| Swap weapon | Q |
| Back to menu / quit from menu | Esc |

## What is in the prototype

You start in the **hub**, a safe room with three areas (walk up and press E):

- **Navigation:** pick a mission. In co-op only the host can start it; everyone goes along.
- **Fabricator:** turn materials into gear (the Breaker, a heavy hammer).
- **Armory:** choose your character (colour only for now) and the two weapons you carry.

Missions are waves of enemies. Enemies drop materials, which fly to you when you get close.
The line at the top of the screen shows what you are saving up for. Armoured Plated Brutes
shrug off the starter blade but not the Breaker. Clear the last wave, or all go down, and
everyone returns to the hub keeping what they collected. Progress is saved on your PC.

## How the code is organised

```
main/        Start menu; loads the arena (solo, host or join)
net/         Starting, joining and leaving co-op sessions
core/        Shared building blocks: health, hitbox, hurtbox, camera, hit flash
player/      The player scene, movement and dash, the input layer, the inventory
weapons/     WeaponData (stats) + reusable attack behaviours + weapon data files
enemies/     EnemyData (stats) + enemy behaviours + enemy scenes + enemy data files
items/       ItemData (a material) + material data files
missions/    MissionData + mission data files (waves, enemies, length)
characters/  CharacterData + character data files
loot/        Drop lists and the pickups that lie on the ground
crafting/    Recipes and the crafting station
levels/      Rooms and the pieces they are built from
ui/          HUD and small on-character displays
tests/       Automated tests, test bots, screenshot and balance tools
docs/        Roadmap and decision log
```

The main idea, repeated everywhere: **content is data**. A weapon, enemy, material, drop
list or recipe is a `.tres` data file you can edit in the Godot editor. Code is only
written for a new *kind* of behaviour.

### Tuning without touching code

Open the project in the editor and double-click one of these files. Every number has a
tooltip explaining what it does.

| File | What it controls |
|------|------------------|
| `weapons/data/pulse_blade.tres` | Starter blade: damage, swing speed, reach, arc, knockback |
| `weapons/data/breaker.tres` | Crafted hammer: the same properties, tuned slow and heavy |
| `enemies/data/scrap_hound.tres` | Basic enemy: health, speed, attack timing, drops |
| `enemies/data/plated_brute.tres` | Armoured enemy: the same, plus armour |
| `crafting/data/breaker_recipe.tres` | What the Breaker costs |
| `items/data/*.tres` | Material names, rarity, colour |
| `player/player.tscn` (select the Player node) | Move speed, acceleration, dash |
| `levels/test_arena/test_arena.tscn` (select WaveDirector) | Wave sizes, when brutes appear |

### Adding things

- **A weapon that swings** like the existing two: duplicate `pulse_blade.tres` and change
  the numbers. No code.
- **A new kind of attack** (for example a projectile): add one behaviour scene under
  `weapons/behaviors/`, then any number of data files can use it.
- **An enemy** that chases and lunges: duplicate `scrap_hound.tres`. For a different look,
  duplicate `enemies/chaser/chaser.tscn` and point the data file at the copy.
- **A material**: duplicate `items/data/scrap.tres`, then add it to an enemy's Drops list.
- **A recipe**: duplicate `breaker_recipe.tres`, set its result and costs, and add it to
  the CraftingStation's Recipes list in the level.

### Measuring balance

`tests/bot_probe.tscn` plays the arena with a scripted bot and prints waves reached, kills,
hits taken, deaths and materials collected. There are two bots: one that only walks up and
swings, and one that also dodges lunges. If the first does nearly as well as the second,
the game is rewarding button-mashing. The probe also prints a snapshot of everyone's
position if nothing dies for 45 seconds, which is how stuck enemies get found. Usage is in
the comment at the top of `tests/bot_probe.gd`; current numbers are in the decision log.
