local script = (arg and arg[0]) or "tests/ui.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/lua/?.lua;" .. package.path

local TERM = { cols = 100, rows = 30 }
local EVENTS, last_opts, last_buf, last_win = {}, nil, nil, nil
local function make_buf()
  local buf = { lines = {} }
  function buf:set_lines(lines)
    assert(type(lines) == "table", "lines must be a table")
    for line_index, line in ipairs(lines) do
      assert(type(line) == "string" or type(line) == "table", "invalid line " .. line_index)
      if type(line) == "table" then
        for span_index, span in ipairs(line) do
          assert(type(span) == "table" and type(span[1]) == "string" and (span[2] == nil or type(span[2]) == "table" or type(span[2]) == "string") and span[3] == nil, "invalid span at line " .. line_index .. ", span " .. span_index)
        end
      end
    end
    self.lines = lines
  end
  function buf:len() return #self.lines end
  return buf
end
local function make_win(buf, opts)
  local win = { buf = buf, opts = opts, config = opts, config_calls = {}, closed = false }
  function win:set_config(patch)
    self.config_calls[#self.config_calls + 1] = patch
    for key, value in pairs(patch) do self.config[key] = value end
  end
  function win:recv()
    local event = table.remove(EVENTS, 1)
    while type(event) == "function" do event(); event = table.remove(EVENTS, 1) end
    return event
  end
  function win:close() self.closed = true end
  return win
end
local function width(text)
  local n, i = 0, 1
  while i <= #text do
    local b = text:byte(i)
    local bytes = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
    if b < 128 then
      n = n + 1
    elseif b < 224 then
      n = n + 1
    elseif b == 226 and text:byte(i + 1) == 148 then
      n = n + 1
    else
      n = n + 2
    end
    i = i + bytes
  end
  return n
end
local function truncate(text, max)
  local out, used, i = "", 0, 1
  while i <= #text do
    local b = text:byte(i)
    local bytes = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
    local chars = b < 128 and 1 or b < 224 and 1 or (b == 226 and text:byte(i + 1) == 148) and 1 or 2
    if used + chars > max then break end
    out, used, i = out .. text:sub(i, i + bytes - 1), used + chars, i + bytes
  end
  return { head = out, tail = text:sub(i) }
end
_G.maki = { ui = {
  terminal_size = function() return { cols = TERM.cols, rows = TERM.rows } end,
  display_width = width,
  truncate_text = truncate,
  theme_color = function(name) return ({ background = "#101010", foreground = "#eeeeee", accent = "#7799ff", warning = "#ffaa00", success = "#00cc66" })[name] end,
  theme_style = function(name) return name == "item_selected" and { bg = "#7799ff", fg = "#101010" } or {} end,
  buf = function() return make_buf() end,
  open_win = function(buf, opts)
    last_buf, last_opts, last_win = buf, opts, make_win(buf, opts)
    return last_win
  end,
} }
local fake = { result = nil, error = nil, calls = 0 }
function fake:list()
  self.calls = self.calls + 1
  if self.error then return nil, self.error end
  local tasks = {}
  for id, task in pairs((self.result and self.result.tasks) or {}) do
    tasks[#tasks + 1] = { id = id, title = task.title, description = task.description, status = task.status }
  end
  table.sort(tasks, function(a, b)
    local x, y = tonumber(a.id:match("^task%-(%d+)$")), tonumber(b.id:match("^task%-(%d+)$"))
    if x and y then return x < y end
    return a.id < b.id
  end)
  return tasks
end
package.loaded["kanban.store"] = { new = function() return fake end }
local ui = require("kanban.ui")
local passed, failed = 0, 0
local function check(condition, message)
  if condition then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function text(line)
  local out = {}
  if type(line) == "string" then return line end
  for _, span in ipairs(line) do out[#out + 1] = span[1] end
  return table.concat(out)
end
local function run(events, term)
  EVENTS, TERM = events, term or { cols = 100, rows = 30 }
  last_opts, last_buf, last_win = nil, nil, nil
  ui.open()
  return last_win
end
local function board(ids)
  local tasks = {}
  for _, id in ipairs(ids) do tasks[id] = { title = "Title " .. id, description = "secret description", status = "todo" } end
  return { tasks = tasks }
end

fake.result = { tasks = {
  ["task-1"] = { title = "One", description = "hidden", status = "todo" },
  ["task-2"] = { title = "Two", description = "hidden", status = "todo" },
  ["task-10"] = { title = "Ten", description = "hidden", status = "todo" },
} }
run({ { type = "key", key = "q" } })
local all = {}
for _, line in ipairs(last_buf.lines) do all[#all + 1] = text(line) end
local joined = table.concat(all, "\n")
check(joined:find("[1] TODO(3)", 1, true) ~= nil and joined:find("[2] DOING(0)", 1, true) ~= nil and joined:find("[3] DONE(0)", 1, true) ~= nil, "all three counted headers")
check(last_opts.width == "90%" and last_opts.height == "90%", "window uses host-managed 90% dimensions")
check(#last_buf.lines == 27 and width(all[1]) == 90, "100x30 terminal renders 90x27 content")
check(all[1] == string.rep(" ", 90) and all[#all] == string.rep(" ", 90), "vertical padding is blank at top and bottom")
check(all[2]:sub(1, 2) == "  " and all[2]:sub(-2) == "  ", "horizontal padding is blank at left and right")
check(all[2]:find("┌", 1, true) and all[#all - 1]:find("└", 1, true), "rectangular panes have top and bottom borders")
check(not joined:find("h/l", 1, true) and not joined:find("q close", 1, true), "legacy footer removed")
check(not joined:find("task%-1") and not joined:find("hidden", 1, true), "IDs and descriptions hidden")
check(not joined:find("no tasks", 1, true), "empty columns have no placeholder")
local focused = false
for _, span in ipairs(last_buf.lines[2]) do
  if type(span) == "table" and type(span[2]) == "table" and span[2].bold then focused = true end
end
check(focused, "focused header style is distinct")
local selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if type(span) == "table" and type(span[2]) == "table" and span[2].bg == "#7799ff" then selected = true end
end
check(selected, "selected row has background highlight")
local order = table.concat(all, "\n")
check(order:find("One", 1, true) ~= nil and order:find("Two", 1, true) ~= nil and order:find("Ten", 1, true) ~= nil and order:find("One", 1, true) < order:find("Two", 1, true) and order:find("Two", 1, true) < order:find("Ten", 1, true), "numeric task ID order")

fake.result = board({ "task-1", "task-2", "task-3", "task-4", "task-5", "task-6", "task-7", "task-8", "task-9", "task-10", "task-11", "task-12", "task-13", "task-14", "task-15", "task-16", "task-17", "task-18", "task-19", "task-20", "task-21", "task-22", "task-23", "task-24", "task-25" })
run({ { type = "key", key = "l" }, { type = "key", key = "h" }, { type = "key", key = "3" }, { type = "key", key = "1" }, { type = "key", key = "j" }, { type = "key", key = "k" }, { type = "key", key = "q" } })
check(text(last_buf.lines[2]):find("[1] TODO", 1, true) ~= nil, "digit and h/l column navigation")
local first_selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if span[1]:find("Title task%-1") and span[2] and span[2].bg then first_selected = true end
end
check(first_selected, "j moves selection and k restores it")

fake.result = board({ "task-1", "task-2", "task-3", "task-4", "task-5", "task-6", "task-7", "task-8", "task-9", "task-10", "task-11", "task-12", "task-13", "task-14", "task-15", "task-16", "task-17", "task-18", "task-19", "task-20", "task-21", "task-22", "task-23", "task-24", "task-25" })
local initial_calls = fake.calls
local w = run({ { type = "key", key = "j" }, { type = "key", key = "j" }, { type = "key", key = "j" }, function() TERM = { cols = 60, rows = 35 }; fake.result = board({ "task-1" }) end, { type = "resize", width = 54, height = 31 }, { type = "key", key = "r" }, { type = "key", key = "q" } }, { cols = 100, rows = 10 })
check(#w.config_calls == 0 and w.config.width == "90%" and w.config.height == "90%" and #last_buf.lines == 31, "host percentage geometry follows resize")
check(fake.calls == initial_calls + 2, "r reloads store exactly once")
check(text(last_buf.lines[3]):find("Title task%-1") ~= nil and not text(last_buf.lines[3]):find("Title task%-2"), "refresh clamps selection to remaining task")

fake.result = { tasks = { ["task-1"] = { title = "待办", status = "todo" } } }
run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
check(text(last_buf.lines[3]):find("待办", 1, true) ~= nil, "CJK title is rendered")
for _, line in ipairs(last_buf.lines) do check(width(text(line)) <= 90, "CJK line fits configured width") end
run({ { type = "key", key = "q" } }, { cols = 12, rows = 8 })
check(last_opts.width == "90%" and last_opts.height == "90%" and #last_buf.lines == 7, "narrow terminal uses 90% window dimensions")
for _, line in ipairs(last_buf.lines) do check(width(text(line)) <= 10, "narrow line stays within width") end
run({ { type = "key", key = "q" } }, { cols = 3, rows = 4 })
check(last_opts.width == "90%" and last_opts.height == "90%", "small terminal keeps percentage dimensions")
for _, line in ipairs(last_buf.lines) do check(width(text(line)) <= 2, "tiny window stays within width") end
check(#last_buf.lines == 3 and text(last_buf.lines[1]) == "  ", "tiny window omits panes when padding leaves no room")
check(last_win.closed, "q closes window")
run({ { type = "key", key = "<Esc>" } })
check(last_win.closed, "Esc closes window")
run({ { type = "close" } })
check(last_win.closed, "external close handled")

fake.result = { tasks = {} }
run({ { type = "key", key = "2" }, { type = "key", key = "q" } }, { cols = 71, rows = 30 })
local below_text = {}
for _, line in ipairs(last_buf.lines) do below_text[#below_text + 1] = text(line) end
local below_joined = table.concat(below_text, "\n")
check(not below_joined:find("[1] TODO", 1, true) and below_joined:find("[2] DOING", 1, true) and not below_joined:find("[3] DONE", 1, true), "59 pane content cells render only the focused pane")

run({ { type = "key", key = "2" }, { type = "key", key = "q" } }, { cols = 72, rows = 30 })
local threshold_text = {}
for _, line in ipairs(last_buf.lines) do threshold_text[#threshold_text + 1] = text(line) end
local threshold_joined = table.concat(threshold_text, "\n")
check(threshold_joined:find("[1] TODO", 1, true) and threshold_joined:find("[2] DOING", 1, true) and threshold_joined:find("[3] DONE", 1, true), "60 pane content cells render all three panes")
check(text(last_buf.lines[2]):find("[2] DOING", 1, true) ~= nil, "digit 2 switches focus at the threshold")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
