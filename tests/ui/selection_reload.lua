--# selene: allow(undefined_variable, unscoped_variables)
local by_id, retained = Board.new(90, 8), Board.new(90, 8)
fake.result = board({ "task-1", "task-2", "task-3" })
by_id:reload(fake)
by_id:select_task("task-2")
fake.result.tasks["task-2"].status = "doing"
by_id:reload(fake)
check(
  by_id._state.focused_column == 1 and by_id:selected_task().id == "task-3",
  "moved selection stays in original column with valid fallback"
)
fake.result.tasks["task-1"].status = "doing"
fake.result.tasks["task-3"].status = "doing"
by_id:reload(fake)
check(
  by_id._state.focused_column == 1 and by_id:selected_task() == nil and by_id._state.selected[1] == 1,
  "moving last tasks leaves valid empty original column"
)
by_id:select_task("task-2")
fake.result.tasks["task-0"] = { title = "Inserted", status = "doing" }
by_id:reload(fake)
check(
  by_id._state.focused_column == 2 and by_id:selected_task().id == "task-2",
  "reload preserves non-TODO column selection by ID"
)
by_id:handle_key("h", fake)
by_id:reload(fake)
by_id:handle_key("l", fake)
check(by_id:selected_task().id == "task-2", "reload preserves unfocused column selection by ID")
retained:reload(fake)
retained:select_task("task-3")
local offset_before = retained._state.offsets[2]
retained:reload(fake)
check(retained._state.offsets[2] == offset_before, "unchanged reload retains legal scroll offset")
