--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1", "task-2", "task-3" })
fake.result.tasks["task-1"].status = "doing"
fake.result.tasks["task-2"].status = "doing"
local moving = Board.new(80, 12)
moving:reload(fake)
moving:select_task("task-3")
local function check_board_selection(lines, color)
  local selected_row, focused_top, focused_bottom = false, false, false
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      for i, span in ipairs(line) do
        local style = span[2]
        if span[1]:find("▸ ", 1, true) then
          selected_row = true
          check(
            style.fg == color and style.bold and not style.bg,
            "selected marker and title follow status color without background"
          )
          for _, border in ipairs({ line[i - 1], line[i + 1] }) do
            check(
              border[1] == "│" and border[2].fg == color and border[2].bold and not border[2].bg,
              "focused side borders match selected task color"
            )
          end
        elseif span[1]:find("Title task-", 1, true) then
          check(style.fg == "#eeeeee" and not style.bold and not style.bg, "nonselected tasks retain plain foreground")
        end
        if style.bold and span[1]:find("┌", 1, true) then
          focused_top = style.fg == color and not style.bg
        end
        if style.bold and span[1]:find("└", 1, true) then
          focused_bottom = style.fg == color and not style.bg
        end
      end
    end
  end
  check(
    selected_row and focused_top and focused_bottom,
    "rendered selection and focused top bottom borders use status color"
  )
end
check_board_selection(moving:render(), "#7799ff")
local move_lists, move_updates = fake.calls, #fake.updates
for _, move in ipairs({
  { ">", "doing", 2, "#ffaa00" },
  { ">", "done", 3, "#00cc66" },
  { "<", "doing", 2, "#ffaa00" },
  { "<", "todo", 1, "#7799ff" },
}) do
  moving:handle_key(move[1], fake)
  check(
    fake.result.tasks["task-3"].status == move[2]
      and moving._state.focused_column == move[3]
      and moving:selected_task().id == "task-3",
    "move changes status and follows ID into target column"
  )
  check_board_selection(moving:render(), move[4])
  if move[2] == "doing" then
    check(moving._state.selected[2] == 3, "target selection uses moved ID rather than source index")
  end
  local update = fake.updates[#fake.updates]["task-3"]
  local fields = 0
  for _ in pairs(update) do
    fields = fields + 1
  end
  check(fields == 1 and update.status == move[2], "move sends status-only patch")
end
check(fake.calls == move_lists + 4 and #fake.updates == move_updates + 4, "every successful move reloads board once")
local boundary_updates, boundary_lists = #fake.updates, fake.calls
moving:handle_key("<", fake)
moving:handle_key("h", fake)
moving:handle_key(">", fake)
moving:handle_key("<", fake)
check(#fake.updates == boundary_updates and fake.calls == boundary_lists, "boundary and empty-column moves are no-ops")
moving:handle_key("l", fake)
local navigation_updates = #fake.updates
for _, key in ipairs({ "l", "<Right>", "h", "<Left>" }) do
  moving:handle_key(key, fake)
end
check(
  moving._state.focused_column == 1 and #fake.updates == navigation_updates,
  "lowercase and arrows only navigate columns"
)
local before_id, before_index = moving:selected_task().id, moving._state.selected[1]
fake.update_error = "move write failed"
local failure_lists = fake.calls
moving:handle_key(">", fake)
check(
  moving._state.focused_column == 1
    and moving._state.selected[1] == before_index
    and moving:selected_task().id == before_id
    and moving:selected_task().status == "todo"
    and fake.calls == failure_lists,
  "move failure leaves focus selection cards unchanged without reload"
)
check_board_selection(moving:render(), "#7799ff")
check(
  text(moving:render()[10]):find("Error: move write failed", 1, true)
    and moving:render()[10][3][2].fg == "#ff4444"
    and moving:render()[10][3][2].bold,
  "board displays bold prefixed move error"
)
for _, size in ipairs({ { 20, 10 }, { 1, 1 }, { 80, 12 } }) do
  moving:resize(size[1], size[2])
  check(#moving:render() == size[2], "move error resize respects height")
  for _, line in ipairs(moving:render()) do
    check(width(text(line)) <= size[1], "move error resize respects width")
  end
end
fake.update_error = nil
fake.result.tasks[before_id].status = "done"
fake.result.tasks[before_id].title = "External title"
fake.result.tasks[before_id].description = "External description"
moving:handle_key(">", fake)
check(
  moving:selected_task().id == before_id
    and moving:selected_task().status == "doing"
    and moving:selected_task().title == "External title"
    and moving:selected_task().description == "External description",
  "stale board move preserves fresh external task body with status-only update"
)
check(not moving._state.error_message, "successful reload clears move error")

fake.result = board({ "task-1", "task-2" })
fake.result.tasks["task-2"].status = "doing"
observed = {}
run({
  { type = "key", key = ">" },
  function()
    observed.first = selected_title()
    observed.board = snapshot()
    check_board_selection(last_buf.lines, "#ffaa00")
  end,
  { type = "resize", width = 20, height = 10 },
  { type = "key", key = ">" },
  function()
    observed.narrow = snapshot()
    observed.selected = selected_title()
    check_board_selection(last_buf.lines, "#00cc66")
  end,
  { type = "key", key = "<" },
  { type = "resize", width = 80, height = 12 },
  function()
    observed.resized = snapshot()
    observed.final = selected_title()
    check_board_selection(last_buf.lines, "#ffaa00")
  end,
  { type = "key", key = "q" },
}, { cols = 30, rows = 15 })
check(
  observed.board:find("DOING · 2", 1, true) and observed.first:find("Title task-1", 1, true),
  "single-column board focuses target and selects moved ID"
)
check(observed.narrow:find("DONE · 1", 1, true), "consecutive > follows task through narrow board")
check(
  observed.resized:find("DOING · 2", 1, true) and observed.final and observed.final:find("Title task-1", 1, true),
  "< and resize retain moved selection"
)
