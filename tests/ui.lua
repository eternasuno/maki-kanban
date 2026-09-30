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
    elseif b == 226 and (text:byte(i + 1) == 148 or text:sub(i, i + 2) == "▸") then
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
    local chars = b < 128 and 1 or b < 224 and 1 or (b == 226 and (text:byte(i + 1) == 148 or text:sub(i, i + 2) == "▸")) and 1 or 2
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
function fake:delete(id)
  self.deletes = (self.deletes or 0) + 1
  self.deleted_id = id
  if self.delete_error then return nil, self.delete_error end
  local task = self.result.tasks[id]
  if not task then return nil, "task not found: " .. id end
  self.result.tasks[id] = nil
  return { id = id, title = task.title, description = task.description, status = task.status }
end
function fake:create(input)
  self.creates = (self.creates or 0) + 1
  self.create_inputs = self.create_inputs or {}
  self.create_inputs[#self.create_inputs + 1] = { title = input.title, description = input.description }
  if self.create_error then return nil, self.create_error end
  if type(input.title) ~= "string" or input.title:match("^%s*$") then return nil, "title must not be empty" end
  local number = 1
  while self.result.tasks["task-" .. number] do number = number + 1 end
  local id = "task-" .. number
  self.result.tasks[id] = { title = input.title, description = input.description, status = "todo" }
  return { id = id, title = input.title, description = input.description, status = "todo" }
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
check(joined:find("TODO · 3", 1, true) ~= nil and joined:find("DOING · 0", 1, true) ~= nil and joined:find("DONE · 0", 1, true) ~= nil and not joined:find("[1]", 1, true) and not joined:find("[2]", 1, true) and not joined:find("[3]", 1, true), "all three counted headers omit numeric shortcuts")
check(last_opts.width == "90%" and last_opts.height == "90%", "window uses host-managed 90% dimensions")
check(#last_buf.lines == 27 and width(all[1]) == 90, "100x30 terminal renders 90x27 content")
check(all[1] == string.rep(" ", 90) and all[#all] == string.rep(" ", 90), "vertical padding is blank at top and bottom")
check(all[2]:sub(1, 2) == "  " and all[2]:sub(-2) == "  ", "horizontal padding is blank at left and right")
check(all[2]:find("┌", 1, true) and all[#all - 5]:find("└", 1, true), "rectangular panes have top and bottom borders")
check(joined:find("NORMAL", 1, true) and joined:find("? help   q quit", 1, true), "normal footer includes help and quit hints")
check(not joined:find("task%-1") and not joined:find("hidden", 1, true), "IDs and descriptions hidden")
check(not joined:find("no tasks", 1, true), "empty columns have no placeholder")
local focused = false
for _, span in ipairs(last_buf.lines[2]) do
  if type(span) == "table" and type(span[2]) == "table" and span[2].bold then focused = true end
end
check(focused, "focused header style is distinct")
local selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if type(span) == "table" and type(span[2]) == "table" and span[2].fg == "#7799ff" and span[2].bold and not span[2].bg and span[1]:find("▸ ", 1, true) then selected = true end
end
check(selected, "selected row has accent bold marker without background")
local order = table.concat(all, "\n")
check(order:find("One", 1, true) ~= nil and order:find("Two", 1, true) ~= nil and order:find("Ten", 1, true) ~= nil and order:find("One", 1, true) < order:find("Two", 1, true) and order:find("Two", 1, true) < order:find("Ten", 1, true), "numeric task ID order")

fake.result = board({ "task-1", "task-2", "task-3", "task-4", "task-5", "task-6", "task-7", "task-8", "task-9", "task-10", "task-11", "task-12", "task-13", "task-14", "task-15", "task-16", "task-17", "task-18", "task-19", "task-20", "task-21", "task-22", "task-23", "task-24", "task-25" })
run({ { type = "key", key = "l" }, { type = "key", key = "l" }, { type = "key", key = "l" }, { type = "key", key = "j" }, { type = "key", key = "k" }, { type = "key", key = "q" } })
check(text(last_buf.lines[2]):find("TODO", 1, true) ~= nil, "h/l column navigation")
local first_selected = false
for _, span in ipairs(last_buf.lines[3]) do
  if span[1]:find("Title task%-1") and span[2] and span[2].bold and span[1]:find("▸ ", 1, true) then first_selected = true end
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
check(#last_buf.lines == 3 and text(last_buf.lines[1]) == "┌┐", "tiny window reserves the footer without column panes")
check(last_win.closed, "q closes window")
run({ { type = "key", key = "<Esc>" } })
check(last_win.closed, "Esc closes window")
run({ { type = "close" } })
check(last_win.closed, "external close handled")

fake.result = { tasks = {} }
run({ { type = "key", key = "l" }, { type = "key", key = "q" } }, { cols = 71, rows = 30 })
local below_text = {}
for _, line in ipairs(last_buf.lines) do below_text[#below_text + 1] = text(line) end
local below_joined = table.concat(below_text, "\n")
check(not below_joined:find("TODO", 1, true) and below_joined:find("DOING", 1, true) and not below_joined:find("DONE", 1, true), "59 pane content cells render only the focused pane")

run({ { type = "key", key = "l" }, { type = "key", key = "q" } }, { cols = 72, rows = 30 })
local threshold_text = {}
for _, line in ipairs(last_buf.lines) do threshold_text[#threshold_text + 1] = text(line) end
local threshold_joined = table.concat(threshold_text, "\n")
check(threshold_joined:find("TODO", 1, true) and threshold_joined:find("DOING", 1, true) and threshold_joined:find("DONE", 1, true), "60 pane content cells render all three panes")
check(text(last_buf.lines[2]):find("DOING", 1, true) ~= nil, "l switches focus at the threshold")
fake.result = { tasks = {
  ["task-1"] = { title = "A long detail title that wraps across two lines", description = "first line\n\n" .. string.rep("long description words ", 300), status = "doing" },
} }
local observed = {}
run({
  { type = "key", key = "l" },
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
check(observed.back:find("TODO", 1, true) and observed.back:find("A long detail title", 1, true), "b restores board focus and selected task")

fake.result = { tasks = { ["task-1"] = { title = "待辦標題 that is far too long", description = "", status = "done" } } }
observed = {}
run({
  function() observed.board = snapshot() end,
  { type = "key", key = "h" },
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
retained:handle_key("l", fake)
retained:handle_key("h", fake)
check(retained:selected_task() == selected_before and row(retained:render(), 3) == before, "board preserves selection and scroll offset across focus change")

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
check(fake.result.tasks["task-1"].status == "doing" and snapshot():find("DOING · 1", 1, true) and snapshot():find("TODO · 0", 1, true), "status save moves board card")

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

local create_task = Task.new_create(30, 12)
check(create_task.creating and not create_task.editing and create_task.focused_field == "title", "creation starts in title field selection mode")
check(not create_task:handle_paste("ignored") and create_task.task.title == "", "paste is ignored until title editing begins")
check(create_task:handle_key("<Enter>", fake) and create_task.editing == "title", "Enter begins title editing in create mode")
create_task:handle_paste("新しい")
check(create_task:handle_key("<Enter>", fake) and create_task.task.title == "新しい" and not create_task.editing, "Enter stores CJK title draft locally")
create_task:handle_key("<Tab>", fake)
check(create_task.focused_field == "description", "creation tabs from title to description")
create_task:handle_key("<Tab>", fake)
check(create_task.focused_field == "create", "creation tabs to create action")

fake.result = { tasks = { ["task-1"] = { title = "Existing", description = "", status = "todo" }, ["task-3"] = { title = "Gap", description = "", status = "todo" } } }
fake.create_error = nil
local create_calls = fake.creates or 0
run({ { type = "key", key = "n" }, { type = "paste", text = "ignored" }, { type = "key", key = "<Enter>" }, { type = "paste", text = "新" }, { type = "key", key = "<Enter>" }, { type = "key", key = "<Tab>" }, { type = "key", key = "<Tab>" }, { type = "key", key = "<Enter>" }, { type = "key", key = "q" } })
check(fake.creates == create_calls + 1 and fake.result.tasks["task-2"].title == "新", "n creates title-only CJK task")
check(snapshot():find("新", 1, true) and snapshot():find("TODO · 3", 1, true), "creation reloads TODO board and selects created task ID")

fake.result = board({ "task-1", "task-2", "task-3" })
by_id:reload(fake)
by_id:select_task("task-2")
fake.result.tasks["task-2"].status = "doing"
by_id:reload(fake)
check(by_id._state.focused_column == 1 and by_id:selected_task().id == "task-3", "moved selection stays in original column with valid fallback")
fake.result.tasks["task-1"].status = "doing"
fake.result.tasks["task-3"].status = "doing"
by_id:reload(fake)
check(by_id._state.focused_column == 1 and by_id:selected_task() == nil and by_id._state.selected[1] == 1, "moving last tasks leaves valid empty original column")
by_id:select_task("task-2")
fake.result.tasks["task-0"] = { title = "Inserted", status = "doing" }
by_id:reload(fake)
check(by_id._state.focused_column == 2 and by_id:selected_task().id == "task-2", "reload preserves non-TODO column selection by ID")
by_id:handle_key("h", fake)
by_id:reload(fake)
by_id:handle_key("l", fake)
check(by_id:selected_task().id == "task-2", "reload preserves unfocused column selection by ID")
retained:reload(fake)
retained:select_task("task-3")
local offset_before = retained._state.offsets[2]
retained:reload(fake)
check(retained._state.offsets[2] == offset_before, "unchanged reload retains legal scroll offset")

local function selected_title()
  for _, line in ipairs(last_buf.lines) do
    if type(line) == "table" then
      for _, span in ipairs(line) do
        if type(span[2]) == "table" and span[2].bold and span[1]:find("▸ ", 1, true) then return span[1] end
      end
    end
  end
end
check(selected_title():find("新", 1, true) ~= nil, "title-only creation selects new ID rather than last index")

reset_editor()
fake.result = { tasks = { ["task-1"] = { title = "Existing", description = "", status = "todo" } } }
local updates_before, lists_before = #fake.updates, fake.calls
local description_creates = fake.creates
maki.ui.open_editor = function(path)
  check(editor.files[path] == "", "create description editor starts with empty draft")
  editor.files[path] = "first\n第二行"
  return 0
end
observed = {}
run({
  { type = "key", key = "l" }, { type = "key", key = "n" },
  function() observed.open = snapshot() end,
  { type = "paste", text = "ignored" }, { type = "key", key = "<Enter>" },
  { type = "paste", text = "With description" }, { type = "key", key = "<Enter>" },
  { type = "key", key = "<Tab>" }, { type = "key", key = "<Enter>" },
  function() check(fake.creates == description_creates and #fake.updates == updates_before, "description draft does not write Store before Create") end,
  { type = "key", key = "<Tab>" }, { type = "key", key = "<Enter>" },
  function() observed.selected = selected_title() end,
  { type = "key", key = "<CR>" },
  function() observed.detail = snapshot() end,
  { type = "key", key = "q" },
})
check(observed.open:find("Create task (Todo)", 1, true) and observed.open:find("Esc Cancel", 1, true), "n opens create flow")
check(fake.result.tasks["task-2"].description == "first\n第二行" and fake.result.tasks["task-2"].status == "todo", "description creation stores draft and fixed TODO status")
check(fake.calls == lists_before + 2 and observed.selected:find("With description", 1, true) and observed.detail:find("With description", 1, true), "creation reloads once, focuses TODO and opens selected new task")
check(#editor.removes == 1 and next(editor.files) == nil, "create description removes temporary file")
maki.ui.open_editor = description_open

for _, title in ipairs({ "", "   " }) do
  local invalid = Task.new_create(80, 12)
  invalid:handle_key("<CR>", fake)
  invalid:handle_paste(title)
  invalid:handle_key("<CR>", fake)
  invalid:handle_key("<Tab>", fake)
  invalid:handle_key("<Tab>", fake)
  local attempts = fake.creates
  check(invalid:handle_key("<CR>", fake) == true and fake.creates == attempts + 1 and invalid.error == "title must not be empty", "Store rejects empty/whitespace create title")
  check(invalid.task.title == title and row(invalid:render(), 10):find("title must not be empty", 1, true), "invalid create retains input and renders Store error")
end

reset_editor()
local failed_create = Task.new_create(80, 12)
failed_create:handle_key("<CR>", fake)
failed_create:handle_paste("Retained title")
failed_create:handle_key("<CR>", fake)
failed_create:handle_key("<Tab>", fake)
maki.ui.open_editor = function(path) editor.files[path] = "Retained description"; return 0 end
failed_create:handle_key("<CR>", fake)
failed_create:handle_key("<Tab>", fake)
fake.create_error = "write failed"
check(failed_create:handle_key("<CR>", fake) == true and failed_create.creating and failed_create.task.title == "Retained title" and failed_create.task.description == "Retained description", "Store create failure keeps create UI and both drafts")
check(row(failed_create:render(), 10):find("write failed", 1, true), "create failure displays error")
fake.create_error = nil
check(failed_create:handle_key("<CR>", fake) == "created" and failed_create.task.status == "todo", "failed creation can retry successfully")
maki.ui.open_editor = description_open

local cancel_creates = fake.creates
observed = {}
run({ { type = "key", key = "n" }, { type = "key", key = "<Esc>" },
  function() observed.cancel_flow = snapshot() end, { type = "key", key = "q" },
})
check(fake.creates == cancel_creates and observed.cancel_flow:find("TODO", 1, true) and not observed.cancel_flow:find("Create task (Todo)", 1, true), "Esc exits field selection to board without creating")

run({ { type = "key", key = "n" }, { type = "key", key = "<Enter>" }, { type = "paste", text = "Cancel me" },
  { type = "key", key = "<Esc>" }, function() observed.cancel_edit = snapshot() end,
  { type = "key", key = "<Esc>" }, function() observed.cancel_flow = snapshot() end,
  { type = "key", key = "q" },
})
check(fake.creates == cancel_creates and observed.cancel_edit:find("Create task (Todo)", 1, true) and not observed.cancel_edit:find("Cancel me", 1, true), "Esc cancels title draft without creating or leaving create view")
check(observed.cancel_flow:find("TODO", 1, true) and not observed.cancel_flow:find("Create task (Todo)", 1, true), "second Esc exits creation to board")

local resized_create = Task.new_create(80, 12)
resized_create:handle_key("<CR>", fake)
resized_create:handle_paste("中文创建标题中文创建标题")
for _, size in ipairs({ { 20, 10 }, { 3, 4 }, { 1, 1 }, { 0, 0 }, { 80, 12 } }) do
  resized_create:resize(size[1], size[2])
  check(#resized_create:render() == size[2], "create resize respects height")
  for _, line in ipairs(resized_create:render()) do check(width(text(line)) <= size[1], "create resize stays within display width") end
end
check(resized_create.title_input:value() == "中文创建标题中文创建标题", "create resize preserves CJK title input")
run({ { type = "key", key = "n" }, { type = "paste", text = "ignored" },
  { type = "resize", width = 1, height = 1 },
  function() check(#last_buf.lines == 1 and width(text(last_buf.lines[1])) <= 1, "event-loop resize renders bounded create view") end,
  { type = "key", key = "<Esc>" }, { type = "key", key = "<Esc>" }, { type = "key", key = "q" },
})

fake.create_error = "disk write failed"
observed = {}
run({ { type = "key", key = "n" }, { type = "paste", text = "ignored" },
  { type = "key", key = "<Enter>" }, { type = "paste", text = "Keep this title" }, { type = "key", key = "<CR>" }, { type = "key", key = "<Tab>" },
  { type = "key", key = "<Tab>" }, { type = "key", key = "<CR>" },
  function() observed.failure = snapshot() end,
  { type = "key", key = "<Esc>" }, function() observed.board = snapshot() end,
  { type = "key", key = "q" },
})
check(observed.failure:find("Keep this title", 1, true) and observed.failure:find("disk write failed", 1, true) and observed.failure:find("Create task (Todo)", 1, true), "event loop keeps create view and input after Store failure")
check(observed.board:find("TODO", 1, true) ~= nil, "failed create can be cancelled back to board")
fake.create_error = nil
reset_editor()
editor.exit_code = 1
local cancelled_description = Task.new_create(80, 12)
cancelled_description:handle_key("<CR>", fake)
cancelled_description:handle_paste("Draft")
cancelled_description:handle_key("<CR>", fake)
cancelled_description:handle_key("<Tab>", fake)
cancelled_description:handle_key("<CR>", fake)
check(cancelled_description.task.description == "" and #editor.removes == 1, "cancelled create description editor preserves draft and cleans file")
reset_editor()

fake.result = board({ "task-1", "task-2", "task-3" })
local deleting = Task.new({ id = "task-2", title = "Delete me", description = "", status = "todo" }, 80, 12)
local deletes_before = fake.deletes or 0
for _, key in ipairs({ "<Esc>", "n", "b", "q", "<Enter>" }) do
  check(deleting:handle_key("d", fake) == true and deleting.confirm_delete, "d enters delete confirmation")
  check(row(deleting:render(), 11):find("Delete this task? y/N", 1, true), "confirmation prompt rendered")
  deleting:handle_key(key, fake)
  check(not deleting.confirm_delete and (fake.deletes or 0) == deletes_before and fake.result.tasks["task-2"], "non-y cancels deletion without executing key")
end
for _, err in ipairs({ "malformed JSON", "task not found: task-2", "write failed" }) do
  fake.delete_error = err
  deleting:handle_key("d", fake)
  check(deleting:handle_key("y", fake) == true and deleting.error == err and not deleting.confirm_delete, "delete failure stays in detail with retryable error")
  check(row(deleting:render(), 10):find(err, 1, true), "delete failure rendered")
end
fake.delete_error = nil
deleting:handle_key("d", fake)
check(deleting:handle_key("y", fake) == "deleted" and fake.deleted_id == "task-2" and not fake.result.tasks["task-2"], "confirmed delete calls Store and returns deleted action")
local no_delete_create = Task.new_create(80, 12)
check(no_delete_create:handle_key("d", fake) == false and not no_delete_create.confirm_delete, "creation has no delete action")

fake.result = board({ "task-1", "task-2", "task-3" })
local delete_lists = fake.calls
observed = {}
run({ { type = "key", key = "j" }, { type = "key", key = "<Enter>" },
  { type = "key", key = "d" }, { type = "key", key = "<Esc>" },
  function() observed.cancel = snapshot() end,
  { type = "key", key = "d" }, { type = "key", key = "n" },
  { type = "key", key = "d" }, { type = "key", key = "y" },
  function() observed.deleted = snapshot(); observed.selected = selected_title() end,
  { type = "key", key = "q" },
})
check(observed.cancel:find("Title task-2", 1, true) and not observed.cancel:find("Delete this task?", 1, true), "Esc confirmation cancellation does not close detail window")
check(fake.calls == delete_lists + 2 and observed.deleted:find("TODO · 2", 1, true) and not observed.deleted:find("Title task-2", 1, true), "deleted action reloads and returns to board")
check(observed.selected:find("Title task-3", 1, true), "deleted middle task falls back to next task at same index")

fake.result = board({ "task-1" })
run({ { type = "key", key = "<Enter>" }, { type = "key", key = "d" }, { type = "key", key = "y" }, { type = "key", key = "<Enter>" }, { type = "key", key = "q" } })
check(snapshot():find("TODO · 0", 1, true) and selected_title() == nil, "deleting last task leaves legal empty board selection")
fake.result = board({ "task-1" })
fake.delete_error = "disk write failed"
observed = {}
run({ { type = "key", key = "<Enter>" }, { type = "key", key = "d" }, { type = "key", key = "y" },
  function() observed.failure = snapshot() end, { type = "key", key = "b" },
  function() observed.back = snapshot() end, { type = "key", key = "q" },
})
check(observed.failure:find("disk write failed", 1, true) and observed.failure:find("Enter Edit", 1, true) and observed.back:find("TODO · 1", 1, true), "event loop keeps failed delete detail and permits returning to board")
fake.delete_error = nil

fake.result = board({ "task-1", "task-2", "task-3" })
fake.result.tasks["task-1"].status = "doing"
fake.result.tasks["task-2"].status = "doing"
local moving = Board.new(80, 12)
moving:reload(fake)
moving:select_task("task-3")
local move_lists, move_updates = fake.calls, #fake.updates
for _, move in ipairs({ { ">", "doing", 2 }, { ">", "done", 3 }, { "<", "doing", 2 }, { "<", "todo", 1 } }) do
  moving:handle_key(move[1], fake)
  check(fake.result.tasks["task-3"].status == move[2] and moving._state.focused_column == move[3] and moving:selected_task().id == "task-3", "move changes status and follows ID into target column")
  if move[2] == "doing" then check(moving._state.selected[2] == 3, "target selection uses moved ID rather than source index") end
  local update = fake.updates[#fake.updates]
  local fields = 0
  for _ in pairs(update.patch) do fields = fields + 1 end
  check(update.id == "task-3" and fields == 1 and update.patch.status == move[2], "move sends status-only patch")
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
for _, key in ipairs({ "l", "<Right>", "h", "<Left>" }) do moving:handle_key(key, fake) end
check(moving._state.focused_column == 1 and #fake.updates == navigation_updates, "lowercase and arrows only navigate columns")
local before_id, before_index = moving:selected_task().id, moving._state.selected[1]
fake.update_error = "move write failed"
local failure_lists = fake.calls
moving:handle_key(">", fake)
check(moving._state.focused_column == 1 and moving._state.selected[1] == before_index and moving:selected_task().id == before_id and moving:selected_task().status == "todo" and fake.calls == failure_lists, "move failure leaves focus selection cards unchanged without reload")
check(text(moving:render()[10]):find("Error: move write failed", 1, true) and moving:render()[10][3][2].fg == "#ff4444" and moving:render()[10][3][2].bold, "board displays bold prefixed move error")
for _, size in ipairs({ { 20, 10 }, { 1, 1 }, { 80, 12 } }) do
  moving:resize(size[1], size[2])
  check(#moving:render() == size[2], "move error resize respects height")
  for _, line in ipairs(moving:render()) do check(width(text(line)) <= size[1], "move error resize respects width") end
end
fake.update_error = nil
fake.result.tasks[before_id].status = "done"
fake.result.tasks[before_id].title = "External title"
fake.result.tasks[before_id].description = "External description"
moving:handle_key(">", fake)
check(moving:selected_task().id == before_id and moving:selected_task().status == "doing" and moving:selected_task().title == "External title" and moving:selected_task().description == "External description", "stale board move preserves fresh external task body with status-only update")
check(not moving._state.error_message, "successful reload clears move error")

fake.result = board({ "task-1", "task-2" })
fake.result.tasks["task-2"].status = "doing"
observed = {}
run({ { type = "key", key = ">" },
  function() observed.first = selected_title(); observed.board = snapshot() end,
  { type = "resize", width = 20, height = 10 }, { type = "key", key = ">" },
  function() observed.narrow = snapshot(); observed.selected = selected_title() end,
  { type = "key", key = "<" }, { type = "resize", width = 80, height = 12 },
  function() observed.resized = snapshot(); observed.final = selected_title() end,
  { type = "key", key = "q" },
}, { cols = 30, rows = 15 })
check(observed.board:find("DOING · 2", 1, true) and observed.first:find("Title task-1", 1, true), "single-column board focuses target and selects moved ID")
check(observed.narrow:find("DONE · 1", 1, true) and observed.selected:find("Title task-1", 1, true), "consecutive > follows task through narrow board")
check(observed.resized:find("DOING · 2", 1, true) and observed.final:find("Title task-1", 1, true), "< and resize retain moved selection")

fake.result = board({ "task-1", "task-2", "task-3" })
local board_delete = Board.new(80, 12)
board_delete:reload(fake)
board_delete:select_task("task-2")
local board_deletes, board_lists = fake.deletes, fake.calls
board_delete:handle_key("d", fake)
check(board_delete._state.pending_delete_id == "task-2" and fake.deletes == board_deletes and fake.calls == board_lists, "board d records selected ID without deleting or reloading")
check(row(board_delete:render(), 10):find('Delete "Title task-2"?  y/N', 1, true), "board renders titled delete confirmation")
for _, size in ipairs({ { 20, 10 }, { 1, 1 }, { 80, 12 } }) do
  board_delete:resize(size[1], size[2])
  check(board_delete._state.pending_delete_id == "task-2" and #board_delete:render() == size[2], "board resize retains pending delete ID and height")
  local footer_row = size[2] >= 8 and size[2] - 2 or size[2] >= 3 and size[2] - 1 or 1
  local prompt = size[1] >= 2 and size[2] >= 3 and '│ ' .. truncate('Delete "Title task-2"?  y/N', math.max(0, size[1] - 8)).head or "D"
  check(row(board_delete:render(), footer_row):find(prompt, 1, true), "board resize retains fitted titled confirmation prompt")
  for _, line in ipairs(board_delete:render()) do check(width(text(line)) <= size[1], "board confirmation resize fits width") end
end
board_delete:handle_key("y", fake)
check(fake.deleted_id == "task-2" and fake.deletes == board_deletes + 1 and fake.calls == board_lists + 1 and not board_delete._state.pending_delete_id, "board y deletes recorded ID and reloads once")
check(board_delete:selected_task().id == "task-3" and board_delete._state.focused_column == 1 and board_delete._state.selected[1] == 2, "board middle deletion retains same index and focus")
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(board_delete:selected_task().id == "task-1" and board_delete._state.selected[1] == 1, "board final-index deletion clamps to preceding task")
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(not board_delete:selected_task() and board_delete._state.selected[1] == 1 and board_delete._state.offsets[1] == 0, "board last deletion leaves legal empty selection")
board_deletes, board_lists = fake.deletes, fake.calls
board_delete:handle_key("d", fake)
check(not board_delete._state.pending_delete_id and fake.deletes == board_deletes and fake.calls == board_lists, "empty board d is a no-op")
fake.error = "malformed JSON"
board_delete:reload(fake)
board_delete:handle_key("d", fake)
check(not board_delete._state.pending_delete_id and not board_delete._state.valid and fake.deletes == board_deletes, "invalid board d is a no-op")
fake.error = nil
fake.result = board({ "task-1", "task-2", "task-3" })
fake.result.tasks["task-2"].status = "doing"
board_delete:reload(fake)
board_delete:select_task("task-2")
for _, key in ipairs({ "n", "<Esc>", "q", "<CR>", "<Enter>", "j", "k", "l", "h", "2", "<", ">", "r", "d", "Y" }) do
  local cards, selected, offsets = board_delete._state.cards, board_delete._state.selected[2], board_delete._state.offsets[2]
  board_delete:handle_key("d", fake)
  check(board_delete:handle_key(key, fake) and not board_delete._state.pending_delete_id and board_delete._state.cards == cards and board_delete._state.focused_column == 2 and board_delete._state.selected[2] == selected and board_delete._state.offsets[2] == offsets and fake.deletes == board_deletes, "board confirmation consumes cancellation key " .. key)
end
board_delete:handle_key("d", fake)
board_delete:reload(fake)
check(not board_delete._state.pending_delete_id and not row(board_delete:render(), 10):find('Delete "', 1, true), "board reload clears pending confirmation")
board_delete:handle_key("h", fake)
board_delete:handle_key("j", fake)
board_lists = fake.calls
local failure_cards, failure_task = board_delete._state.cards, board_delete:selected_task()
fake.delete_error = "delete write failed"
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(board_delete._state.cards == failure_cards and board_delete:selected_task() == failure_task and board_delete._state.focused_column == 1 and board_delete._state.selected[1] == 2 and fake.calls == board_lists and not board_delete._state.pending_delete_id, "board delete failure retains cards focus selection without reload")
check(board_delete._state.error_message == "delete write failed" and row(board_delete:render(), 10):find("Error: delete write failed", 1, true) and board_delete:render()[10][3][2].fg == "#ff4444" and board_delete:render()[10][3][2].bold, "board delete failure renders bold prefixed error")
fake.delete_error = nil
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(not fake.result.tasks[failure_task.id] and not board_delete._state.error_message, "board failed deletion can retry successfully")

for _, key in ipairs({ "n", "<Esc>", "q", "<CR>", "<Enter>", "j", "l", ">", "r" }) do
  fake.result = board({ "task-1", "task-2", "task-3" })
  board_deletes, board_lists = fake.deletes, fake.calls
  local reached = false
  run({ { type = "key", key = "j" }, { type = "key", key = "d" },
    function() check(snapshot():find('Delete "Title task-2"?  y/N', 1, true) and not snapshot():find("Enter Edit", 1, true) and fake.deletes == board_deletes, "event loop d confirms on board without immediate deletion") end,
    { type = "key", key = key },
    function()
      reached = true
      check(snapshot():find("TODO · 3", 1, true) and not snapshot():find('Delete "', 1, true) and selected_title():find("Title task-2", 1, true), "event loop consumes board cancellation " .. key)
    end,
    { type = "key", key = "q" },
  })
  check(reached and fake.deletes == board_deletes and fake.calls == board_lists + 1, "board cancellation does not close create open move or reload: " .. key)
end
fake.result = board({ "task-1", "task-2", "task-3" })
board_lists = fake.calls
run({ { type = "key", key = "j" }, { type = "key", key = "d" },
  { type = "resize", width = 20, height = 10 },
  function() check(row(last_buf.lines, 8):find('│ Delete "Titl', 1, true) and snapshot():find("TODO · 3", 1, true), "event loop narrow resize retains board confirmation") end,
  { type = "key", key = "y" },
  function() check(snapshot():find("TODO · 2", 1, true) and selected_title():find("Title task-3", 1, true), "event loop board y reloads and falls back at same index") end,
  { type = "key", key = "q" },
})
check(fake.deleted_id == "task-2" and fake.calls == board_lists + 2, "event loop resize retains recorded deletion ID and reloads once")
fake.result = board({ "task-1" })
fake.delete_error = "board disk write failed"
board_lists = fake.calls
run({ { type = "key", key = "d" }, { type = "key", key = "y" },
  function() check(snapshot():find("TODO · 1", 1, true) and snapshot():find("board disk write failed", 1, true) and selected_title():find("Title task-1", 1, true), "event loop delete failure stays board with selection and error"); fake.delete_error = nil end,
  { type = "key", key = "d" }, { type = "key", key = "y" },
  function() check(snapshot():find("TODO · 0", 1, true) and not selected_title(), "event loop board retry deletes last card") end,
  { type = "key", key = "q" },
})
check(fake.calls == board_lists + 2, "event loop failed board delete does not reload before successful retry")

local regression_ids = {}
for i = 1, 30 do regression_ids[i] = "task-" .. i end
fake.result = board(regression_ids)
fake.result.tasks["task-1"].title = "中文 first"
fake.result.tasks["task-2"].title = "中文 second"
local phase = Board.new(90, 12)
phase:reload(fake)
check(width("▸") == 1 and width("▸ 中文") == 6 and truncate("▸ 中文", 4).head == "▸ 中", "mock treats marker as one cell while preserving CJK widths")
local phase_lines = phase:render()
check(phase_lines[3][3][1]:sub(1, #"▸ 中文") == "▸ 中文" and phase_lines[4][3][1]:sub(1, #"  中文") == "  中文", "selected and unselected titles share a two-cell marker prefix")
check(phase_lines[3][3][2].fg == "#7799ff" and phase_lines[3][3][2].bold and not phase_lines[3][3][2].bg and phase_lines[4][3][2].fg == "#eeeeee" and not phase_lines[4][3][2].bold and not phase_lines[4][3][2].bg, "marker title styling is accent bold without background only on selection")
for _, line_number in ipairs({ 2, 3, 7 }) do
  local spans = phase_lines[line_number]
  check(spans[2][2].fg == "#7799ff" and spans[2][2].bold, "focused top side and bottom borders use accent bold")
end
check(phase_lines[2][4][2].fg == "#eeeeee" and not phase_lines[2][4][2].bold and phase_lines[3][6][2].fg == "#eeeeee" and not phase_lines[3][6][2].bold and phase_lines[7][4][2].fg == "#eeeeee" and not phase_lines[7][4][2].bold, "inactive top side and bottom borders use foreground without bold")
phase:handle_key("l", fake)
check(phase:render()[2][4][2].fg == "#ffaa00" and phase:render()[2][4][2].bold and phase:render()[2][2][2].fg == "#eeeeee" and not phase:render()[2][2][2].bold, "column navigation transfers focused border styling")
phase:handle_key("h", fake)
phase:handle_key("G", fake)
check(phase:selected_task().id == "task-30" and phase._state.offsets[1] == 26 and row(phase:render(), 6):find("▸ Title task-30", 1, true), "G reaches last task and exact final viewport row")
phase:handle_key("g", fake)
check(phase:selected_task().id == "task-1" and phase._state.offsets[1] == 0, "g restores first task and offset")
for _, key in ipairs({ "1", "2", "3", "H", "L" }) do
  local lines, calls, updates = phase:render(), fake.calls, #fake.updates
  check(phase:handle_key(key, fake) == false and phase:render() == lines and phase._state.focused_column == 1 and phase:selected_task().id == "task-1" and fake.calls == calls and #fake.updates == updates, "removed Board shortcut is ignored: " .. key)
end
for _, height in ipairs({ 3, 4, 5, 6, 7, 8, 9, 12, 27 }) do
  phase:resize(90, height)
  phase:handle_key("G", fake)
  local lines = phase:render()
  local footer_row = height >= 8 and height - 2 or height - 1
  check(#lines == height and row(lines, footer_row):find("NORMAL", 1, true) and row(lines, footer_row):find("? help   q quit", 1, true), "footer content occupies exact row at height " .. height)
  check(row(lines, footer_row - 1):find("┌", 1, true) and row(lines, footer_row + 1):find("└", 1, true), "footer reserves three bordered rows at height " .. height)
  if height >= 8 then
    check(row(lines, 1) == string.rep(" ", 90) and row(lines, height) == string.rep(" ", 90) and row(lines, height - 4) == string.rep(" ", 90) and row(lines, height - 5):find("└", 1, true), "vertical padding and footer gap define exact column boundary at height " .. height)
    if height > 8 then
      check(phase._state.offsets[1] == 30 - (height - 8) and row(lines, height - 6):find("▸ Title task-30", 1, true), "column viewport is height minus eight at height " .. height)
    end
  end
  for _, line in ipairs(lines) do check(width(text(line)) == 90, "footer layout has exact display width") end
end
phase:resize(90, 12)
phase:handle_key("g", fake)
phase:handle_key("j", fake)
phase:handle_key("d", fake)
check(row(phase:render(), 10):find('Delete "中文 second"?  y/N', 1, true) and phase:render()[10][3][2].fg == "#ff4444" and phase:render()[10][3][2].bold, "titled CJK delete prompt uses bold error styling in footer")
phase:handle_key("n", fake)
fake.error = "reload failed"
phase:reload(fake)
check(row(phase:render(), 10):find("Error: reload failed", 1, true) and phase:render()[10][3][2].fg == "#ff4444" and phase:render()[10][3][2].bold, "reload errors use Error prefix and bold error footer styling")
fake.error = nil
phase:reload(fake)
phase:handle_key("G", fake)
local help_task, help_offset, help_cards = phase:selected_task(), phase._state.offsets[1], phase._state.cards
local help_calls, help_updates, help_deletes, help_creates = fake.calls, #fake.updates, fake.deletes, fake.creates
phase:resize(90, 27)
help_offset = phase._state.offsets[1]
phase:handle_key("?", fake)
local help_lines = phase:render()
local help_text = {}
for _, line in ipairs(help_lines) do help_text[#help_text + 1] = text(line) end
help_text = table.concat(help_text, "\n")
check(help_text:find("Keybindings", 1, true) and help_text:find("g / G", 1, true) and help_text:find("< / >", 1, true) and help_text:find("? / Esc", 1, true), "help displays phase-one navigation actions and dismissal keys")
local help_keys = { "n", "<CR>", "<Enter>", "q", "d", "r", "<", ">", "h", "l", "j", "k", "g", "G", "<Left>", "<Right>", "<Up>", "<Down>", "1", "2", "3", "H", "L" }
for _, key in ipairs(help_keys) do
  check(phase:handle_key(key, fake) and phase._state.help_open and phase:render() == help_lines and phase:selected_task() == help_task and phase._state.offsets[1] == help_offset and phase._state.focused_column == 1 and phase._state.cards == help_cards and fake.calls == help_calls and #fake.updates == help_updates and fake.deletes == help_deletes and fake.creates == help_creates, "help consumes key without side effects: " .. key)
end
phase:handle_key("?", fake)
check(not phase._state.help_open and phase:selected_task() == help_task and phase._state.offsets[1] == help_offset, "question mark toggles help off without navigation")
phase:handle_key("g", fake)
help_task = phase:selected_task()
phase:handle_key("?", fake)
for _, size in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 3 }, { 7, 7 }, { 8, 8 }, { 20, 10 }, { 35, 20 }, { 90, 27 } }) do
  phase:resize(size[1], size[2])
  check(phase._state.help_open and phase:selected_task() == help_task and #phase:render() == size[2], "help resize preserves state and exact height")
  for _, line in ipairs(phase:render()) do check(width(text(line)) == size[1], "help overlay remains bounded with CJK beneath it") end
end
phase:handle_key("<Esc>", fake)
check(not phase._state.help_open and phase:selected_task() == help_task, "Esc dismisses help without clearing task selection")
observed = {}
fake.result = board(regression_ids)
local regression_calls, regression_updates = fake.calls, #fake.updates
run({ { type = "key", key = "G" }, function() observed.last = selected_title() end,
  { type = "key", key = "g" }, function() observed.first = snapshot() end,
  { type = "key", key = "1" }, { type = "key", key = "2" }, { type = "key", key = "3" }, { type = "key", key = "H" }, { type = "key", key = "L" },
  function() observed.removed = snapshot() end, { type = "key", key = "q" },
})
check(observed.last:find("task-30", 1, true) and observed.first:find("▸ Title task-1", 1, true) and observed.removed == observed.first and fake.calls == regression_calls + 1 and #fake.updates == regression_updates, "event loop supports g/G and ignores removed shortcuts")
for _, key in ipairs(help_keys) do
  fake.result = board(regression_ids)
  fake.result.tasks["task-1"].title = "中文 first"
  local calls, updates, deletes, creates = fake.calls, #fake.updates, fake.deletes, fake.creates
  local reached = false
  observed = {}
  run({ { type = "key", key = "G" }, function() observed.before = snapshot() end,
    { type = "key", key = "?" }, function() observed.help = snapshot() end,
    { type = "key", key = key }, function() reached = true; check(snapshot() == observed.help and not last_win.closed, "event loop help consumes " .. key) end,
    { type = "key", key = "<Esc>" }, function() check(snapshot() == observed.before and not last_win.closed, "event loop Esc dismisses help preserving selection viewport and focus") end,
    { type = "key", key = "?" }, { type = "key", key = "?" }, function() check(snapshot() == observed.before, "event loop question mark toggles help") end,
    { type = "key", key = "q" },
  })
  check(reached and last_win.closed and fake.calls == calls + 1 and #fake.updates == updates and fake.deletes == deletes and fake.creates == creates, "event loop help has no Store or view side effects: " .. key)
end
fake.result = { tasks = { ["task-1"] = { title = "中文中文中文", status = "todo" } } }
local resize_help_events = { { type = "key", key = "?" } }
for _, size in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 4 }, { 8, 8 }, { 20, 10 }, { 90, 27 } }) do
  local cols, rows = size[1], size[2]
  resize_help_events[#resize_help_events + 1] = { type = "resize", width = cols, height = rows }
  resize_help_events[#resize_help_events + 1] = function()
    check(#last_buf.lines == rows, "event loop help resize keeps exact height")
    for _, line in ipairs(last_buf.lines) do check(width(text(line)) == cols, "event loop help resize fits exact width from 1x1 upwards") end
  end
end
resize_help_events[#resize_help_events + 1] = { type = "key", key = "<Esc>" }
resize_help_events[#resize_help_events + 1] = function() check(selected_title():find("中文", 1, true), "event loop help resize and Esc preserve CJK selection") end
resize_help_events[#resize_help_events + 1] = { type = "key", key = "q" }
run(resize_help_events)

local tiny_footer = Board.new(20, 1)
fake.error = "disk failed"
tiny_footer:reload(fake)
check(row(tiny_footer:render(), 1):find("Error: disk", 1, true), "single-row footer displays clipped errors instead of only border")
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

for _, keys in ipairs({ {}, { "?" }, { "d" }, { "<CR>" }, { "<CR>", "<CR>" }, { "n" }, { "n", "<CR>" }, { "<CR>", "d" } }) do
  fake.result = board({ "task-1" })
  local events = {}
  for _, key in ipairs(keys) do events[#events + 1] = { type = "key", key = key } end
  local reached, deletes, updates, creates = false, fake.deletes, #fake.updates, fake.creates
  events[#events + 1] = { type = "key", key = "<C-c>" }
  events[#events + 1] = function() reached = true end
  run(events)
  check(last_win.closed and not reached, "Ctrl+C immediately closes kanban from " .. table.concat(keys, ","))
  check(fake.deletes == deletes and #fake.updates == updates and fake.creates == creates, "Ctrl+C exits without saving or deleting")
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
