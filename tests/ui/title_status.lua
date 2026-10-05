--# selene: allow(undefined_variable, unscoped_variables)
local edit_task = { id = "task-1", title = "abc", description = "old", status = "todo" }
local edit = Task.new(edit_task, 30, 12)
for _, key in ipairs({ "j", "k", "<Down>", "<Up>", "<Tab>", "<S-Tab>" }) do
  edit.focused_field, edit.offset = "title", 0
  check(
    edit:handle_key(key, fake) and edit.focused_field == "description" and edit.offset == 0,
    key .. " selects description without scrolling"
  )
  check(
    edit:handle_key(key, fake) and edit.focused_field == "title" and edit.offset == 0,
    key .. " wraps to title without scrolling"
  )
end
edit.focused_field = "title"
fake.result = { tasks = { ["task-1"] = { title = "abc", description = "old", status = "todo" } } }
fake.update_error = nil
check(edit:handle_key("<CR>", fake) and edit.editing == "title", "Enter begins title editing")
check(cursor(edit).text == " " and cursor(edit).column == 6, "existing title shows trailing cursor")
check(edit:render()[2][2][2].fg == "#7799ff", "editing title marker uses accent color")
check(edit:render()[2][3][2].fg == "#eeeeee", "editing title text keeps foreground color")
for _, move in ipairs({ { "<Left>", "c", 5 }, { "<Home>", "a", 3 }, { "<Right>", "b", 4 }, { "<End>", " ", 6 } }) do
  edit:handle_key(move[1], fake)
  local current = cursor(edit)
  check(current.text == move[2] and current.column == move[3], move[1] .. " moves visible title cursor")
end
check(
  edit:handle_key("<Left>", fake)
    and edit:handle_key("<BS>", fake)
    and edit:handle_paste("x\ny")
    and edit.title_input:value() == "ax yc",
  "title cursor editing and newline paste"
)
check(edit:handle_key("<Esc>", fake) and edit.task.title == "abc" and not edit.editing, "title cancel discards draft")
check(not cursor(edit), "cancel removes title cursor")
check(edit:render()[2][2][2].fg == "#eeeeee", "cancel restores title marker foreground")
edit:handle_key("<CR>", fake)
edit:handle_paste("new")
fake.update_error = "no title write"
check(
  edit:handle_key("<Enter>", fake)
    and edit.editing == "title"
    and edit.error == "no title write"
    and edit.title_input:value() == "abcnew"
    and edit.task.title == "abc",
  "title update failure keeps editing and error"
)
check(cursor(edit).text == " " and cursor(edit).column == 9, "failed title save retains draft cursor")
check(edit:render()[2][2][2].fg == "#7799ff", "failed title save retains accent marker")
fake.update_error = nil
edit:handle_key("<Esc>", fake)
edit:handle_key("<CR>", fake)
for _ = 1, 3 do
  edit:handle_key("<BS>", fake)
end
check(
  edit:handle_key("<CR>", fake)
    and edit.editing == "title"
    and edit.title_input:value() == ""
    and edit.error == "title must not be empty"
    and edit.task.title == "abc",
  "empty title save fails without losing input"
)
edit:handle_key("<Esc>", fake)

edit:handle_key("<CR>", fake)
local literal_updates = #fake.updates
check(
  edit:handle_key("q", fake)
    and edit.title_input:value() == "abcq"
    and edit.editing == "title"
    and #fake.updates == literal_updates,
  "q is literal text during title editing"
)
check(
  edit:handle_key("<Enter>", fake) == "changed"
    and edit.task.title == "abcq"
    and not edit.editing
    and #fake.updates == literal_updates + 1,
  "Enter saves title and exits editing"
)
check(not cursor(edit), "successful title save removes cursor")
check(edit:render()[2][2][2].fg == "#eeeeee", "successful save restores title marker foreground")
edit:handle_key("<CR>", fake)
check(
  edit:handle_key("<C-c>", fake) == "quit" and #fake.updates == literal_updates + 1,
  "Ctrl-C quits title editing without saving"
)
edit:handle_key("<Esc>", fake)
edit.focused_field = "description"
local status_updates = #fake.updates
check(
  edit:handle_key("<", fake) == true and #fake.updates == status_updates and edit.task.status == "todo",
  "detail lower status boundary is a no-op"
)
for _, move in ipairs({ { ">", "doing" }, { ">", "done" }, { "<", "doing" }, { "<", "todo" } }) do
  check(
    edit:handle_key(move[1], fake) == "changed"
      and edit.task.status == move[2]
      and edit.focused_field == "description"
      and not edit.editing,
    "detail status changes immediately without changing focus"
  )
  local update, fields = fake.updates[#fake.updates], 0
  for _ in pairs(update["task-1"]) do
    fields = fields + 1
  end
  check(
    update["task-1"] and fields == 1 and update["task-1"].status == move[2],
    "detail status sends status-only patch"
  )
  if move[2] == "done" then
    local count = #fake.updates
    check(
      edit:handle_key(">", fake) == true and #fake.updates == count and edit.task.status == "done",
      "detail upper status boundary does not wrap"
    )
  end
end
fake.update_error = "status failed"
local old_task, old_focus, old_offset = edit.task, edit.focused_field, edit.offset
check(
  edit:handle_key(">", fake) == true
    and edit.error == "status failed"
    and edit.task == old_task
    and edit.task.status == "todo"
    and edit.focused_field == old_focus
    and edit.offset == old_offset
    and not edit.editing,
  "status failure preserves task focus and viewport"
)
check(row(edit:render(), 11):find("Error: status failed", 1, true), "status failure renders prefixed footer error")
fake.update_error = nil
