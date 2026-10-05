--# selene: allow(undefined_variable, unscoped_variables)
fake.result = {
  tasks = {
    ["task-1"] = { title = "One", description = "hidden", status = "todo" },
    ["task-2"] = { title = "Two", description = "hidden", status = "todo" },
    ["task-10"] = { title = "Ten", description = "hidden", status = "todo" },
  },
}
run({ { type = "key", key = "q" } })
local all = {}
for _, line in ipairs(last_buf.lines) do
  all[#all + 1] = text(line)
end
local joined = table.concat(all, "\n")
check(
  joined:find("TODO · 3", 1, true) ~= nil
    and joined:find("DOING · 0", 1, true) ~= nil
    and joined:find("DONE · 0", 1, true) ~= nil
    and not joined:find("[1]", 1, true)
    and not joined:find("[2]", 1, true)
    and not joined:find("[3]", 1, true),
  "all three counted headers omit numeric shortcuts"
)
check(last_opts.width == "90%" and last_opts.height == "90%", "window uses host-managed 90% dimensions")
_ENV.input_snapshot = { text = "ask ", cursor = 4, version = 7, session_id = "session-1" }
_ENV.input_edit_result, _ENV.input_edit_error, notifications = true, nil, {}
run({ { type = "key", key = "j" }, { type = "key", key = "a" } })
check(
  last_win.closed
    and input_edit_closed
    and input_edit_opts.start == 4
    and input_edit_opts.stop == 4
    and input_edit_opts.text == "\n[task:task-2] Two"
    and input_edit_opts.cursor == 22
    and input_edit_opts.version == 7
    and input_edit_opts.session_id == "session-1",
  "a closes Kanban before inserting compact task reference at input cursor"
)
check(#notifications == 0, "successful task reference does not notify")
_ENV.input_edit_result, _ENV.input_edit_error, notifications = nil, "stale input", {}
run({ { type = "key", key = "a" } })
check(
  last_win.closed
    and #notifications == 1
    and notifications[1].level == "error"
    and notifications[1].message:find("stale input", 1, true),
  "input edit failure is reported after Kanban closes"
)
_ENV.input_edit_result, _ENV.input_edit_error, _ENV.input_snapshot = true, nil, nil
check(#last_buf.lines == 27 and width(all[1]) == 90, "100x30 terminal renders 90x27 content")
check(all[1] == string.rep(" ", 90) and all[#all] == string.rep(" ", 90), "vertical padding is blank at top and bottom")
check(all[2]:sub(1, 2) == "  " and all[2]:sub(-2) == "  ", "horizontal padding is blank at left and right")
check(
  all[2]:find("┌", 1, true) and all[#all - 5]:find("└", 1, true),
  "rectangular panes have top and bottom borders"
)
check(
  joined:find("NORMAL", 1, true) and joined:find("? help   q quit", 1, true),
  "normal footer includes help and quit hints"
)
check(not joined:find("task%-1") and not joined:find("hidden", 1, true), "IDs and descriptions hidden")
check(not joined:find("no tasks", 1, true), "empty columns have no placeholder")
local focused = false
for _, span in ipairs(last_buf.lines[2]) do
  if type(span) == "table" and type(span[2]) == "table" and span[2].bold then
    focused = true
  end
end
check(focused, "focused header style is distinct")
local selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if
    type(span) == "table"
    and type(span[2]) == "table"
    and span[2].fg == "#7799ff"
    and span[2].bold
    and not span[2].bg
    and span[1]:find("▸ ", 1, true)
  then
    selected = true
  end
end
check(selected, "selected row has accent bold marker without background")
local order = table.concat(all, "\n")
check(
  order:find("One", 1, true) ~= nil
    and order:find("Two", 1, true) ~= nil
    and order:find("Ten", 1, true) ~= nil
    and order:find("One", 1, true) < order:find("Two", 1, true)
    and order:find("Two", 1, true) < order:find("Ten", 1, true),
  "numeric task ID order"
)

fake.result = board({
  "task-1",
  "task-2",
  "task-3",
  "task-4",
  "task-5",
  "task-6",
  "task-7",
  "task-8",
  "task-9",
  "task-10",
  "task-11",
  "task-12",
  "task-13",
  "task-14",
  "task-15",
  "task-16",
  "task-17",
  "task-18",
  "task-19",
  "task-20",
  "task-21",
  "task-22",
  "task-23",
  "task-24",
  "task-25",
})
run({
  { type = "key", key = "l" },
  { type = "key", key = "l" },
  { type = "key", key = "l" },
  { type = "key", key = "j" },
  { type = "key", key = "k" },
  { type = "key", key = "q" },
})
check(text(last_buf.lines[2]):find("TODO", 1, true) ~= nil, "h/l column navigation")
local first_selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if span[1]:find("Title task%-1") and span[2] and span[2].bold and span[1]:find("▸ ", 1, true) then
    first_selected = true
  end
end
check(first_selected, "j moves selection and k restores it")

fake.result = board({
  "task-1",
  "task-2",
  "task-3",
  "task-4",
  "task-5",
  "task-6",
  "task-7",
  "task-8",
  "task-9",
  "task-10",
  "task-11",
  "task-12",
  "task-13",
  "task-14",
  "task-15",
  "task-16",
  "task-17",
  "task-18",
  "task-19",
  "task-20",
  "task-21",
  "task-22",
  "task-23",
  "task-24",
  "task-25",
})
local initial_calls = fake.calls
local w = run({
  { type = "key", key = "j" },
  { type = "key", key = "j" },
  { type = "key", key = "j" },
  function()
    _ENV.TERM = { cols = 60, rows = 35 }
    fake.result = board({ "task-1" })
  end,
  { type = "resize", width = 54, height = 31 },
  { type = "key", key = "r" },
  { type = "key", key = "q" },
}, { cols = 100, rows = 10 })
check(
  #w.config_calls == 0 and w.config.width == "90%" and w.config.height == "90%" and #last_buf.lines == 31,
  "host percentage geometry follows resize"
)
check(fake.calls == initial_calls + 2, "r reloads store exactly once")
check(
  text(last_buf.lines[3]):find("Title task%-1") ~= nil and not text(last_buf.lines[3]):find("Title task%-2"),
  "refresh clamps selection to remaining task"
)

fake.result = { tasks = { ["task-1"] = { title = "待办", status = "todo" } } }
run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
check(text(last_buf.lines[3]):find("待办", 1, true) ~= nil, "CJK title is rendered")
for _, line in ipairs(last_buf.lines) do
  check(width(text(line)) <= 90, "CJK line fits configured width")
end
run({ { type = "key", key = "q" } }, { cols = 12, rows = 8 })
check(
  last_opts.width == "90%" and last_opts.height == "90%" and #last_buf.lines == 7,
  "narrow terminal uses 90% window dimensions"
)
for _, line in ipairs(last_buf.lines) do
  check(width(text(line)) <= 10, "narrow line stays within width")
end
run({ { type = "key", key = "q" } }, { cols = 3, rows = 4 })
check(last_opts.width == "90%" and last_opts.height == "90%", "small terminal keeps percentage dimensions")
for _, line in ipairs(last_buf.lines) do
  check(width(text(line)) <= 2, "tiny window stays within width")
end
check(
  #last_buf.lines == 3 and text(last_buf.lines[1]) == "┌┐",
  "tiny window reserves the footer without column panes"
)
check(last_win.closed, "q closes window")
run({ { type = "key", key = "<Esc>" } })
check(last_win.closed, "Esc closes window")
run({ { type = "close" } })
check(last_win.closed, "external close handled")

fake.result = { tasks = {} }
run({ { type = "key", key = "l" }, { type = "key", key = "q" } }, { cols = 71, rows = 30 })
local below_text = {}
for _, line in ipairs(last_buf.lines) do
  below_text[#below_text + 1] = text(line)
end
local below_joined = table.concat(below_text, "\n")
check(
  not below_joined:find("TODO", 1, true)
    and below_joined:find("DOING", 1, true)
    and not below_joined:find("DONE", 1, true),
  "59 pane content cells render only the focused pane"
)

run({ { type = "key", key = "l" }, { type = "key", key = "q" } }, { cols = 72, rows = 30 })
local threshold_text = {}
for _, line in ipairs(last_buf.lines) do
  threshold_text[#threshold_text + 1] = text(line)
end
local threshold_joined = table.concat(threshold_text, "\n")
check(
  threshold_joined:find("TODO", 1, true)
    and threshold_joined:find("DOING", 1, true)
    and threshold_joined:find("DONE", 1, true),
  "60 pane content cells render all three panes"
)
check(text(last_buf.lines[2]):find("DOING", 1, true) ~= nil, "l switches focus at the threshold")
