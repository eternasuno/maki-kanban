local script = (arg and arg[0]) or "tests/ui.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/lua/?.lua;" .. package.path
local harness = assert(loadfile(root .. "/tests/ui/harness.lua"))()
local groups = {
  "board_layout",
  "detail_events",
  "board_multiselect",
  "detail_layout",
  "board_selection",
  "title_status",
  "description_editor",
  "detail_save_events",
  "create_title",
  "selection_reload",
  "create_description",
  "create_resize",
  "detail_delete",
  "board_move",
  "board_delete",
  "board_rendering",
  "board_help",
  "quit_events",
  "task_help",
  "task_scrolling",
  "task_modal_events",
  "task_retry_events",
  "description_retry",
  "task_cache",
  "board_lazy",
}
local passed, failed = 0, 0
if arg and #arg > 0 then
  groups = arg
end
for _, name in ipairs(groups) do
  assert(name:match("^[%w_]+$"), "invalid group name")
  local p, f = harness.run(root, name)
  passed, failed = passed + p, failed + f
end
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
