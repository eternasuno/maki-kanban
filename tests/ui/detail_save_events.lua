--# selene: allow(undefined_variable, unscoped_variables)
fake.result = { tasks = { ["task-1"] = { title = "Before", description = "d", status = "todo" } } }
local calls_before = fake.calls
run({
  { type = "key", key = "<CR>" },
  { type = "key", key = "<CR>" },
  { type = "key", key = "<End>" },
  { type = "key", key = "X" },
  { type = "key", key = "<CR>" },
  function()
    check(fake.calls == calls_before + 1, "title save does not reload hidden board")
  end,
  { type = "key", key = "<Esc>" },
  { type = "key", key = "q" },
})
check(
  fake.result.tasks["task-1"].title == "BeforeX" and snapshot():find("BeforeX", 1, true),
  "return to board shows saved title"
)

fake.result = { tasks = { ["task-1"] = { title = "Moving", description = "d", status = "todo" } } }
observed = {}
run({
  { type = "key", key = "<CR>" },
  { type = "key", key = ">" },
  function()
    observed.moved = snapshot()
    check(
      last_buf.lines[1][1][2].fg == "#ffaa00" and not last_win.closed,
      "detail status change immediately recolors border"
    )
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.board = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.moved:find("─ Task", 1, true)
    and observed.moved:find("Moving", 1, true)
    and observed.board:find("▸ Moving", 1, true),
  "status change stays detail then back selects moved ID"
)
check(
  fake.result.tasks["task-1"].status == "doing"
    and snapshot():find("DOING · 1", 1, true)
    and snapshot():find("TODO · 0", 1, true),
  "status save moves board card"
)

fake.result = { tasks = { ["task-1"] = { title = "Description", description = "original", status = "todo" } } }
local opened_path
maki.ui.open_editor = function(path)
  opened_path = path
  check(editor.files[path] == "original", "editor receives current description")
  editor.files[path] = "edited\nline"
  return 0
end
calls_before = fake.calls
run({
  { type = "key", key = "<CR>" },
  { type = "key", key = "<Tab>" },
  { type = "key", key = "<CR>" },
  function()
    check(fake.calls == calls_before + 1, "description save does not reload hidden board")
  end,
  { type = "key", key = "<Esc>" },
  { type = "key", key = "<CR>" },
  function()
    check(snapshot():find("edited", 1, true), "reopened task has saved description")
  end,
  { type = "key", key = "q" },
})
check(
  opened_path and fake.result.tasks["task-1"].description == "edited\nline" and not editor.files[opened_path],
  "description save persists and removes temp file"
)
maki.ui.open_editor = description_open
