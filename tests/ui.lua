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
local editor = { files = {}, writes = {}, reads = {}, removes = {}, exit_code = 0 }
local function editor_write(path, value)
  editor.writes[#editor.writes + 1] = path
  editor.files[path] = value
  return true
end
local function editor_read(path)
  editor.reads[#editor.reads + 1] = path
  if editor.read_error then return nil, editor.read_error end
  return editor.files[path]
end
local function editor_rm(path)
  editor.removes[#editor.removes + 1] = path
  editor.files[path] = nil
  return true
end

_G.maki = { env = { state_dir = function() return "/tmp" end }, fs = {
  write = editor_write, read = editor_read, rm = editor_rm,
  joinpath = function(dir, file) return dir .. "/" .. file end,
  metadata = function(path) return editor.files[path] and { is_file = true } or nil end,
}, ui = {
  terminal_size = function() return { cols = TERM.cols, rows = TERM.rows } end,
  display_width = width,
  truncate_text = truncate,
  theme_color = function(name) return ({ background = "#101010", foreground = "#eeeeee", accent = "#7799ff", warning = "#ffaa00", success = "#00cc66", error = "#ff4444" })[name] end,
  theme_style = function(name) return name == "item_selected" and { bg = "#7799ff", fg = "#101010" } or {} end,
  buf = function() return make_buf() end,
  open_editor = function(path)
    editor.editor_path = path
    return editor.exit_code
  end,
  open_win = function(buf, opts)
    last_buf, last_opts, last_win = buf, opts, make_win(buf, opts)
    return last_win
  end,
} }

local text_input = {}
text_input.Result = { IGNORED = "ignored", CHANGED = "changed" }
function text_input.new()
  local self = { chars = {}, cursor = 1 }
  function self:value() return table.concat(self.chars) end
  function self:insert_text(value)
    value = tostring(value or "")
    for i = 1, #value do table.insert(self.chars, self.cursor, value:sub(i, i)); self.cursor = self.cursor + 1 end
    return text_input.Result.CHANGED
  end
  function self:handle_key(key)
    if key == "<Left>" then self.cursor = math.max(1, self.cursor - 1); return text_input.Result.CHANGED end
    if key == "<Right>" then self.cursor = math.min(#self.chars + 1, self.cursor + 1); return text_input.Result.CHANGED end
    if key == "<Home>" then self.cursor = 1; return text_input.Result.CHANGED end
    if key == "<End>" then self.cursor = #self.chars + 1; return text_input.Result.CHANGED end
    if key == "<BS>" or key == "<Backspace>" then
      if self.cursor > 1 then table.remove(self.chars, self.cursor - 1); self.cursor = self.cursor - 1; return text_input.Result.CHANGED end
      return text_input.Result.IGNORED
    end
    if key == "<Del>" or key == "<Delete>" then
      if self.cursor <= #self.chars then table.remove(self.chars, self.cursor); return text_input.Result.CHANGED end
      return text_input.Result.IGNORED
    end
    if type(key) == "string" and #key == 1 and key:byte() >= 32 then return self:insert_text(key) end
    return text_input.Result.IGNORED
  end
  return self
end
package.loaded["maki.text_input"] = text_input

local fake = { result = nil, error = nil, update_error = nil, calls = 0, updates = {} }
function fake:update(id, patch)
  self.updates[#self.updates + 1] = { id = id, patch = patch }
  if self.update_error then return nil, self.update_error end
  if patch.title ~= nil and patch.title == "" then return nil, "title must not be empty" end
  local source = self.result.tasks[id] or {}
  for key, value in pairs(patch) do source[key] = value end
  self.result.tasks[id] = source
  return { id = id, title = source.title, description = source.description, status = source.status }
end
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
local function snapshot()
  local lines = {}
  for _, line in ipairs(last_buf.lines) do lines[#lines + 1] = text(line) end
  return table.concat(lines, "\n")
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
fake.result = { tasks = {
  ["task-1"] = { title = "A long detail title that wraps across two lines", description = "first line\n\n" .. string.rep("long description words ", 300), status = "doing" },
} }
local observed = {}
run({
  { type = "key", key = "2" },
  { type = "key", key = "<CR>" },
  function() observed.detail = snapshot() end,
  { type = "key", key = "j" },
  function() observed.j = snapshot() end,
  { type = "key", key = "<Down>" },
  function() observed.down = snapshot() end,
  { type = "key", key = "<PageDown>" },
  function() observed.page_down = snapshot() end,
  { type = "key", key = "G" },
  function() observed.bottom = snapshot() end,
  { type = "key", key = "<PageUp>" },
  function() observed.page_up = snapshot() end,
  { type = "key", key = "k" },
  function() observed.k = snapshot() end,
  { type = "key", key = "<Up>" },
  function() observed.up = snapshot() end,
  { type = "key", key = "g" },
  function() observed.top = snapshot() end,
  { type = "key", key = "b" },
  function() observed.back = snapshot() end,
  { type = "key", key = "q" },
})
check(observed.detail:find("A long detail title", 1, true) and observed.detail:find("Doing", 1, true), "Enter opens detail with title and status")
check(observed.detail:find("first line", 1, true) and observed.detail:find("┌", 1, true) and observed.detail:find("└", 1, true) and observed.detail:find("b Back", 1, true), "detail displays description and bordered back footer")
check(observed.j ~= observed.detail and observed.down ~= observed.j and observed.page_down ~= observed.down and observed.bottom ~= observed.page_down, "j, Down, PageDown and G advance description viewport")
check(observed.page_up ~= observed.bottom and observed.k ~= observed.page_up and observed.up ~= observed.k and observed.top ~= observed.up, "g, PageUp, k and Up navigate description viewport")
check(observed.back:find("[1] TODO", 1, true) and observed.back:find("A long detail title", 1, true), "b restores board focus and selected task")

fake.result = { tasks = { ["task-1"] = { title = "待辦標題 that is far too long", description = "", status = "done" } } }
observed = {}
run({
  function() observed.board = snapshot() end,
  { type = "key", key = "3" },
  { type = "key", key = "<Enter>" },
  function() observed.detail = snapshot() end,
  function() TERM = { cols = 24, rows = 12 } end,
  { type = "resize", width = 20, height = 10 },
  function() observed.resize = snapshot() end,
  { type = "key", key = "b" },
  { type = "key", key = "q" },
})
check(observed.detail:find("Done", 1, true) and observed.resize:find("Done", 1, true) and not observed.resize:find("A long detail", 1, true), "status rendering and resize rewrap detail title")
check(#last_buf.lines == 10 and last_win.closed, "detail resize preserves view geometry and q closes")

fake.result = { tasks = {} }
run({ { type = "key", key = "<CR>" }, { type = "key", key = "q" } })
check(text(last_buf.lines[2]):find("TODO", 1, true) ~= nil, "Enter on empty selection remains on board")
run({ { type = "key", key = "<Esc>" } })
check(last_win.closed, "Esc closes from board view")

local Task = require("kanban.ui.task")
local Board = require("kanban.ui.board")
local function row(lines, i) return text(lines[i]) end
local detail = Task.new({ title = "Short", status = "todo", description = "one\ntwo" }, 16, 12)
local detail_lines = detail:render()
check(row(detail_lines, 2):find("Short", 1, true) ~= nil and row(detail_lines, 3) == "│" .. string.rep(" ", 14) .. "│", "single-line title reserves second row")
check(row(detail_lines, 4) == "├" .. string.rep("─", 14) .. "┤" and row(detail_lines, 5):find("Todo", 1, true) ~= nil, "separator and Todo label")
check(row(detail_lines, 6) == "│" .. string.rep(" ", 14) .. "│" and row(detail_lines, 7):find("one", 1, true) and row(detail_lines, 8):find("two", 1, true), "description follows blank spacer and preserves newlines")
check(width(row(detail_lines, 11)) == 16 and row(detail_lines, 12) == "└" .. string.rep("─", 14) .. "┘", "detail footer and bottom border")
check(detail_lines[5][2][2].fg == "#7799ff", "todo status uses accent color")

local cjk = Task.new({ title = "中文中文中文中文中文中文中文", status = "doing", description = "你好世界你好世界" }, 10, 11)
local cjk_lines = cjk:render()
check(row(cjk_lines, 2):find("中文中文", 1, true) and row(cjk_lines, 3):find("…", 1, true) and not row(cjk_lines, 4):find("中文", 1, true), "CJK title wraps into at most two truncated rows")
check(row(cjk_lines, 7):find("你好世界", 1, true) and row(cjk_lines, 8):find("你好世界", 1, true), "CJK description wraps at display width")
check(cjk_lines[5][2][2].fg == "#ffaa00", "doing status uses warning color")
for _, line in ipairs(cjk_lines) do check(width(text(line)) == 10, "CJK detail row fits exact width") end
local done = Task.new({ title = "Done task", status = "done", description = "" }, 12, 10)
check(row(done:render(), 5):find("Done", 1, true) and done:render()[5][2][2].fg == "#00cc66", "done status uses success color")
check(not row(done:render(), 7):find("empty", 1, true), "empty description has no placeholder")
local long = Task.new({ title = "Scrolling", status = "todo", description = table.concat({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }, "\n") }, 12, 10)
check(row(long:render(), 7):find("a", 1, true) ~= nil, "description begins at top")
check(long:handle_key("G") and row(long:render(), 7):find("j", 1, true) == nil and row(long:render(), 8):find("j", 1, true) ~= nil, "G reaches last description page")
long:resize(12, 13)
check(row(long:render(), 7):find("f", 1, true) ~= nil, "resize clamps description offset")
check(long:handle_key("b") == "back" and long:handle_key("q") == false and long:handle_key("<Esc>") == false, "detail only handles back, not global close keys")

fake.result = board({ "task-1", "task-2", "task-3", "task-4", "task-5", "task-6", "task-7", "task-8", "task-9", "task-10" })
local retained = Board.new(90, 8)
retained:reload(fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
retained:handle_key("j", fake)
local selected_before = retained:selected_task()
local before = row(retained:render(), 3)
retained:handle_key("2", fake)
retained:handle_key("1", fake)
check(retained:selected_task() == selected_before and row(retained:render(), 3) == before, "board preserves selection and scroll offset across focus change")

for _, key in ipairs({ "q", "<Esc>" }) do
  fake.result = { tasks = { ["task-1"] = { title = "Open detail", description = "text", status = "todo" } } }
  run({ { type = "key", key = "<CR>" }, { type = "key", key = key } })
  check(last_win.closed and snapshot():find("Open detail", 1, true) and snapshot():find("b Back", 1, true), key .. " closes from detail without going back")
end

local edit_task = { id = "task-1", title = "abc", description = "old", status = "todo" }
local edit = Task.new(edit_task, 30, 12)
check(edit.focused_field == "title" and edit:handle_key("<Tab>", fake) and edit.focused_field == "status" and edit:handle_key("<Tab>", fake) and edit.focused_field == "description" and edit:handle_key("<S-Tab>", fake) and edit.focused_field == "status", "focus tabs cycle in both directions")
edit.focused_field = "title"
fake.result = { tasks = { ["task-1"] = { title = "abc", description = "old", status = "todo" } } }
fake.update_error = nil
check(edit:handle_key("<CR>", fake) and edit.editing == "title", "Enter begins title editing")
check(edit:handle_key("<Left>", fake) and edit:handle_key("<BS>", fake) and edit:handle_paste("x\ny") and edit.title_draft == "ax yc", "title cursor editing and newline paste")
check(edit:handle_key("<Esc>", fake) and edit.task.title == "abc" and not edit.editing, "title cancel discards draft")
edit:handle_key("<CR>", fake); edit:handle_paste("new"); fake.update_error = "no title write"
check(edit:handle_key("<Enter>", fake) and edit.editing == "title" and edit.error == "no title write", "title update failure keeps editing and error")
fake.update_error = nil; edit:handle_key("<Esc>", fake)
edit:handle_key("<CR>", fake)
for _ = 1, 3 do edit:handle_key("<BS>", fake) end
check(edit:handle_key("<CR>", fake) and edit.editing == "title" and edit.title_input:value() == "" and edit.error == "title must not be empty" and edit.task.title == "abc", "empty title save fails without losing input")
edit:handle_key("<Esc>", fake)

edit.focused_field = "status"
edit:handle_key("<CR>", fake)
check(edit.status_draft == "todo" and edit:handle_key("l", fake) and edit.status_draft == "doing" and edit:handle_key("<Right>", fake) and edit.status_draft == "done", "status cycles left/right")
fake.update_error = "status failed"
check(edit:handle_key("<CR>", fake) and edit.error == "status failed" and edit.editing == "status", "status update failure keeps draft")
edit:handle_key("<Esc>", fake); fake.update_error = nil

local function reset_editor()
  editor.files, editor.writes, editor.reads, editor.removes = {}, {}, {}, {}
  editor.exit_code, editor.read_error, editor.editor_path = 0, nil, nil
end
reset_editor()
edit.focused_field = "description"
local description_open = maki.ui.open_editor
maki.ui.open_editor = function(path) editor.editor_path = path; editor.files[path] = "updated"; return 0 end
check(edit:handle_key("<CR>", fake) == "changed" and edit.task.description == "updated" and #fake.updates > 0, "description success reads and partially updates")
maki.ui.open_editor = description_open
reset_editor(); editor.exit_code = 1
check(edit:handle_key("<CR>", fake) and #editor.removes == 1 and edit.task.description == "updated", "description cancel/nonzero removes temporary file")
reset_editor(); editor.exit_code = 0; editor.read_error = "read failed"
check(edit:handle_key("<CR>", fake) and edit.error == "read failed" and #editor.removes == 1, "description read failure is rendered and cleaned up")
reset_editor(); editor.exit_code = 0; fake.update_error = "description failed"
local old_open_editor = maki.ui.open_editor
maki.ui.open_editor = function(path) editor.editor_path = path; editor.files[path] = "failed update"; return 0 end
check(edit:handle_key("<CR>", fake) and edit.error == "description failed" and #editor.removes == 1, "description update failure is retained and cleaned up")
maki.ui.open_editor, fake.update_error = old_open_editor, nil

fake.result = { tasks = { ["task-1"] = { title = "Before", description = "d", status = "todo" } } }
local calls_before = fake.calls
run({ { type = "key", key = "<CR>" }, { type = "key", key = "<CR>" }, { type = "key", key = "<End>" }, { type = "key", key = "X" }, { type = "key", key = "<CR>" }, { type = "key", key = "b" }, { type = "key", key = "q" } })
check(fake.result.tasks["task-1"].title == "BeforeX" and fake.calls == calls_before + 2 and snapshot():find("BeforeX", 1, true), "title save reloads board card")

fake.result = { tasks = { ["task-1"] = { title = "Moving", description = "d", status = "todo" } } }
run({ { type = "key", key = "<CR>" }, { type = "key", key = "<Tab>" }, { type = "key", key = "<CR>" }, { type = "key", key = "l" }, { type = "key", key = "<CR>" }, { type = "key", key = "b" }, { type = "key", key = "q" } })
check(fake.result.tasks["task-1"].status == "doing" and snapshot():find("DOING(1)", 1, true) and snapshot():find("TODO(0)", 1, true), "status save moves board card")

fake.result = { tasks = { ["task-1"] = { title = "Description", description = "original", status = "todo" } } }
local opened_path
maki.ui.open_editor = function(path)
  opened_path = path
  check(editor.files[path] == "original", "editor receives current description")
  editor.files[path] = "edited\nline"
  return 0
end
calls_before = fake.calls
run({ { type = "key", key = "<CR>" }, { type = "key", key = "<Tab>" }, { type = "key", key = "<Tab>" }, { type = "key", key = "<CR>" }, { type = "key", key = "b" }, { type = "key", key = "q" } })
check(opened_path and fake.result.tasks["task-1"].description == "edited\nline" and fake.calls == calls_before + 2 and not editor.files[opened_path], "description save refreshes board cache and removes temp file")
maki.ui.open_editor = description_open

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
