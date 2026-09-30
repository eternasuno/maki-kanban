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
| `<` / `>` | Move marked tasks one status step, or the selected task if none are marked |
| `n` | Open the create form |
| `a` | Insert `[task:<id>] <title>` references into Maki input without submitting |
| `d` | Confirm deletion of marked tasks, or the selected task |
| `r` | Reload tasks |
| `q` / Esc / Ctrl-C | Close the board |

Marks survive reloads while their task IDs exist. Moves and deletes are all-or-nothing; a move fails if any targeted task is already at the requested status boundary. Reference insertion uses marked tasks, or the selected task when none are marked.

### Task details and creation

- Use `j` / `k`, arrows or Tab / Shift+Tab to focus Title or Description; Enter edits the field.
- Title editing: Enter saves the edit, Esc cancels it. In Create, this only updates the draft.
- Description editing opens an external editor through `$VISUAL` / `$EDITOR`. Save and exit successfully to apply changes; failed edits leave the description unchanged.
- In details, `<` / `>` saves the previous / next status, `d` asks to delete, and Esc returns to the board. Use `J` / `K`, PageDown / PageUp or `g` / `G` to scroll the description.
- In Create, `s` creates the task in `todo`; Esc discards the form. Finishing a field edit does not create a task.
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

Run regression tests from the repository root:

```sh
lua tests/store.lua
lua tests/ui.lua
```

The scripts use local Maki API shims. For real-host checks, start Maki in a disposable project directory, verify tool registration with `maki prompt --tools --names`, and exercise `/kanban`, editing, batch actions and resizing. Use interactive `/reload` after Lua changes and `maki --no-jit` for clearer Lua stack traces.

See `AGENTS.md` for project structure and change guardrails.
