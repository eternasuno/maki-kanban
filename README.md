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
| `q` / Esc / Ctrl-C | Close kanban |

Moves do not wrap at either edge. After a successful move, focus and selection follow the task by ID; failures preserve selection and display an error. Column navigation never moves tasks. The former `1`/`2`/`3` and uppercase `H`/`L` Board bindings are removed.

`?` opens the modal keybinding help overlay; see the modal-key rules below.

A separate three-line Footer box shows `NORMAL` and compact help/quit hints. It also displays errors and delete confirmation, using bold error-colored text. The task viewport excludes the Footer and its spacing, including after resizing. Extremely small windows clip the layout to the available cells.

### Task Detail

Task Detail has only Title and Description fields, with no Status row. Its border reflects the current status: TODO uses accent, DOING warning, and DONE success.

| Detail key (outside editing) | Action |
| --- | --- |
| `j` / Down, Tab | Focus the next field (Title / Description) |
| `k` / Up, Shift+Tab | Focus the previous field |
| `J` / `K` | Scroll the description down / up |
| PageDown / PageUp | Scroll the description by a viewport |
| `g` / `G` | Scroll to the top / bottom of the description |
| Enter | Edit the focused field |
| `<` / `>` | Immediately save the previous / next status |
| `d` | Confirm task deletion |
| Esc | Return to the board |
| `q` / Ctrl-C | Close kanban |
| `?` | Open keybinding help |

Status changes are bounded by `todo`, `doing`, and `done`: they do not wrap or open an editor. Successful changes update the border and make board selection follow the task by ID; failures leave the task unchanged and display an error. Returning to the board preserves selection and scroll position, subject to reloading and clamping.

### Create

On the board, `n` opens Create in normal field-selection mode. Only Title and Description are selectable; there is no Status or Create field.

| Create key (outside editing) | Action |
| --- | --- |
| `j` / Down, Tab | Focus the next field (Title / Description) |
| `k` / Up, Shift+Tab | Focus the previous field |
| Enter | Edit the focused field |
| `s` | Explicitly create the task |
| Esc | Discard the form and return to the board |
| `q` / Ctrl-C | Close kanban without creating a task |
| `?` | Open keybinding help |

`s` sends only Title and Description to the Store; status defaults to `todo`. Success opens the new task in Task Detail and selects it on the board. Failure keeps Create open, preserves both drafts, and displays the error. Finishing a field edit does not create a task.

### Field editing and modal keys

| Title-edit key | Action |
| --- | --- |
| Enter | Save the title in Detail / finish the draft in Create |
| Esc | Cancel the current title edit |
| `q` | Insert the character `q`, not quit |
| Ctrl-C | Close kanban through Maki's parent-window dismissal |

Description editing opens a temporary file through Maki's external editor lifecycle (`$VISUAL` / `$EDITOR`). Save the file and exit successfully to apply changed text immediately in Detail or retain it as a draft in Create. Exiting without changing the file leaves the description unchanged. A nonzero editor exit or a read/save failure displays an error without applying the change; the temporary file is removed afterward.

Help is modal on the board, in Detail, and in Create: `?` or Esc closes it, Ctrl-C quits kanban, and all other keys (including `q`) are consumed without their normal actions. Help is centered and recomputes its size and position after resizing; narrow windows clip its contents safely.

On the board or in Detail, `d` asks for deletion confirmation. Only `y` confirms. Every other key, including `q`, Esc, and Ctrl-C, cancels confirmation and is consumed rather than performing its normal action. Successful deletion reloads the board; Detail returns to it. Selection falls back to the same index in the original column, clamped to the last remaining task, or no task if the column is empty. Failure displays an error and keeps the current view open so you can retry.

Detail and Create have an independent Footer box showing mode, hints, errors, or deletion confirmation. The description viewport excludes the Footer and its spacing and is recomputed on resize; small windows clip safely.

The agent tools are batch-first; tool names are unchanged:

- `task_list({})` — list every task as a JSON array, including its ID.
- `task_get({"ids":["task-1","task-2"]})` — read tasks by ID.
- `task_create({"tasks":[{"title":"Implement login","description":"Add login UI"},{"title":"Add tests"}]})` — create tasks with required `title` and optional `description`; IDs are generated and status defaults to `todo`.
- `task_update({"tasks":{"task-1":{"status":"doing"},"task-2":{"title":"Add login tests"}}})` — pass an ID-keyed object of patches. Each patch must contain at least one of `title`, `description`, or `status`; the Store rejects empty patches. Omitted fields remain unchanged and any legal status is allowed directly.
- `task_delete({"ids":["task-1","task-2"]})` — delete tasks by ID and return their deleted values.

Get, create, update, and delete return ID-keyed JSON objects. For a single task, use the same batch schema with a one-item array (`ids` or create `tasks`) or a one-entry update `tasks` object; there is no separate single-task argument form. Batches are all-or-nothing: any invalid item or missing requested ID fails the whole call. Mutations validate the whole batch before one atomic write, with no partial changes.

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

The stored `tasks` value is an ID-to-task object, not an array; the task body does not contain an ID. `task_list` responses include IDs in task bodies; the other tool responses use IDs as object keys.

## Statuses

`todo`, `doing`, `done` (represented by accent, warning, and success borders in Task Detail; there is no Status row).

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
2. Create a task through `task_create({"tasks":[{"title":"实现登录页面","description":"添加基础登录 UI"}]})`; confirm `task-1`, `todo`, and an ID-keyed JSON object with no body ID.
3. `task_list({})` must include the ID in the task body; `task_get({"ids":["task-1"]})` must return it as an object key.
4. Call `task_update({"tasks":{"task-1":{"status":"doing"}}})`, then repeat with `done`; check the returned task, JSON, and `/kanban` column after each step.
5. Call `task_update({"tasks":{"task-1":{"title":"Login page","description":"Login UI"}}})`; omitted fields must remain unchanged.
6. Try `task_update({"tasks":{"task-1":{"status":"blocked"}}})`, `task_get({"ids":["task-1","missing-id"]})`, and `task_update({"tasks":{"task-1":{"status":"todo"},"missing-id":{"status":"doing"}}})`; all must report errors without modifying the file. Also reject `task_update({"tasks":{"task-1":{}}})`. Create a second task and check multi-item get/update and `task_delete({"ids":["task-1","task-2"]})`; returned objects must be keyed by ID.
7. Replace the JSON with invalid text, call `task_list` and open `/kanban`; expect an explicit error and the original invalid bytes to remain.
8. On `/kanban`, open Create with `n`, edit Title and Description with Enter, and create with `s`; confirm the new Task Detail opens. Return with Esc, reopen with Enter, and try `d` → `n`, `d` → Esc, then `d` → `y`. Check selection after deleting a middle task and the last task in a column. Create another task and use `>`, `>`, `<`, `<`; selection must follow it. Repeat in a narrow single-column window and resize while moving. Try deleting/moving with malformed JSON and verify its bytes remain unchanged.
9. Temporarily change the window title in `lua/kanban/ui.lua`, execute `/reload`, open `/kanban` and confirm the new title. Restore the code and reload again.

In this development environment the installed Maki 0.5.7 CLI confirmed registration and the agent tools performed steps 1–3, the status/text updates and error checks; the corrupt JSON remained intact. An interactive TUI is required to visually verify the window and to execute `/reload`: those interactive checks have not been independently confirmed here.

## MVP limitations

There is no subagent tracking, execution hooks, or concurrent write protection. There are no additional task fields or backend service.
