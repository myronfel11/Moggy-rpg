# Working together

Two of us work on this game from different homes. GitHub keeps our files in sync; it has
nothing to do with playing online (see "Playing together" below for that).

## Setting up a new PC (once)

1. Install [Git for Windows](https://git-scm.com/download/win) and create a GitHub account.
   Accept the invitation to the repository (check your email or github.com/notifications).
2. Clone the project and install Godot into it:
   ```
   git clone <repository url> "C:\game"
   cd "C:\game"
   tools\setup.cmd
   ```
   `setup.cmd` downloads Godot 4.4.1 into `tools\godot\` and checks it is the official build.
   We both use exactly this version; do not open the project in a different Godot version.
3. Run `tools\test.cmd`. It should end with "All tests passed".
4. Play with `tools\play.cmd`. Edit with `tools\editor.cmd`.

## Everyday workflow

`main` is always playable and passes the tests. Nobody pushes to it directly.

1. Start from the latest `main`:
   ```
   git switch main
   git pull
   git switch -c yourname/what-you-are-doing
   ```
2. Work, run `tools\test.cmd`, commit often:
   ```
   git add -A
   git commit -m "Add the spark lance weapon"
   ```
3. Push and open a pull request:
   ```
   git push -u origin yourname/what-you-are-doing
   gh pr create --fill
   ```
4. GitHub runs the tests automatically on the pull request. The other person pulls the
   branch, plays it, and approves:
   ```
   git fetch
   git switch yourname/what-you-are-doing
   ```
5. Merge with "Squash and merge" on GitHub, delete the branch, and both `git pull` on `main`.

Keep branches small and short-lived (a day or two). Long branches are what cause painful
conflicts.

## Avoiding conflicts in Godot

- **Scenes (`.tscn`) merge badly.** Only one of us edits a given scene at a time. Say in chat
  "I'm editing the arena scene" before you start, and "done" after merging.
- **New content goes in new data files.** A new weapon, enemy, material or recipe is a new
  `.tres` file, which never conflicts with anything. Prefer that over editing shared files.
- **Commit `.uid` and `.import` files** that Godot creates next to scripts and images.
- **Never commit `.godot/`** (Godot's cache) or `tools/godot/` (the engine). `.gitignore`
  already excludes them.

## When a merge conflict happens

`git pull` or the pull request says there is a conflict. Then:

- **Script (`.gd`) or document:** open the file, find the `<<<<<<<` / `=======` / `>>>>>>>`
  markers, keep the right parts of both, delete the markers.
- **Scene (`.tscn`), data (`.tres`) or `project.godot`:** do not hand-merge. Keep one side
  whole, then redo the other person's change in the editor:
  ```
  git checkout --theirs path/to/file.tscn   # keep the version from main
  git checkout --ours path/to/file.tscn     # keep your version
  ```
- Then run `tools\test.cmd`, `git add -A`, `git commit`.

If unsure, stop and ask the other person before committing.

## Playing together online

Home routers block direct connections between our PCs, so typing a normal IP address into
the Join box does not work across the internet.

**Today: Tailscale** (free). Both install it from tailscale.com and sign in; the host shares
their device with the other person in the Tailscale admin page. The host runs
`tools\host.cmd`. The other person runs `tools\play.cmd`, types the host's Tailscale address
(starts with `100.`, shown in the Tailscale tray menu) and clicks Join.

**Soon: Steam.** Host with Steam and the other person picks the game from a list. Both need
Steam running and a Steam account.

Both should be on the same commit of `main`. The game refuses to join a host whose version
number differs (Project Settings > Application > Config > Version, currently in
`project.godot`). **Bump that number in any pull request that changes networking, synced
values or scenes that are spawned over the network**, so mismatched builds are refused with
a clear message instead of misbehaving.

### Online test checklist

1. Both players see each other move, aim, swing and dash.
2. Enemies and attack warnings match on both screens; a dodge that worked for you counts.
3. Each player damages and kills enemies; both get the same drops.
4. One player dies and returns after 5 s; both die and the run restarts.
5. Swap who hosts and repeat.
6. Leave and rejoin mid-wave.
7. The host force-closes the game (the other returns to the menu with a message); the
   joiner turns off Wi-Fi (the host loses that player within about 30 s and keeps playing).

Report anything that felt delayed or wrong, who was hosting, and both log files from
`%APPDATA%\Godot\app_userdata\Action RPG Prototype\logs`.
