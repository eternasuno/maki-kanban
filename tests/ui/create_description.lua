--# selene: allow(undefined_variable, unscoped_variables)
reset_editor()
fake.result = { tasks = { ["task-1"] = { title = "Existing", description = "", status = "todo" } } }
local updates_before, lists_before = #fake.updates, fake.calls
local description_creates = fake.creates
maki.ui.open_editor = function(path)
  check(editor.files[path] == "", "create description editor starts with empty draft")
  editor.files[path] = "first\n第二行"
  return 0
end
observed = {}
run({
  { type = "key", key = "l" },
  { type = "key", key = "n" },
  function()
    observed.open = snapshot()
  end,
  { type = "paste", text = "ignored" },
  { type = "key", key = "<Enter>" },
  { type = "paste", text = "With description" },
  { type = "key", key = "<Enter>" },
  { type = "key", key = "<Tab>" },
  { type = "key", key = "<Enter>" },
  function()
    check(
      fake.creates == description_creates and #fake.updates == updates_before,
      "description draft does not write Store before Create"
    )
  end,
  { type = "key", key = "s" },
  function()
    observed.selected = selected_title()
  end,
  function()
    observed.detail = snapshot()
  end,
  { type = "key", key = "q" },
})
check(observed.open:find("─ Create", 1, true) and observed.open:find("Esc back", 1, true), "n opens create flow")
check(
  fake.result.tasks["task-2"].description == "first\n第二行" and fake.result.tasks["task-2"].status == "todo",
  "description creation stores draft and fixed TODO status"
)
check(
  fake.calls == lists_before + 1 and observed.detail:find("With description", 1, true),
  "creation opens new task without reloading hidden board"
)
check(#editor.removes == 1 and next(editor.files) == nil, "create description removes temporary file")
maki.ui.open_editor = description_open

for _, title in ipairs({ "", "   " }) do
  local invalid = Task.new_create(80, 12)
  invalid:handle_key("<CR>", fake)
  invalid:handle_paste(title)
  invalid:handle_key("<CR>", fake)
  invalid:handle_key("<Tab>", fake)
  invalid:handle_key("<Tab>", fake)
  local attempts = fake.creates
  check(
    invalid:handle_key("s", fake) == true
      and fake.creates == attempts + 1
      and invalid.error == "title must not be empty",
    "Store rejects empty/whitespace create title"
  )
  check(
    invalid.task.title == title and row(invalid:render(), 11):find("title must not be empty", 1, true),
    "invalid create retains input and renders Store error"
  )
end

reset_editor()
local failed_create = Task.new_create(80, 12)
failed_create:handle_key("<CR>", fake)
failed_create:handle_paste("Retained title")
failed_create:handle_key("<CR>", fake)
failed_create:handle_key("<Tab>", fake)
maki.ui.open_editor = function(path)
  editor.files[path] = "Retained description"
  return 0
end
failed_create:handle_key("<CR>", fake)
failed_create:handle_key("<Tab>", fake)
fake.create_error = "write failed"
check(
  failed_create:handle_key("s", fake) == true
    and failed_create.creating
    and failed_create.task.title == "Retained title"
    and failed_create.task.description == "Retained description",
  "Store create failure keeps create UI and both drafts"
)
check(row(failed_create:render(), 11):find("write failed", 1, true), "create failure displays error")
fake.create_error = nil
check(
  failed_create:handle_key("s", fake) == "created" and failed_create.task.status == "todo",
  "failed creation can retry successfully"
)
maki.ui.open_editor = description_open

for _, failure in ipairs({ "false", "throw" }) do
  reset_editor()
  local creating = Task.new_create(80, 12)
  creating.task.title = "Cleanup " .. failure
  creating.task.description = "old description"
  creating.focused_field = "description"
  local draft = "new description " .. failure .. "\n中文"
  maki.ui.open_editor = function(path)
    editor.files[path] = draft
    return 0
  end
  maki.fs.rm = function(path)
    editor.removes[#editor.removes + 1] = path
    if failure == "throw" then
      error("cleanup threw")
    end
    return false, "cleanup failed"
  end
  check(creating:handle_key("<CR>", fake) == true, "create handles cleanup failure: " .. failure)
  check(
    creating.task.description == draft
      and creating.description_draft == nil
      and #editor.removes == 1
      and row(creating:render(), 11):find("cleanup", 1, true),
    "create retains new text and renders cleanup error: " .. failure
  )
  creating:handle_key("<Tab>", fake)
  creating:handle_key("<CR>", fake)
  creating:handle_paste(" title")
  creating:handle_key("<CR>", fake)
  check(row(creating:render(), 11):find("cleanup", 1, true), "title draft save keeps cleanup error: " .. failure)
  check(
    creating:handle_key("s", fake) == "created"
      and fake.result.tasks[creating.task.id].description == draft
      and row(creating:render(), 11):find("cleanup", 1, true),
    "create persists new description without hiding cleanup error: " .. failure
  )
  creating:handle_key("<CR>", fake)
  creating:handle_paste(" saved")
  check(creating:handle_key("<CR>", fake) == "changed", "normal title saves after creation: " .. failure)
  check(row(creating:render(), 11):find("cleanup", 1, true), "normal title save keeps cleanup error: " .. failure)
end
reset_editor()
maki.ui.open_editor = description_open

local cancel_creates = fake.creates
observed = {}
run({
  { type = "key", key = "n" },
  { type = "key", key = "<Esc>" },
  function()
    observed.cancel_flow = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  fake.creates == cancel_creates
    and observed.cancel_flow:find("TODO", 1, true)
    and not observed.cancel_flow:find("─ Create", 1, true),
  "Esc exits field selection to board without creating"
)

run({
  { type = "key", key = "n" },
  { type = "key", key = "<Enter>" },
  { type = "paste", text = "Cancel me" },
  { type = "key", key = "<Esc>" },
  function()
    observed.cancel_edit = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.cancel_flow = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  fake.creates == cancel_creates
    and observed.cancel_edit:find("─ Create", 1, true)
    and not observed.cancel_edit:find("Cancel me", 1, true),
  "Esc cancels title draft without creating or leaving create view"
)
check(
  observed.cancel_flow:find("TODO", 1, true) and not observed.cancel_flow:find("─ Create", 1, true),
  "second Esc exits creation to board"
)
