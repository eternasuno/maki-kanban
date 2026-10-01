--# selene: allow(undefined_variable, unscoped_variables)
local host_width, host_truncate = maki.ui.display_width, maki.ui.truncate_text
local scanned, calls = 0, 0
maki.ui.display_width = function(value)
  scanned, calls = scanned + #value, calls + 1
  return host_width(value)
end
maki.ui.truncate_text = function(value, limit)
  scanned, calls = scanned + #value, calls + 1
  return host_truncate(value, limit)
end
local body = string.rep("description 中文 words ", 1000)
local task = Task.new({ id = "task-1", title = "abc", description = body, status = "todo" }, 36, 12)
local cached = task.description_lines
local function unchanged(label, action)
  scanned, calls = 0, 0
  action()
  task:render()
  check(task.description_lines == cached, label .. " preserves cached description lines")
  check(scanned < #body and calls < 300, label .. " avoids host scans of unchanged description")
end
unchanged("begin title", function()
  task:handle_key("<CR>", fake)
end)
unchanged("title character", function()
  task:handle_key("x", fake)
end)
unchanged("title paste", function()
  task:handle_paste("y\n中文")
end)
for _, key in ipairs({ "<Home>", "<Right>", "<Left>", "<End>" }) do
  unchanged(key .. " cursor", function()
    task:handle_key(key, fake)
  end)
end
unchanged("height resize", function()
  task:resize(36, 20)
end)
unchanged("title cancel", function()
  task:handle_key("<Esc>", fake)
end)
scanned = 0
task:resize(40, 20)
check(task.description_lines ~= cached and scanned >= #body, "width change invalidates and rewraps description")
cached = task.description_lines
local before = table.concat(cached)
task.task.description = "replacement\nbody"
task:resize(40, 20)
check(
  task.description_lines ~= cached
    and table.concat(task.description_lines) ~= before
    and task.description_lines[1] == "replacement",
  "content change invalidates cached description"
)
cached = task.description_lines
unchanged("same width and content", function()
  task:resize(40, 20)
end)

for _, unit in ipairs({ "a", "中" }) do
  local previous
  for _, count in ipairs({ 4096, 16384 }) do
    local content = string.rep(unit, count)
    scanned, calls = 0, 0
    local wrapped = Task.new({ title = "", description = content, status = "todo" }, 36, 12)
    local cost = scanned
    check(table.concat(wrapped.description_lines) == content, "long wrapping preserves all " .. unit .. " bytes")
    check(cost <= #content * 25 + 1024, "long wrapping host scanned bytes have linear bound: " .. unit .. count)
    if previous then
      check(cost <= previous * 5, "quadrupled content increases host scan cost at most fivefold")
    end
    previous = cost
  end
end
local base_width, base_truncate = host_width, host_truncate
local combining = "́"
local function complete_utf8(value)
  local bytes = 0
  for char in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local first = char:byte(1)
    local size = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
    assert(#char == size, "host receives complete UTF-8 characters")
    bytes = bytes + #char
  end
  assert(bytes == #value, "host receives no orphaned continuation bytes")
end
host_width = function(value)
  complete_utf8(value)
  return base_width((value:gsub(combining, "")))
end
host_truncate = function(value, limit)
  complete_utf8(value)
  local used, last = 0, 0
  for char in value:gmatch(".[\128-\191]*") do
    local char_width = char == combining and 0 or base_width(char)
    if used + char_width > limit then
      break
    end
    used, last = used + char_width, last + #char
  end
  return { head = value:sub(1, last), tail = value:sub(last + 1) }
end

for _, prefix in ipairs({ "", string.rep("a", 32), string.rep("中", 16) }) do
  local previous
  for _, count in ipairs({ 8192, 32768 }) do
    local content = prefix .. string.rep(combining, count) .. (prefix == "" and "" or "b")
    scanned, calls = 0, 0
    local wrapped = Task.new({ title = "", description = content, status = "todo" }, 36, 12)
    local cost = scanned
    check(table.concat(wrapped.description_lines) == content, "long zero-width wrapping preserves all bytes")
    check(cost <= #content * 8 + 1024, "long zero-width wrapping has a linear host scan bound")
    check(#wrapped.description_lines == (prefix == "" and 1 or 2), "combining marks stay on the filled row")
    if prefix ~= "" then
      check(wrapped.description_lines[2] == "b", "visible suffix wraps after combining marks")
    end
    if previous then
      check(cost <= previous * 5, "quadrupled zero-width content increases scan cost at most fivefold")
    end
    previous = cost
  end
end

for _, content in ipairs({
  string.rep("a", 255) .. combining .. "中b",
  string.rep("中", 85) .. combining .. "ab",
  "a" .. string.rep(combining, 127) .. "中b",
  "a" .. string.rep(combining, 128) .. "中b",
  "a" .. string.rep(combining, 255) .. "中b",
  "a" .. string.rep(combining, 256) .. "中b",
}) do
  for _, width in ipairs({ 1, 2, 32 }) do
    local expected, remaining = {}, content
    while remaining ~= "" do
      local part = host_truncate(remaining, width)
      if part.head == "" then
        expected[#expected + 1] = remaining
        break
      end
      expected[#expected + 1], remaining = part.head, part.tail
    end
    local wrapped = Task.new({ title = "", description = content, status = "todo" }, width + 4, 12)
    check(#wrapped.description_lines == #expected, "chunk boundaries preserve row count")
    for row, line in ipairs(expected) do
      check(wrapped.description_lines[row] == line, "chunk boundaries preserve host wrapping and narrow fallback")
    end
  end
end
maki.ui.display_width, maki.ui.truncate_text = base_width, base_truncate
