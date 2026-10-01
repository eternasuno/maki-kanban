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

-- Returning from Detail follows the opened ID, including changes made elsewhere.
fake.result = board({ "task-1", "task-2", "task-3" })
local lists_before = fake.calls
run({
  { type = "key", key = "j" },
  { type = "key", key = "<CR>" },
  function()
    fake.result.tasks["task-2"].status = "done"
    fake.result.tasks["task-2"].title = "Externally moved"
  end,
  { type = "key", key = "<Esc>" },
  function()
    check((selected_title() or ""):find("▸ Externally moved", 1, true), "Detail return follows externally moved ID")
    check(fake.calls == lists_before + 2, "Detail return reloads board exactly once")
  end,
  { type = "key", key = "<CR>" },
  function()
    check(snapshot():find("Externally moved", 1, true), "reopening uses fresh external task data")
  end,
  { type = "key", key = "q" },
})

for _, deleted_in_detail in ipairs({ false, true }) do
  fake.result = board({ "task-1", "task-2", "task-3" })
  lists_before = fake.calls
  local events = {
    { type = "key", key = "j" },
    { type = "key", key = "<CR>" },
  }
  if deleted_in_detail then
    events[#events + 1] = { type = "key", key = "d" }
    events[#events + 1] = { type = "key", key = "y" }
  else
    events[#events + 1] = function()
      fake.result.tasks["task-2"] = nil
    end
    events[#events + 1] = { type = "key", key = "<Esc>" }
  end
  events[#events + 1] = function()
    check(
      (selected_title() or ""):find("▸ Title task-3", 1, true),
      "deleted return ID falls back to surviving selection"
    )
    check(fake.calls == lists_before + 2, "deleted Detail return reloads board exactly once")
  end
  events[#events + 1] = { type = "key", key = "q" }
  run(events)
end

fake.result = board({ "task-1", "task-2", "task-3" })
lists_before = fake.calls
run({
  { type = "key", key = "j" },
  { type = "key", key = "<CR>" },
  { type = "key", key = ">" },
  { type = "key", key = "<CR>" },
  { type = "key", key = "<End>" },
  { type = "key", key = "X" },
  { type = "key", key = "<CR>" },
  { type = "key", key = ">" },
  function()
    check(fake.calls == lists_before + 1, "multiple saves and status changes never reload hidden board")
    fake.error = "return reload failed"
  end,
  { type = "key", key = "<Esc>" },
  function()
    check(snapshot():find("return reload failed", 1, true), "return reload error is visible")
    fake.error = nil
    fake.result.tasks["task-2"].status = "doing"
  end,
  { type = "key", key = "r" },
  function()
    check(
      (selected_title() or ""):find("▸ Title task-2X", 1, true),
      "reload recovery retains saved return ID across external movement"
    )
    check(not snapshot():find("return reload failed", 1, true), "reload recovery clears error")
  end,
  { type = "key", key = "j" },
  { type = "key", key = "h" },
  { type = "key", key = "r" },
  function()
    check(
      (selected_title() or ""):find("▸ Title task-1", 1, true),
      "successful return consumes pending focus before later board reload"
    )
  end,
  { type = "key", key = "q" },
})

fake.result = board({ "task-1" })
lists_before = fake.calls
run({
  { type = "key", key = "l" },
  { type = "key", key = "n" },
  { type = "key", key = "<CR>" },
  { type = "paste", text = "Created selection" },
  { type = "key", key = "<CR>" },
  { type = "key", key = "s" },
  { type = "key", key = ">" },
  { type = "key", key = ">" },
  function()
    check(fake.calls == lists_before + 1, "create and subsequent status saves do not reload hidden board")
  end,
  { type = "key", key = "<Esc>" },
  function()
    check(
      (selected_title() or ""):find("▸ Created selection", 1, true),
      "Create return selects new ID in final status column"
    )
    check(snapshot():find("DONE · 1", 1, true), "Create return shows latest status")
  end,
  { type = "key", key = "q" },
})
