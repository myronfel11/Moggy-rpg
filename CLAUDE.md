# Project notes for Claude

Top-down pixel art action RPG in Godot 4.4.1 with typed GDScript. The user is a web developer
who is new to game development: explain game-dev concepts and the reasons behind decisions.

Two developers work on this from different homes via GitHub; see `docs/CONTRIBUTING.md`
for the branch/pull-request workflow and Godot conflict rules. Work on a branch, never
commit straight to `main`. Bump `application/config/version` in `project.godot` when a
change affects networking, synced values or network-spawned scenes (co-op refuses
mismatched versions). A new PC runs `tools\setup.cmd` to install the pinned Godot build.
GitHub Actions (`.github/workflows/tests.yml`) runs unit and smoke tests on pull requests.

## Read first

- `docs/ROADMAP.md`: current phase and what is next. Update it when a milestone item changes state.
- `docs/DECISIONS.md`: agreed, proposed and open decisions. Add an entry for every new decision.

Do not build anything from a later roadmap phase, or any major feature, without discussing it
with the user first.

## Commands

The engine is at `tools/godot/Godot_v4.4.1-stable_win64_console.exe` (use the `_console` build so
output is captured). The project path contains a space, so quote it.

```powershell
$godot = "C:\test game\tools\godot\Godot_v4.4.1-stable_win64_console.exe"

# After adding or renaming any script with class_name, or adding assets: rebuild Godot's cache.
& $godot --headless --path "C:\test game" --import

# Unit tests and the scripted smoke test (exit code 0 = pass)
& $godot --headless --path "C:\test game" res://tests/unit_tests.tscn
& $godot --headless --fixed-fps 60 --path "C:\test game" res://tests/smoke_test.tscn

# Screenshot of the running game (opens a window briefly). Add --when=telegraph to
# capture an enemy about to lunge instead of the player mid-swing.
& $godot --path "C:\test game" res://tests/screenshot.tscn -- --out=C:/path/to/shot.png

# Balance probe: scripted bot plays, prints waves/kills/hits/deaths/materials. Run after
# tuning or enemy-movement changes and compare with the baseline in docs/DECISIONS.md (T-10).
# Results vary run to run, so run it several times. A "STALL" block in the output means
# nothing died for 45 s: an enemy is stuck, read the positions it prints.
& $godot --headless --fixed-fps 60 --path "C:\test game" res://tests/bot_probe.tscn -- --seconds=180
& $godot --headless --fixed-fps 60 --path "C:\test game" res://tests/bot_probe.tscn -- --seconds=180 --bot=dodge
& $godot --headless --fixed-fps 60 --path "C:\test game" res://tests/bot_probe.tscn -- --seconds=180 --bot=dodge --weapon=breaker
```

Screenshot moments: `--when=swing` (default), `telegraph`, `brute`, `station`, `crafted`.

Edit project files with the Edit/Write tools only. PowerShell's `Set-Content -Encoding utf8`
adds a byte-order mark to the file.

When a fix is for a bug that only shows up sometimes, confirm it by switching the fix off
and seeing the failure come back, and say so plainly if a test cannot reproduce it.

`tools\test.cmd` runs import, unit tests, smoke test and the co-op test (`tools\test_net.cmd`:
a headless host and client on port 24600, logs in `%TEMP%\arpg_net_test`) in one go.
The game starts at `main/main.tscn` (menu); tests instantiate the arena directly.

What cannot be verified from here: how the game *feels*. Say so, and ask the user to playtest.

## Architecture rules

- **Content is data.** Weapons are `WeaponData` resources (`weapons/data/*.tres`) pointing at a
  reusable behaviour scene in `weapons/behaviors/`. Enemies are `EnemyData` resources pointing
  at an enemy scene. A new item of an existing kind must need no new code.
  The same goes for materials (`ItemData`), loot (`DropEntry` lines on `EnemyData.drops`) and
  recipes (`Recipe` with `ItemAmount` costs). Typed arrays of resources in hand-written
  `.tres`/`.tscn` files use `Array[ExtResource("script_id")]([...])`.
- **One damage pipeline.** `Hitbox` -> `Hurtbox.receive_hit(HitInfo)` -> `HealthComponent`.
  Never change health any other way. Armour is applied in `Hurtbox` (flat reduction, min 1).
- **Loot and gear belong to the player.** `Inventory` and the owned-weapons list are on the
  `Player` node. Things in the world (crafting stations) react to the player's
  `interact_requested` signal; they never read input.
- **Co-op.** Authority rules are in `docs/DECISIONS.md` (T-13). In short:
  - Before changing state, check who owns it: `player.is_local()` for players,
    `is_multiplayer_authority()` / `multiplayer.is_server()` for enemies and waves.
    Offline (solo, unit and smoke tests) this machine owns everything, so checks pass.
  - Create players and enemies only through `Arena` (`spawn_enemy`, player spawning);
    never `add_child` them directly, or clients will not get them.
  - A new synced value goes in that scene's `Sync` node (`SceneReplicationConfig`).
  - A new enemy brain must override `_puppet_think` to show telegraphs on clients.
  - Visual one-off events from the host use `@rpc("authority", "call_remote")`.
  - Steam (GodotSteam add-on in `addons/godotsteam/`) is reached only through
    `NetworkSession` with `Engine.get_singleton("Steam")` and `call()`, and only after a
    Steam button is pressed. Never start Steam in tests or at game start.
    `tests/steam_check.tscn` is a manual one-PC check that needs Steam running.
  - Loot is rolled once by the host (`Enemy.roll_drops`) and sent with the death RPC;
    every peer spawns its own copy of the same pieces. Never roll randomness on clients.
  - Player intent goes through `PlayerInput`; gameplay code never reads `Input` directly.
  - Never assume one player. Find players through the `players` group or `Arena.get_players()`.
  - No gameplay state in autoload singletons.
  - Effects that only matter to the local screen (shake, flashes) stay out of gameplay logic.
  - Hit-stop is per character (`_hit_stop` timers), never `Engine.time_scale`.
- **The wielder ticks its weapon** (`weapon.tick(delta)`), so hit-stop pauses both together.
- Physics layer values are in `core/layers.gd`; names are in Project Settings.
- Typed GDScript everywhere. Tabs for indentation. Doc comments (`##`) on exported tuning
  values, because they become editor tooltips the user reads while tuning.
- Scenes are hand-written `.tscn` text. Omit `uid=` and `load_steps`; Godot fills them in.
- No third-party addons without discussing it first.
