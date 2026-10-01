--# selene: allow(undefined_variable, unscoped_variables)
fake.result = { tasks = { ["task-1"] = { title = "Retry", description = "persisted", status = "todo" } } }
local task = Task.new({ id = "task-1", title = "Retry", description = "persisted", status = "todo" }, 30, 12)
task.focused_field = "description"
local original_task = task.task
local seeds = {}
maki.ui.open_editor = function(path)
  seeds[#seeds + 1] = editor.files[path]
  editor.files[path] = "edited\n中文 draft"
  return 0
end
fake.update_error = "disk full"
check(task:handle_key("<CR>", fake) == true, "failed description save stays in detail")
check(
  task.task == original_task
    and task.task.description == "persisted"
    and fake.result.tasks["task-1"].description == "persisted",
  "failed save preserves displayed and persisted text"
)
check(
  task.description_draft == "edited\n中文 draft" and task.error == "disk full",
  "failed save retains exact editor draft"
)
check(next(editor.files) == nil and #editor.removes == 1, "failed Store save still cleans editor file")
fake.update_error = nil
maki.ui.open_editor = function(path)
  seeds[#seeds + 1] = editor.files[path]
  return 0
end
check(task:handle_key("<CR>", fake) == "changed", "unchanged retry editor content is saved")
check(
  seeds[1] == "persisted" and seeds[2] == "edited\n中文 draft",
  "retry editor receives retained draft instead of persisted text"
)
check(
  task.task.description == seeds[2]
    and fake.result.tasks["task-1"].description == seeds[2]
    and task.description_draft == nil
    and task.error == nil,
  "successful retry persists draft and clears error"
)
check(
  #fake.updates == 2 and next(editor.files) == nil and #editor.removes == 2,
  "retry performs one new save and cleans file"
)

local update = fake.update_many
fake.update_many = function()
  error("Store threw")
end
maki.ui.open_editor = function(path)
  editor.files[path] = "second draft"
  return 0
end
check(
  task:handle_key("<CR>", fake) == true and task.error:find("Store threw", 1, true),
  "thrown Store error stays visible"
)
check(
  task.description_draft == "second draft"
    and fake.result.tasks["task-1"].description == seeds[2]
    and next(editor.files) == nil,
  "thrown save retains draft and cleans file without persistence"
)
fake.update_many = update
maki.ui.open_editor = description_open
check(
  task:handle_key("<CR>", fake) == "changed" and task.task.description == "second draft",
  "thrown save can retry same seeded content"
)

for _, failure in ipairs({ "false", "throw" }) do
  reset_editor()
  local persisted = task.task.description
  local updates = #fake.updates
  local draft = "cleanup " .. failure .. "\n中文 draft"
  maki.ui.open_editor = function(path)
    editor.files[path] = draft
    return 0
  end
  maki.fs.rm = function()
    if failure == "throw" then
      error("cleanup threw")
    end
    return false, "cleanup failed"
  end
  check(task:handle_key("<CR>", fake) == true, "cleanup failure stays in detail: " .. failure)
  check(
    task.description_draft == draft and task.error:find("cleanup", 1, true),
    "cleanup failure retains read text and reports error: " .. failure
  )
  check(
    task.task.description == persisted
      and fake.result.tasks["task-1"].description == persisted
      and #fake.updates == updates,
    "cleanup failure does not update Store: " .. failure
  )
  maki.fs.rm = editor_rm
  for _, facility in ipairs({ "write", "open_editor", "read" }) do
    local owner = facility == "open_editor" and maki.ui or maki.fs
    local original = owner[facility]
    owner[facility] = function()
      error(facility .. " threw")
    end
    check(
      task:handle_key("<CR>", fake) == true
        and task.description_draft == draft
        and task.error:find(facility .. " threw", 1, true)
        and #fake.updates == updates,
      "failed " .. facility .. " preserves existing cleanup draft: " .. failure
    )
    owner[facility] = original
  end
  maki.ui.open_editor = function(path)
    check(editor.files[path] == draft, "cleanup retry receives retained draft: " .. failure)
    return 0
  end
  check(task:handle_key("<CR>", fake) == "changed", "cleanup failure retries successfully: " .. failure)
  check(
    task.task.description == draft
      and fake.result.tasks["task-1"].description == draft
      and #fake.updates == updates + 1
      and task.description_draft == nil
      and task.error == nil,
    "cleanup retry persists draft and clears error: " .. failure
  )
end
maki.ui.open_editor = description_open

local Editor = require("kanban.ui.editor")
for _, facility in ipairs({ "write", "open_editor", "read", "rm" }) do
  reset_editor()
  local owner = facility == "open_editor" and maki.ui or maki.fs
  local original = owner[facility]
  owner[facility] = function(path)
    if facility == "rm" then
      editor_rm(path)
    end
    error(facility .. " threw")
  end
  local value, err = Editor.edit("unchanged")
  owner[facility] = original
  local expected = facility == "rm" and "unchanged" or nil
  check(value == expected and err:find(facility .. " threw", 1, true), "editor catches thrown " .. facility)
  check(next(editor.files) == nil and #editor.removes == 1, "editor attempts cleanup after thrown " .. facility)
end
