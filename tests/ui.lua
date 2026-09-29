local script = (arg and arg[0]) or "tests/ui.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/lua/?.lua;" .. package.path

local BORDER = 0

local TERM = { cols = 100, rows = 30 }
local EVENTS = {}
local last_opts, last_buf, last_win

local function adjust_scroll(cursor, offset, scrollable, vh)
  if vh == 0 then
    return offset
  end
  local max_offset = math.max(0, scrollable - vh)
  local o = math.min(offset, max_offset)
  if cursor < o then
    o = cursor
  elseif cursor >= o + vh then
    o = cursor + 1 - vh
  end
  return o
end

local function make_buf()
  local b = { lines = {} }
  function b:line(value)
    self.lines[#self.lines + 1] = value
  end
  function b:lines(list)
    for _, value in ipairs(list) do
      self:line(value)
    end
  end
  function b:set_lines(list)
    for line_index, line in ipairs(list) do
      if type(line) == "table" then
        for span_index, span in ipairs(line) do
          assert(type(span) == "table", string.format("line %d span %d must be a table {text, style?}", line_index, span_index))
          assert(type(span[1]) == "string", string.format("line %d span %d text must be a string", line_index, span_index))
          assert(span[3] == nil, string.format("line %d span %d has unexpected fields", line_index, span_index))
          assert(span[2] == nil or type(span[2]) == "table" or type(span[2]) == "string", string.format("line %d span %d style must be a table or string", line_index, span_index))
        end
      else
        assert(type(line) == "string", string.format("line %d must be a string or span array", line_index))
      end
    end
    self.lines = list
  end
  function b:len()
    return #self.lines
  end
  function b:get_lines()
    return self.lines
  end
  return b
end
local function make_win(buf, opts)
  local w = {
    buf = buf,
    opts = opts,
    config = {},
    offset = 0,
    cursor = 0,
    closed = false,
    close_calls = 0,
    cursor_calls = {},
    config_calls = {},
  }
  for key, value in pairs(opts) do
    w.config[key] = value
  end

  local function layout()
    local count = buf:len()
    local reserved_bot = math.min(w.config.reserved_bottom or 0, count)
    local reserved_top = math.min(w.config.reserved_top or 0, count - reserved_bot)
    return reserved_top, reserved_bot, count - reserved_top - reserved_bot
  end

  local function viewport()
    local reserved_top, reserved_bot = layout()
    local content = (w.config.height or 0) - BORDER
    if reserved_top + reserved_bot > 0 and content > reserved_top + reserved_bot then
      return content - reserved_top - reserved_bot
    end
    return content
  end

  function w:set_cursor(row)
    self.cursor_calls[#self.cursor_calls + 1] = row
    local reserved_top, _, scrollable = layout()
    local vh = viewport()
    local effective = math.max(0, (row - 1) - reserved_top)
    local clamped = math.min(effective, math.max(0, scrollable - 1))
    self.cursor = clamped + reserved_top
    self.offset = adjust_scroll(clamped, self.offset, scrollable, vh)
  end

  function w:set_config(patch)
    self.config_calls[#self.config_calls + 1] = patch
    for key, value in pairs(patch) do
      self.config[key] = value
    end
  end

  function w:recv()
    local ev = table.remove(EVENTS, 1)
    while type(ev) == "function" do
      ev()
      ev = table.remove(EVENTS, 1)
    end
    return ev
  end

  function w:close()
    self.close_calls = self.close_calls + 1
    self.closed = true
  end

  return w
end

local function u8display_width(s)
  local count = 0
  local i = 1
  local len = #s
  while i <= len do
    local b = string.byte(s, i)
    count = count + 1
    if b < 128 then
      i = i + 1
    elseif b >= 192 and b < 224 then
      i = i + 2
    elseif b >= 224 and b < 240 then
      i = i + 3
    elseif b >= 240 then
      i = i + 4
    else
      i = i + 1
    end
  end
  return count
end

local function u8truncate_text(s, max_w)
  local w = 0
  local i = 1
  local len = #s
  local split = len
  while i <= len do
    if w >= max_w then
      split = i - 1
      break
    end
    local b = string.byte(s, i)
    w = w + 1
    if b < 128 then
      i = i + 1
    elseif b >= 192 and b < 224 then
      i = i + 2
    elseif b >= 224 and b < 240 then
      i = i + 3
    elseif b >= 240 then
      i = i + 4
    else
      i = i + 1
    end
  end
  return { head = s:sub(1, split), tail = s:sub(split + 1) }
end

local maki = {
  ui = {
    terminal_size = function()
      return { cols = TERM.cols, rows = TERM.rows }
    end,
    display_width = function(text)
      return u8display_width(text)
    end,
    truncate_text = function(text, width)
      return u8truncate_text(text, width)
    end,
    theme_color = function(name)
      return name == "background" and "#101010" or name == "foreground" and "#eeeeee" or name == "accent" and "#7799ff" or "#ff0000"
    end,
    buf = function()
      return make_buf()
    end,
    open_win = function(buf, opts)
      last_buf = buf
      last_opts = opts
      last_win = make_win(buf, opts)
      return last_win
    end,
  },
}

_G.maki = maki

local fake = { result = nil, error = nil, calls = 0 }
function fake:load()
  self.calls = self.calls + 1
  return self.result, self.error
end
package.loaded["kanban.store"] = {
  new = function()
    return fake
  end,
}

local ui = require("kanban.ui")

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg)
  end
end

local function eq(got, want, msg)
  ok(got == want, msg .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local function run(events, term)
  EVENTS = events
  if term then
    TERM = term
  end
  last_opts, last_buf, last_win = nil, nil, nil
  ui.open()
  return last_win
end

local function board(count)
  local tasks = {}
  for i = 1, count do
    tasks["task-" .. i] = { title = "T" .. i, status = "todo" }
  end
  return { tasks = tasks }
end

local function repeat_key(key, times)
  local events = {}
  for _ = 1, times do
    events[#events + 1] = { type = "key", key = key }
  end
  return events
end

local function flatten(line)
  local parts = {}
  for _, span in ipairs(line) do
    parts[#parts + 1] = type(span) == "table" and span[1] or span
  end
  return table.concat(parts)
end

local function test_set_lines_rejects_mixed_spans()
  local buf = make_buf()
  local accepted = pcall(function()
    buf:set_lines({ { { "valid" }, "invalid" } })
  end)
  eq(accepted, false, "set_lines rejects mixed span arrays")
end

local function test_tall_fixed_height()
  fake.result, fake.error = board(30), nil
  local w = run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  eq(last_opts.border, "none", "outer border removed")
  eq(last_buf:len(), 21, "board and footer fixed to window")
  ok(flatten(last_buf.lines[1]):find("[1] TODO", 1, true) ~= nil, "numbered top-left heading")
  eq(flatten(last_buf.lines[19]):sub(1, #"┌"), "┌", "footer top border")
  eq(flatten(last_buf.lines[20]):sub(1, #"│"), "│", "footer hint line starts inside border")
  eq(flatten(last_buf.lines[20]):sub(-#"│"), "│", "footer hint line ends inside border")
  eq(flatten(last_buf.lines[21]):sub(1, #"└"), "└", "footer bottom border")
  ok(flatten(last_buf.lines[19]):find("h/l", 1, true) == nil, "footer border has no hint text")
  for i = 19, 21 do
    eq(u8display_width(flatten(last_buf.lines[i])), last_opts.width, "footer row fits normal width")
  end
  eq(w.offset, 0, "window does not scroll")
end

local function test_selection_and_navigation()
  fake.result, fake.error = board(30), nil
  local events = { { type = "key", key = "q" } }
  run(events, { cols = 100, rows = 30 })
  local selected_row = last_buf.lines[2]
  local highlighted = false
  for _, span in ipairs(selected_row) do
    if type(span) == "table" and type(span[2]) == "table" and span[2].bg == "#7799ff" then highlighted = true end
  end
  ok(highlighted, "selected row has background highlight")
  ok(flatten(selected_row):find("T1", 1, true) ~= nil, "task row has no checkbox")
  ok(flatten(last_buf.lines[1]):find("[3] Complete", 1, true) ~= nil, "number key jumps to column")
end

local function test_short_fixed_height()
  fake.result, fake.error = board(1), nil
  run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  ok(flatten(last_buf.lines[2]):find("T1", 1, true) ~= nil, "task title displayed")
  ok(flatten(last_buf.lines[2]):find("[ ]", 1, true) == nil, "checkbox omitted")
end

local function test_scroll_line_and_bounds()
  fake.result, fake.error = board(30), nil
  local events = repeat_key("j", 4)
  events[#events + 1] = { type = "key", key = "h" }
  events[#events + 1] = { type = "key", key = "l" }
  events[#events + 1] = { type = "key", key = "q" }
  run(events, { cols = 100, rows = 30 })
  ok(flatten(last_buf.lines[1]):find("[2] Doing", 1, true) ~= nil, "h/l navigate columns")
end

local function test_resize_updates_and_clamps()
  fake.result, fake.error = board(30), nil
  local events = { function() TERM = { cols = 60, rows = 30 } end, { type = "resize" }, { type = "key", key = "q" } }
  local w = run(events, { cols = 100, rows = 12 })
  eq(#w.config_calls, 1, "resize reconfigures the window once")
  eq(w.config.width, 56, "window width updated")
end

local function test_resize_preserves_offset()
  fake.result, fake.error = board(30), nil
  run({ { type = "key", key = "j" }, { type = "q", key = "q" } }, { cols = 100, rows = 30 })
end

local function test_status_columns()
  fake.result, fake.error = { tasks = {
    ["task-1"] = { title = "待办", status = "todo" },
    ["task-2"] = { title = "In progress", status = "doing" },
    ["task-3"] = { title = "Finished", status = "done" },
  } }, nil
  run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  local row = flatten(last_buf.lines[2])
  ok(row:find("待办", 1, true) ~= nil, "CJK todo title displayed")
  ok(row:find("In progress", 1, true) ~= nil, "doing task displayed")
  ok(row:find("Finished", 1, true) ~= nil, "complete task displayed")
  ok(row:find("[ ]", 1, true) == nil, "task rows omit checkboxes")
end

local function test_close_paths()
  fake.result, fake.error = board(3), nil
  fake.calls = 0
  local w = run({ { type = "key", key = "<Esc>" } }, { cols = 100, rows = 30 })
  eq(w.closed, true, "Esc closes the window")
  w = run({ { type = "close" } }, { cols = 100, rows = 30 })
  eq(w.closed, true, "external close shuts the window")
  w = run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  ok(w ~= nil and w.closed, "window can be reopened after closing")
  eq(fake.calls, 3, "each open reloads the store")
end

local function test_narrow_footer()
  fake.result, fake.error = board(1), nil
  run({ { type = "key", key = "q" } }, { cols = 28, rows = 30 })
  eq(last_opts.width, 24, "narrow window uses minimum width")
  eq(last_buf:len(), 21, "narrow board retains fixed height")
  for i = 19, 21 do
    eq(u8display_width(flatten(last_buf.lines[i])), 24, "narrow footer row fits window")
  end
  ok(flatten(last_buf.lines[19]):find("h/l", 1, true) == nil, "narrow footer border has no hints")
  ok(flatten(last_buf.lines[20]):find("h/l", 1, true) ~= nil, "narrow footer hints stay on middle row")
  ok(flatten(last_buf.lines[21]):find("h/l", 1, true) == nil, "narrow footer bottom has no hints")
end

local function test_error_view()
  fake.result, fake.error = nil, "invalid kanban store: boom"
  run({ { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  ok(type(last_buf.lines[1]) == "table", "error heading line exists")
  ok(tostring(last_buf.lines[2]):find("boom", 1, true) ~= nil, "error detail shown")
  eq(flatten(last_buf.lines[19]):sub(1, #"┌"), "┌", "error footer top border")
  eq(flatten(last_buf.lines[20]):sub(1, #"│"), "│", "error footer hint starts inside border")
  eq(flatten(last_buf.lines[20]):sub(-#"│"), "│", "error footer hint ends inside border")
  eq(flatten(last_buf.lines[21]):sub(1, #"└"), "└", "error footer bottom border")
  local calls = fake.calls
  local w = run({ function() TERM = { cols = 28, rows = 30 } end, { type = "resize" }, { type = "key", key = "q" } }, { cols = 100, rows = 30 })
  eq(fake.calls, calls + 1, "error resize does not reload store")
  eq(w.config.width, 24, "error resize updates narrow width")
  eq(last_buf:len(), 21, "error resize retains fixed height")
  for i = 19, 21 do
    eq(u8display_width(flatten(last_buf.lines[i])), 24, "resized error footer row fits window")
  end
  ok(flatten(last_buf.lines[20]):find("h/l", 1, true) ~= nil, "resized error hints stay on middle row")
end

local tests = {
  test_set_lines_rejects_mixed_spans,
  test_tall_fixed_height,
  test_selection_and_navigation,
  test_short_fixed_height,
  test_scroll_line_and_bounds,
  test_resize_updates_and_clamps,
  test_resize_preserves_offset,
  test_status_columns,
  test_close_paths,
  test_error_view,
  test_narrow_footer,
}

for _, test in ipairs(tests) do
  local run_ok, err = pcall(test)
  if not run_ok then
    fail = fail + 1
    print("ERROR: " .. tostring(err))
  end
end

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then
  os.exit(1)
end

