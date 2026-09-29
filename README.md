# maki-kanban

A small, project-level Kanban package for Maki 0.5.7+. Tasks are high-level user work, not agent execution tasks.

## Installation

Declare the Git repository in your **global** Maki `init.lua` (`~/.config/maki/init.lua`, or the active legacy `~/.maki/init.lua`):

```lua
maki.pack.add({ "https://github.com/eternasuno/maki-kanban" })
```

Restart Maki and approve the package and its `fs_read` / `fs_write` permissions. Maki installs a locked Git revision; see its `pack-lock.json` and `/packupdate` to update. The actual package format is `plugin/*.lua` (auto-executed entries), `lua/<module>.lua` (loaded by `require`), and `plugin.toml`. A config-level `lua/` module alone is **not** a package entry and will not run automatically.

## Usage

`/kanban` opens a read-only three-column window (TODO, Doing, Complete). Press `q` or Esc to close; scroll a tall board with `j`/`k`, the arrow keys, PageUp/PageDown, or `g`/`G`. The agent can use:

- `task_list` — list every task, including its ID.
- `task_get` — read a task by `id`.
- `task_create` — create with required `title` and optional `description`; ID is generated, status defaults to `todo`.
- `task_update` — pass `id` and at least one of `title`, `description`, or `status` at the top level. Any legal status is allowed directly.

## Data

Each project uses `<project>/.maki/kanban.json`, relative to the Maki process working directory. Missing file means an empty board; the first write creates the directory and file. Malformed JSON is reported and never automatically overwritten.

```json
{
  "tasks": {
    "task-1": {
      "title": "Implement login page",
      "description": "Add the basic login UI",
      "status": "doing"
    }
  }
}
```

The stored `tasks` value is an ID-to-task object, not an array; the task body does not contain an ID. Tool responses include the ID.

## Statuses

`todo`, `doing`, `done` (shown as Complete).

## Development

Keep the Git checkout separate from Maki's package directory. On this machine the checkout is `/home/zhang/maki-kanban` and the symlink is `/home/zhang/.local/share/maki/site/pack/dev/start/maki-kanban -> /home/zhang/maki-kanban`. `dev` is an arbitrary hand-installed group; `core` is reserved. To set this up on another machine, first check Maki's current [directory layout](https://github.com/tontinton/maki/tree/main/site/docs/content/configuration) and the platform's XDG data directory (`$XDG_DATA_HOME/maki`, usually `~/.local/share/maki` on Linux), then symlink your checkout into `<maki-data>/site/pack/dev/start/maki-kanban`. Hand-installed start packages load on startup and use only their declared manifest permissions, without a package approval prompt. Maki's managed Git packages instead go under `pack/core` and are locked to a revision; do not use them for live local edits.

From a disposable project directory (not the plugin checkout), check registration without calling a model:

```sh
maki prompt --tools --names | grep '^task_'
```

The output should include `task_list`, `task_get`, `task_create`, and `task_update`. Start Maki in that directory and open `/kanban`; after changing Lua code use `/reload` in the interactive UI. Current Maki rebuilds the Lua host, runs the package entry again, re-registers commands/tools and clears the old module `require` cache. This behavior follows the current Maki source; no manual `package.loaded` clearing is needed. It is not a command for `maki -p` or a shell command.

Logs: `maki.log` in the directory returned by `maki.env.logs_dir()` (on this Linux installation: `~/.local/logs/maki/maki.log`). Read this file for Lua load errors and debugging; `maki --log` is **not** an option in installed Maki 0.5.7 even though some API documentation suggests it. Temporary `maki.log.info(...)` or `maki.log.error(...)` can help during development; avoid permanent verbose logs. Run `maki --no-jit` for clearer Lua stack traces.

Run the lightweight regression scripts with Neovim's embedded LuaJIT (`nvim --headless -l tests/store.lua` and `nvim --headless -l tests/ui.lua`). If `luajit` is installed, `luajit tests/store.lua` works too (this machine has LuaJIT in the Nix store but no `luajit` on PATH). The scripts use local Maki API shims, not the interactive UI.

### Manual integration checks

Use a fresh temporary project such as `/tmp/maki-kanban-test`:

1. With no `.maki/kanban.json`, run `maki prompt --tools --names`, open `/kanban` and confirm three empty columns and no error.
2. Create a task through `task_create` (`title`: `实现登录页面`, `description`: `添加基础登录 UI`); confirm `task-1`, `todo`, and an ID-keyed JSON object with no body ID.
3. `task_list` and `task_get({"id":"task-1"})` must include the ID.
4. Update its `status` through `doing` and `done`; check the returned task, JSON, and `/kanban` column after each step.
5. Change `title` and `description` with `task_update`; omitted fields must remain unchanged.
6. Try `status: "blocked"`, then `task_get` and `task_update` with a missing ID; all must report errors without modifying the file.
7. Replace the JSON with invalid text, call `task_list` and open `/kanban`; expect an explicit error and the original invalid bytes to remain.
8. Temporarily change the window title in `lua/kanban/ui.lua`, execute `/reload`, open `/kanban` and confirm the new title. Restore the code and reload again.

In this development environment the installed Maki 0.5.7 CLI confirmed registration and the agent tools performed steps 1–3, the status/text updates and error checks; the corrupt JSON remained intact. An interactive TUI is required to visually verify the window and to execute `/reload`: those interactive checks have not been independently confirmed here.

## MVP limitations

The UI is read-only. There is no subagent tracking, execution hooks, delete operation, or concurrent write protection. There are no additional task fields, UI editing, or backend service. The window keeps a fixed height of 20 content rows (bounded by the terminal), pins the column heading, and scrolls a taller board instead of growing.
