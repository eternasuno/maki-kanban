--# selene: allow(undefined_variable, unscoped_variables)
local create_task = Task.new_create(30, 12)
check(
  create_task.creating and not create_task.editing and create_task.focused_field == "title",
  "creation starts in title field selection mode"
)
check(
  not create_task:handle_paste("ignored") and create_task.task.title == "",
  "paste is ignored until title editing begins"
)
check(
  create_task:handle_key("<Enter>", fake) and create_task.editing == "title",
  "Enter begins title editing in create mode"
)
create_task:handle_paste("新しい")
check(
  create_task:handle_key("<Enter>", fake) and create_task.task.title == "新しい" and not create_task.editing,
  "Enter stores CJK title draft locally"
)
create_task:handle_key("<Tab>", fake)
check(create_task.focused_field == "description", "creation tabs from title to description")
create_task:handle_key("<Tab>", fake)
check(create_task.focused_field == "title", "creation tabs wrap to title with no create field")

fake.result = {
  tasks = {
    ["task-1"] = { title = "Existing", description = "", status = "todo" },
    ["task-3"] = { title = "Gap", description = "", status = "todo" },
  },
}
fake.create_error = nil
local create_calls = fake.creates or 0
observed = {}
run({
  { type = "key", key = "n" },
  { type = "paste", text = "ignored" },
  { type = "key", key = "<Enter>" },
  { type = "paste", text = "新" },
  { type = "key", key = "<Enter>" },
  function()
    check(
      (fake.creates or 0) == create_calls and snapshot():find("CREATE", 1, true),
      "Enter commits title draft but never creates"
    )
  end,
  { type = "key", key = "s" },
  function()
    observed.created = snapshot()
    check(last_buf.lines[1][1][2].fg == "#7799ff" and not last_win.closed, "created task opens todo detail")
  end,
  { type = "key", key = ">" },
  function()
    observed.moved = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.board = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  fake.creates == create_calls + 1
    and fake.result.tasks["task-2"].title == "新"
    and fake.create_inputs[#fake.create_inputs].description == "",
  "n and s create title-only CJK task"
)
check(
  observed.created:find("─ Task", 1, true)
    and not observed.created:find("CREATE", 1, true)
    and observed.moved:find("新", 1, true)
    and fake.result.tasks["task-2"].status == "doing",
  "creation becomes Detail and immediately allows >"
)
check(
  observed.board:find("DOING · 1", 1, true) and observed.board:find("▸ 新", 1, true),
  "back from created detail selects new ID in moved column"
)
check(
  selected_title() and selected_title():find("新", 1, true) ~= nil,
  "title-only creation selects new ID rather than last index"
)
