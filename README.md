# maki-kanban

A small, project-level Kanban package for Maki 0.5.7+. Tasks are high-level user work, not agent execution tasks.

## Installation

Declare the Git repository in your **global** Maki `init.lua` (`~/.config/maki/init.lua`, or the active legacy `~/.maki/init.lua`):

```lua
maki.pack.add({ "https://github.com/eternasuno/maki-kanban" })
```

Restart Maki and approve the package and its `fs_read` / `fs_write` permissions. Maki installs a locked Git revision; see its `pack-lock.json` and `/packupdate` to update. The actual package format is `plugin/*.lua` (auto-executed entries), `lua/<module>.lua` (loaded by `require`), and `plugin.toml`. A config-level `lua/` module alone is **not** a package entry and will not run automatically.

## Usage

`/kanban` opens the Kanban board with three independent TODO, DOING and DONE column boxes. Each title and task count is embedded in the top border, such as `TODO · 3`. Only the focused column has a status-colored border (TODO: accent, DOING: warning, DONE: success). The selected task uses a `▸` marker rather than a background highlight; every task reserves the same marker width. Narrow windows show only the focused column.

| Board key | Action |
| --- | --- |
| `h` / Left, `l` / Right | Previous / next column |
| `j` / Down, `k` / Up | Next / previous task |
| `g` / `G` | First / last task in the focused column |
| Enter | Open Task Detail in the same window |
| `<` / `>` | Move the selected task to the previous / next column |
| `n` | Create a task |
| `d` | Confirm task deletion |
| `r` | Reload |
| `?` | Open keybinding help |
| `q` / Esc | Close kanban |

Moves do not wrap at either edge. After a successful move, focus and selection follow the task by ID; failures preserve selection and display an error. Column navigation never moves tasks. The former `1`/`2`/`3` and uppercase `H`/`L` Board bindings are removed.

`?` opens the keybinding help overlay. `?` or Esc closes it. While help is open, other keys are consumed without changing the Board. Help is centered and recomputes its size and position after resizing; narrow windows clip its contents safely.

A separate three-line Footer box shows `NORMAL` and compact help/quit hints. It also displays errors and delete confirmation, using bold error-colored text. The task viewport excludes the Footer and its spacing, including after resizing. Extremely small windows clip the layout to the available cells.

In Task Detail, Tab / Shift+Tab switches between Title, Status and Description; `j`/`k`, Up/Down, PageDown/PageUp and `g`/`G` scroll the description. Enter edits the focused field. Title is edited inline, and Status is switched with `h`/`l` or Left/Right; Enter saves either field and Esc cancels. Description opens a temporary file in `$EDITOR`: save the file and exit to save the change, or exit without saving to cancel (no change). `b` returns to the board with selection and scroll position intact; `q` or Esc closes the Kanban UI outside inline editing.

In Task Detail outside field editing, press `d` to display `Delete this task? y/N`. Only `y` confirms; any other key (including `n` or Esc) cancels confirmation without performing that key's normal action. Successful deletion reloads and returns to the board; selection falls back to the same index in the original column, clamped to the last remaining task, or no task if the column is empty. Delete failures keep Task Detail open and display the error so you can retry or return with `b`. On the board, `d` shows `Delete "title"? y/N` in the Footer without opening Task Detail; confirmation takes priority over normal hints, errors and help. Only `y` deletes; all other keys (including `q`, Esc, `n`, Enter and navigation) cancel and are consumed. Success reloads the board with the same clamped-index fallback; failure preserves cards, focus and selection and displays an error for retry. Resizing retains confirmation.

The agent can use:

- `task_list` — list every task, including its ID.
- `task_get` — read a task by `id`.
- `task_create` — create with required `title` and optional `description`; ID is generated, status defaults to `todo`.
- `task_update` — pass `id` and at least one of `title`, `description`, or `status` at the top level. Any legal status is allowed directly.
- `task_delete` — delete by required `id`; returns the deleted task as JSON.

On the board, press `n` to open task creation in field-selection mode. Tab / Shift+Tab switches between Title, Description and Create. Press Enter on Title to edit it, then Enter again to keep the draft; Enter on Description opens a temporary file in `$EDITOR`; Enter on Create saves through the Store with status `todo`. Save failures keep the form and inputs and display the error. Esc cancels the current Title edit; Esc outside editing (or `b`) cancels creation and returns to the board without creating a task. Successful creation reloads the board, focuses TODO and selects the new task. Board reloads preserve each column's selected task by ID where possible, with a clamped nearby fallback when it is removed or moved.

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

`todo`, `doing`, `done` (shown as Todo, Doing, Done in task detail).

## Development

Keep the Git checkout separate from Maki's package directory. On this machine the checkout is `/home/zhang/maki-kanban` and the symlink is `/home/zhang/.local/share/maki/site/pack/dev/start/maki-kanban -> /home/zhang/maki-kanban`. `dev` is an arbitrary hand-installed group; `core` is reserved. To set this up on another machine, first check Maki's current [directory layout](https://github.com/tontinton/maki/tree/main/site/docs/content/configuration) and the platform's XDG data directory (`$XDG_DATA_HOME/maki`, usually `~/.local/share/maki` on Linux), then symlink your checkout into `<maki-data>/site/pack/dev/start/maki-kanban`. Hand-installed start packages load on startup and use only their declared manifest permissions, without a package approval prompt. Maki's managed Git packages instead go under `pack/core` and are locked to a revision; do not use them for live local edits.

From a disposable project directory (not the plugin checkout), check registration without calling a model:

```sh
maki prompt --tools --names | grep '^task_'
```

The output should include `task_list`, `task_get`, `task_create`, `task_update`, and `task_delete`. Start Maki in that directory and open `/kanban`; after changing Lua code use `/reload` in the interactive UI. Current Maki rebuilds the Lua host, runs the package entry again, re-registers commands/tools and clears the old module `require` cache. This behavior follows the current Maki source; no manual `package.loaded` clearing is needed. It is not a command for `maki -p` or a shell command.

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
8. On `/kanban`, create with `n`, open with Enter, and try `d` → `n`, `d` → Esc, then `d` → `y`. Check selection after deleting a middle task and the last task in a column. Create another task and use `L`, `L`, `H`, `H`; selection must follow it. Repeat in a narrow single-column window and resize while moving. Try deleting/moving with malformed JSON and verify its bytes remain unchanged.
9. Temporarily change the window title in `lua/kanban/ui.lua`, execute `/reload`, open `/kanban` and confirm the new title. Restore the code and reload again.

In this development environment the installed Maki 0.5.7 CLI confirmed registration and the agent tools performed steps 1–3, the status/text updates and error checks; the corrupt JSON remained intact. An interactive TUI is required to visually verify the window and to execute `/reload`: those interactive checks have not been independently confirmed here.

## MVP limitations

There is no subagent tracking, execution hooks, or concurrent write protection. There are no additional task fields or backend service.
