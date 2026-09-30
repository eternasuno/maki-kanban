# Project guidance

## Scope and structure

maki-kanban is a Lua plugin for Maki 0.5.7+. Tasks represent project-level user work, not agent execution steps.

- `plugin/kanban.lua`: auto-loaded entrypoint registering tools and `/kanban`.
- `plugin.toml`: host version and filesystem permissions.
- `lua/kanban/store.lua`: validation, IDs, persistence and batch CRUD; shared by tools and UI.
- `lua/kanban/tools.lua`: tool schemas and JSON/error responses.
- `lua/kanban/ui.lua`: window lifecycle and event routing.
- `lua/kanban/ui/board.lua`: board rendering, selection and batch actions.
- `lua/kanban/ui/task.lua`: detail/create forms and field editing.
- `tests/store.lua`, `tests/ui.lua`: standalone regression scripts with Maki API shims.

## Change guardrails

- Keep validation and persistence in Store; tools and UI should call its APIs.
- The default store is `.maki/kanban.json` relative to the Maki process working directory, not the plugin checkout. Use disposable projects for integration checks; preserve existing task data.
- Persist an ID-keyed `tasks` object with `title`, `description` and `status` fields. Stored bodies omit IDs; public task objects include `id`.
- Preserve whole-batch validation before one atomic write. Invalid input, missing requested IDs, corrupt data and write failures must leave persisted task data unchanged. Atomic writes do not provide concurrent read-modify-write coordination.
- Reload persisted state for each operation. Titles must be nonblank; descriptions default to an empty string; statuses are `todo`, `doing`, `done`. Creation starts in `todo`; updates preserve omitted fields and reject empty patches.
- IDs use the lowest available `task-N`, including reuse after deletion. `task_list` returns an array, including `[]` when empty; other tools return ID-keyed objects.
- Keep UI status moves bounded, deletion confirmed and errors visible. Preserve selection/marks by task ID where applicable and clamp selection/scroll offsets after reload or resize.
- Use Maki display-width and truncation helpers for layout rather than byte lengths. Verify narrow windows and resizing when changing rendering.
- Title editing uses `maki.text_input`; description editing uses the host external editor lifecycle. Clean up temporary files and retain drafts on failed saves.
- Task-reference insertion closes the window before editing Maki input and retains session/input-version guards.

## Verification

Run from the repository root:

```sh
lua tests/store.lua
lua tests/ui.lua
```

Add regression coverage to the corresponding script when changing behavior. The scripts use host shims; passing them does not verify the real interactive UI.

For host integration changes, use a disposable working directory and check registration with `maki prompt --tools --names`, then open `/kanban`. For UI changes, exercise affected actions, error paths, narrow layouts and resizing. Use interactive `/reload` after Lua edits; report any manual checks that were not performed.

See `README.md` for installation, user keybindings and tool call examples. Keep those descriptions aligned with the implementation.
