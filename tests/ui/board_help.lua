--# selene: allow(undefined_variable, unscoped_variables)
local regression_ids = {}
for i = 1, 30 do
  regression_ids[i] = "task-" .. i
end
fake.result = board(regression_ids)
local phase = Board.new(90, 12)
phase:reload(fake)
phase:handle_key("G", fake)
local help_task, help_offset, help_cards = phase:selected_task(), phase._state.offsets[1], phase._state.cards
local help_calls, help_updates, help_deletes, help_creates = fake.calls, #fake.updates, fake.deletes, fake.creates
phase:resize(90, 27)
help_offset = phase._state.offsets[1]
phase:handle_key("?", fake)
local help_lines = phase:render()
local help_text = {}
for _, line in ipairs(help_lines) do
  help_text[#help_text + 1] = text(line)
end
help_text = table.concat(help_text, "\n")
check(
  help_text:find("Keybindings", 1, true)
    and help_text:find("g / G", 1, true)
    and help_text:find("< / >", 1, true)
    and help_text:find("? / Esc", 1, true),
  "help displays phase-one navigation actions and dismissal keys"
)
local help_keys = {
  "n",
  "<CR>",
  "<Enter>",
  "q",
  "d",
  "r",
  "<",
  ">",
  "h",
  "l",
  "j",
  "k",
  "g",
  "G",
  "<Left>",
  "<Right>",
  "<Up>",
  "<Down>",
  "1",
  "2",
  "3",
  "H",
  "L",
}
for _, key in ipairs(help_keys) do
  check(
    phase:handle_key(key, fake)
      and phase._state.help_open
      and phase:render() == help_lines
      and phase:selected_task() == help_task
      and phase._state.offsets[1] == help_offset
      and phase._state.focused_column == 1
      and phase._state.cards == help_cards
      and fake.calls == help_calls
      and #fake.updates == help_updates
      and fake.deletes == help_deletes
      and fake.creates == help_creates,
    "help consumes key without side effects: " .. key
  )
end
phase:handle_key("?", fake)
check(
  not phase._state.help_open and phase:selected_task() == help_task and phase._state.offsets[1] == help_offset,
  "question mark toggles help off without navigation"
)
phase:handle_key("g", fake)
help_task = phase:selected_task()
phase:handle_key("?", fake)
for _, size in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 3 }, { 7, 7 }, { 8, 8 }, { 20, 10 }, { 35, 20 }, { 90, 27 } }) do
  phase:resize(size[1], size[2])
  check(
    phase._state.help_open and phase:selected_task() == help_task and #phase:render() == size[2],
    "help resize preserves state and exact height"
  )
  for _, line in ipairs(phase:render()) do
    check(width(text(line)) == size[1], "help overlay remains bounded with CJK beneath it")
  end
end
phase:handle_key("<Esc>", fake)
check(
  not phase._state.help_open and phase:selected_task() == help_task,
  "Esc dismisses help without clearing task selection"
)
observed = {}
fake.result = board(regression_ids)
local regression_calls, regression_updates = fake.calls, #fake.updates
run({
  { type = "key", key = "G" },
  function()
    observed.last = selected_title()
  end,
  { type = "key", key = "g" },
  function()
    observed.first = snapshot()
  end,
  { type = "key", key = "1" },
  { type = "key", key = "2" },
  { type = "key", key = "3" },
  { type = "key", key = "H" },
  { type = "key", key = "L" },
  function()
    observed.removed = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.last:find("task-30", 1, true)
    and observed.first:find("▸ Title task-1", 1, true)
    and observed.removed == observed.first
    and fake.calls == regression_calls + 1
    and #fake.updates == regression_updates,
  "event loop supports g/G and ignores removed shortcuts"
)
for _, key in ipairs(help_keys) do
  fake.result = board(regression_ids)
  fake.result.tasks["task-1"].title = "中文 first"
  local calls, updates, deletes, creates = fake.calls, #fake.updates, fake.deletes, fake.creates
  local reached = false
  observed = {}
  run({
    { type = "key", key = "G" },
    function()
      observed.before = snapshot()
    end,
    { type = "key", key = "?" },
    function()
      observed.help = snapshot()
    end,
    { type = "key", key = key },
    function()
      reached = true
      check(snapshot() == observed.help and not last_win.closed, "event loop help consumes " .. key)
    end,
    { type = "key", key = "<Esc>" },
    function()
      check(
        snapshot() == observed.before and not last_win.closed,
        "event loop Esc dismisses help preserving selection viewport and focus"
      )
    end,
    { type = "key", key = "?" },
    { type = "key", key = "?" },
    function()
      check(snapshot() == observed.before, "event loop question mark toggles help")
    end,
    { type = "key", key = "q" },
  })
  check(
    reached
      and last_win.closed
      and fake.calls == calls + 1
      and #fake.updates == updates
      and fake.deletes == deletes
      and fake.creates == creates,
    "event loop help has no Store or view side effects: " .. key
  )
end
fake.result = { tasks = { ["task-1"] = { title = "中文中文中文", status = "todo" } } }
local resize_help_events = { { type = "key", key = "?" } }
for _, size in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 4 }, { 8, 8 }, { 20, 10 }, { 90, 27 } }) do
  local cols, rows = size[1], size[2]
  resize_help_events[#resize_help_events + 1] = { type = "resize", width = cols, height = rows }
  resize_help_events[#resize_help_events + 1] = function()
    check(#last_buf.lines == rows, "event loop help resize keeps exact height")
    for _, line in ipairs(last_buf.lines) do
      check(width(text(line)) == cols, "event loop help resize fits exact width from 1x1 upwards")
    end
  end
end
resize_help_events[#resize_help_events + 1] = { type = "key", key = "<Esc>" }
resize_help_events[#resize_help_events + 1] = function()
  check(selected_title():find("中文", 1, true), "event loop help resize and Esc preserve CJK selection")
end
resize_help_events[#resize_help_events + 1] = { type = "key", key = "q" }
run(resize_help_events)

local tiny_footer = Board.new(20, 1)
fake.error = "disk failed"
tiny_footer:reload(fake)
check(
  row(tiny_footer:render(), 1):find("Error: disk", 1, true),
  "single-row footer displays clipped errors instead of only border"
)
fake.error = nil
fake.result = board({ "task-1" })
tiny_footer:reload(fake)
tiny_footer:handle_key("d", fake)
check(row(tiny_footer:render(), 1):find("Delete", 1, true), "single-row footer displays clipped deletion confirmation")
tiny_footer:handle_key("n", fake)
tiny_footer:resize(1, 10)
tiny_footer:handle_key("?", fake)
check(row(tiny_footer:render(), 5) == "?", "one-cell-wide help shows visible modal indicator")
tiny_footer:handle_key("<Esc>", fake)
check(not tiny_footer._state.help_open, "tiny help remains dismissible")
