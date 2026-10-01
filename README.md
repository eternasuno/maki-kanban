# maki-kanban

A project-level Kanban plugin for Maki 0.5.7+. Manage user work through an interactive board or agent tools, with tasks stored locally per project.

## Installation

Add the repository to your global Maki configuration (`~/.config/maki/init.lua`, or the active legacy `~/.maki/init.lua`):

```lua
maki.pack.add({ "https://github.com/eternasuno/maki-kanban" })
```

Restart Maki and approve the package and its `fs_read` / `fs_write` permissions. Use `/packupdate` to update the locked Git revision.

## Usage

Run `/kanban` to open the TODO, DOING and DONE board. Narrow windows show only the focused column. Press `?` for keybinding help.

| Board key | Action |
| --- | --- |
| `h` / Left, `l` / Right | Previous / next column |
| `j` / Down, `k` / Up | Next / previous task |
| `g` / `G` | First / last task in the column |
| Enter | Open task details |
| Space | Mark / unmark a task |
| `<` / `>` | Move the union of marked tasks and the cursor task one status step |
| `n` | Open the create form |
| `a` | Insert `[task:<id>] <title>` references into Maki input without submitting |
| `d` | Confirm deletion of the union of marked tasks and the cursor task |
| `r` | Reload tasks |
| `q` / Esc / Ctrl-C | Close the board |

Marks survive reloads while their task IDs remain in the focused column; switching columns clears marks. Moves, deletes and reference insertion target the union of marked tasks and the cursor task, without duplicates. Moves and deletes are all-or-nothing; moves stop at the first and last status.

### Task details and creation

- Use `j` / `k`, arrows or Tab / Shift+Tab to focus Title or Description; Enter edits the field.
- Title editing: Enter saves the edit, Esc cancels it. In Create, this only updates the draft.
- Description editing opens an external editor through `$VISUAL` / `$EDITOR`. Save and exit successfully to apply changes. If saving fails, the persisted description remains unchanged and the edited text is retained as a draft. Enter on Description opens that draft; exiting successfully retries saving even without further edits. Leaving task details discards the unsaved draft.
- In details, `<` / `>` saves the previous / next status, `d` asks to delete, and Esc returns to the board. Use `J` / `K`, PageDown / PageUp or `g` / `G` to scroll the description.
- In Create, `s` creates the task in `todo`; Esc discards the form. Finishing a field edit does not create a task. Successful editor text is kept even if temporary-file cleanup fails; the cleanup error remains visible after creation.
- Outside field editing, `q` / Ctrl-C closes Kanban. Help is modal: `?` / Esc closes help and Ctrl-C quits. During deletion confirmation, only `y` confirms; every other key cancels.

## Agent tools

Tools use batch arguments, including for a single task:

```text
task_list({})
task_get({"ids":["task-1","task-2"]})
task_create({"tasks":[{"title":"Implement login","description":"Add login UI"},{"title":"Add tests"}]})
task_update({"tasks":{"task-1":{"status":"doing"},"task-2":{"title":"Add login tests"}}})
task_delete({"ids":["task-1","task-2"]})
```

`task_list` returns a JSON array; get/create/update/delete return ID-keyed JSON objects. All returned task objects include `id`, `title`, `description` and `status`.

Creation requires a nonblank title; description is optional and status defaults to `todo`. Update patches must contain at least one of `title`, `description` or `status`; omitted fields remain unchanged. Valid statuses are `todo`, `doing`, `done`. Invalid input or a missing requested ID fails the entire batch without partial changes.

## Storage

Tasks live in `.maki/kanban.json`, relative to the Maki process working directory:

```json
{
  "tasks": {
    "task-1": {
      "title": "Implement login",
      "description": "Add login UI",
      "status": "doing"
    }
  }
}
```

A missing file means an empty board; the first mutation creates it. Invalid JSON or task data is reported rather than overwritten. Mutations use atomic writes, but concurrent writers are not coordinated. Stored task bodies omit IDs; IDs are the object keys.

## Development

Enter the development environment with `devenv shell` (or direnv), then run tests from the repository root:

```sh
just check
just lint
just test
just lua-test
just lua-fmt-check
just lua-lint
```

The Rust integration tests follow `lu-zero/maki-lua-plugin-template`'s test-only Cargo package pattern, loading the plugin through the real Maki `PluginHost` with `PluginPermissions::trusted()`. A separate test grants only the permissions declared in `plugin.toml`. The two Maki dev-dependencies follow the upstream default branch without a `rev` in `Cargo.toml`; `Cargo.lock` records the exact revision tested. Use `cargo update -p maki-lua` to update the shared Maki source, then run the integration suite. CI uses `--locked` for reproducible verification. They cover registration, real filesystem/JSON behavior, batch validation, tool dispatch and window lifecycle. Each test runs in a subprocess with a disposable working directory so the project's `.maki/kanban.json` is never accessed. Rust 1.88 or newer and native build tools are required; the devenv environment supplies Rust and Lua.

Store unit tests use detached in-memory snapshots to cover business rules; real JSON, filesystem and permission behavior is covered by Rust host tests. UI unit tests cover state and layout, while event groups cover key user flows. The Lua scripts use local Maki API shims. `tests/ui.lua` runs isolated behavior groups in `tests/ui/`, each with fresh host, Store, editor and event state. Run selected groups with `lua tests/ui.lua description_retry task_cache board_lazy`; group order does not matter. UI state/editing lives in `board.lua` and `task.lua`, rendering in `board_view.lua` and `task_view.lua`, shared display helpers in `display.lua`, UTF-8 text wrapping in `text.lua`, and external editor cleanup in `editor.lua`. Host integration tests observe UI channels, not terminal rendering. For real-host checks, start Maki in a disposable project directory, verify tool registration with `maki prompt --tools --names`, and exercise `/kanban`, editing, batch actions and resizing. Use interactive `/reload` after Lua changes and `maki --no-jit` for clearer Lua stack traces.

See `AGENTS.md` for project structure and change guardrails.
