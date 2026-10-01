--# selene: allow(undefined_variable, unscoped_variables)
fake.result = { tasks = { ["task-1"] = { title = "abcq", description = "old", status = "todo" } } }
local edit = Task.new({ id = "task-1", title = "abcq", description = "old", status = "todo" }, 30, 12)
reset_editor()
edit.focused_field = "description"
local description_open = maki.ui.open_editor
maki.ui.open_editor = function(path)
  editor.editor_path = path
  editor.files[path] = "updated"
  return 0
end
check(
  edit:handle_key("<CR>", fake) == "changed" and edit.task.description == "updated" and #fake.updates > 0,
  "description success reads and partially updates"
)
maki.ui.open_editor = description_open
reset_editor()
editor.exit_code = 1
check(
  edit:handle_key("<CR>", fake)
    and #editor.removes == 1
    and #editor.reads == 0
    and edit.task.description == "updated"
    and edit.error == "editor exited with status 1",
  "description nonzero exit reports error without reading and removes temporary file"
)
reset_editor()
editor.exit_code = 0
editor.read_error = "read failed"
check(
  edit:handle_key("<CR>", fake) and edit.error == "read failed" and #editor.removes == 1,
  "description read failure is rendered and cleaned up"
)
reset_editor()
editor.exit_code = 0
fake.update_error = "description failed"
local old_open_editor = maki.ui.open_editor
maki.ui.open_editor = function(path)
  editor.editor_path = path
  editor.files[path] = "failed update"
  return 0
end
check(
  edit:handle_key("<CR>", fake) and edit.error == "description failed" and #editor.removes == 1,
  "description update failure is retained and cleaned up"
)
maki.ui.open_editor, fake.update_error = old_open_editor, nil

reset_editor()
editor.write_error = "write failed"
local editor_updates, editor_task = #fake.updates, edit.task
check(
  edit:handle_key("<CR>", fake) == true
    and edit.error == "write failed"
    and edit.task == editor_task
    and edit.task.description == "updated",
  "description temporary write failure preserves task and reports error"
)
check(
  #editor.writes == 1 and #editor.removes == 1 and editor.removes[1] == editor.writes[1] and next(editor.files) == nil,
  "description temporary write failure removes partially written file"
)
check(
  editor.editor_path == nil
    and #editor.reads == 0
    and #fake.updates == editor_updates
    and edit.focused_field == "description"
    and not edit.editing,
  "description temporary write failure skips editor read and Store update"
)
check(
  row(edit:render(), 11):find("Error: write failed", 1, true),
  "description temporary write failure renders footer error"
)
reset_editor()
edit.description_draft = nil
check(
  edit:handle_key("<CR>", fake) == true
    and edit.error == nil
    and edit.task == editor_task
    and edit.task.description == "updated"
    and #fake.updates == editor_updates,
  "successful unchanged description clears error without replacing task or updating Store"
)
check(
  #editor.writes == 1
    and editor.editor_path == editor.writes[1]
    and #editor.reads == 1
    and editor.reads[1] == editor.editor_path,
  "unchanged description opens editor and reads original content"
)
check(
  #editor.removes == 1
    and editor.removes[1] == editor.editor_path
    and next(editor.files) == nil
    and edit.focused_field == "description"
    and not edit.editing,
  "unchanged description cleans temporary file and retains field selection"
)
reset_editor()
