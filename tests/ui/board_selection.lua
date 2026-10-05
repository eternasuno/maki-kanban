--# selene: allow(undefined_variable, unscoped_variables)
fake.result =
  board({ "task-1", "task-2", "task-3", "task-4", "task-5", "task-6", "task-7", "task-8", "task-9", "task-10" })
local retained = Board.new(90, 8)
retained:reload(fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
local selected_before = retained:selected_task()
local before = row(retained:render(), 3)
retained:handle_key("l", fake)
retained:handle_key("h", fake)
check(
  retained:selected_task() == selected_before and row(retained:render(), 3) == before,
  "board preserves selection and scroll offset across focus change"
)

local by_id = Board.new(90, 8)
fake.result = board({ "task-1", "task-2", "task-3" })
by_id:reload(fake)
by_id:handle_key("j", fake)
fake.result = board({ "task-0", "task-1", "task-2", "task-3" })
by_id:reload(fake)
check(by_id:selected_task().id == "task-2", "reload preserves selected ID after insertion before it")
fake.result = board({ "task-0", "task-2", "task-3" })
by_id:reload(fake)
check(by_id:selected_task().id == "task-2", "reload preserves selected ID after deletion before it")
by_id:select_task("task-3")
check(by_id:selected_task().id == "task-3" and by_id._state.focused_column == 1, "select_task focuses matching ID")
fake.result = board({ "task-0", "task-1" })
by_id:reload(fake)
check(by_id:selected_task().id == "task-1", "deleted selection falls back to clamped old index")
fake.result = { tasks = {} }
by_id:reload(fake)
check(by_id:selected_task() == nil and by_id._state.offsets[1] == 0, "empty reload clamps selection and offset")

for _, key in ipairs({ "q", "<C-c>" }) do
  fake.result = { tasks = { ["task-1"] = { title = "Open detail", description = "text", status = "todo" } } }
  local reached = false
  run({
    { type = "key", key = "<CR>" },
    function()
      check(
        snapshot():find("─ Task", 1, true) and snapshot():find("Open detail", 1, true) and not last_win.closed,
        "detail is open before quit"
      )
    end,
    { type = "key", key = key },
    function()
      reached = true
    end,
  })
  check(
    last_win.closed and not reached and snapshot():find("Esc back", 1, true),
    key .. " closes detail immediately without returning to board"
  )
end
