local script = (arg and arg[0]) or "tests/store.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/lua/?.lua;" .. package.path

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local text = f:read("*a")
  f:close()
  return text
end

local function shell_ok(cmd)
  local rc = os.execute(cmd)
  return rc == true or rc == 0
end

local function quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function json_escape(s)
  return (s:gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end))
end

local function array_len(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then
      return nil
    end
    n = n + 1
  end
  return n
end

local function json_encode(v)
  local tv = type(v)
  if v == nil then
    return "null"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return "null"
    end
    if math.floor(v) == v then
      return string.format("%d", v)
    end
    return string.format("%.14g", v)
  elseif tv == "string" then
    return '"' .. json_escape(v) .. '"'
  elseif tv == "table" then
    local n = array_len(v)
    if n and n > 0 then
      local parts = {}
      for i = 1, n do
        parts[i] = json_encode(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, val in pairs(v) do
      parts[#parts + 1] = json_encode(tostring(k)) .. ":" .. json_encode(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function json_decode(text)
  local pos = 1
  local len = #text

  local function fail(msg)
    error(msg .. " at " .. pos, 0)
  end

  local function skip()
    while true do
      local c = text:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then
        pos = pos + 1
      else
        return
      end
    end
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local out = {}
    while true do
      local c = text:sub(pos, pos)
      if c == "" then
        fail("unterminated string")
      elseif c == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        if e == "n" then out[#out + 1] = "\n"
        elseif e == "t" then out[#out + 1] = "\t"
        elseif e == "r" then out[#out + 1] = "\r"
        elseif e == "b" then out[#out + 1] = "\b"
        elseif e == "f" then out[#out + 1] = "\f"
        elseif e == "u" then
          out[#out + 1] = string.char(tonumber(text:sub(pos + 2, pos + 5), 16) % 256)
          pos = pos + 4
        else
          out[#out + 1] = e
        end
        pos = pos + 2
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
  end

  local function parse_number()
    local s = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not s or s == "" then
      fail("invalid number")
    end
    pos = pos + #s
    return tonumber(s)
  end

  local function parse_array()
    pos = pos + 1
    local out = {}
    skip()
    if text:sub(pos, pos) == "]" then
      pos = pos + 1
      return out
    end
    while true do
      out[#out + 1] = parse_value()
      skip()
      local c = text:sub(pos, pos)
      if c == "," then
        pos = pos + 1
        skip()
      elseif c == "]" then
        pos = pos + 1
        return out
      else
        fail("expected ] or ,")
      end
    end
  end

  local function parse_object()
    pos = pos + 1
    local out = {}
    skip()
    if text:sub(pos, pos) == "}" then
      pos = pos + 1
      return out
    end
    while true do
      skip()
      if text:sub(pos, pos) ~= '"' then
        fail("expected key")
      end
      local key = parse_string()
      skip()
      if text:sub(pos, pos) ~= ":" then
        fail("expected :")
      end
      pos = pos + 1
      out[key] = parse_value()
      skip()
      local c = text:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "}" then
        pos = pos + 1
        return out
      else
        fail("expected } or ,")
      end
    end
  end

  parse_value = function()
    skip()
    local c = text:sub(pos, pos)
    if c == "{" then return parse_object() end
    if c == "[" then return parse_array() end
    if c == '"' then return parse_string() end
    if c == "t" and text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if c == "f" and text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if c == "n" and text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
    return parse_number()
  end

  local value = parse_value()
  skip()
  if pos <= len then
    fail("trailing data")
  end
  return value
end

local maki = {}
maki.uv = {
  cwd = function()
    local p = io.popen("pwd")
    if not p then
      return nil
    end
    local dir = p:read("*l")
    p:close()
    return dir
  end,
}

maki.fs = {
  metadata = function(path)
    local f = io.open(path, "rb")
    if not f then
      return nil, nil
    end
    f:close()
    return { path = path }, nil
  end,
  read = read_file,
  dirname = function(path)
    local dir = path:match("^(.*)[/\\][^/\\]*$")
    if dir == nil or dir == "" then
      return "."
    end
    return dir
  end,
  joinpath = function(...)
    local parts = { ... }
    local out = table.concat(parts, "/")
    out = out:gsub("//+", "/")
    return out
  end,
  mkdir = function(dir)
    if dir == nil or dir == "" then
      return true
    end
    if not shell_ok("mkdir -p " .. quote(dir)) then
      return nil, "mkdir failed: " .. dir
    end
    return true
  end,
  atomic_write = function(path, text)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then
      return nil, tostring(err)
    end
    f:write(text)
    f:close()
    local ok, rerr = os.rename(tmp, path)
    if not ok then
      return nil, tostring(rerr)
    end
    return true
  end,
}

maki.json = {
  encode = function(value)
    local ok, text = pcall(json_encode, value)
    if not ok then
      return nil, text
    end
    return text
  end,
  decode = function(text)
    local ok, value = pcall(json_decode, text)
    if not ok then
      return nil, value
    end
    if value == nil then
      return nil, "empty document"
    end
    return value
  end,
}

_G.maki = maki

local Store = require("kanban.store")

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

local base = "/tmp/kanban-store-test-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 1000000))
ok(shell_ok("mkdir -p " .. quote(base)), "create temp dir")

local n = 0
local function fresh()
  n = n + 1
  return base .. "/case" .. tostring(n) .. "/kanban.json"
end

local function write_raw(path, text)
  local dir = path:match("^(.*)/[^/]*$")
  shell_ok("mkdir -p " .. quote(dir))
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function test_missing()
  local path = fresh()
  local s = Store.new(path)

  local board, err = s:load()
  ok(board ~= nil, "missing load returns board: " .. tostring(err))
  ok(type(board.tasks) == "table", "missing board has tasks table")
  eq(next(board.tasks), nil, "missing board is empty")

  local tasks = s:list()
  ok(tasks ~= nil, "missing list returns table")
  eq(#tasks, 0, "missing list is empty")

  local task, gerr = s:get("task-1")
  eq(task, nil, "missing get returns nil")
  eq(gerr, "task not found: task-1", "missing get error")
end

local function test_create_get_list()
  local path = fresh()
  local s = Store.new(path)

  local a = s:create({ title = "A", description = "first" })
  ok(a ~= nil, "create A succeeds")
  eq(a.id, "task-1", "first id")
  eq(a.title, "A", "first title")
  eq(a.description, "first", "first description")
  eq(a.status, "todo", "create defaults to todo")

  local b = s:create({ title = "B" })
  eq(b.id, "task-2", "second id")
  eq(b.description, "", "description defaults to empty")
  eq(b.status, "todo", "second status todo")

  local got = s:get("task-1")
  eq(got.title, "A", "get returns created title")
  eq(got.status, "todo", "get returns created status")

  local list = s:list()
  eq(#list, 2, "list has two tasks")
  eq(list[1].id, "task-1", "list sorted first id")
  eq(list[2].id, "task-2", "list sorted second id")

  local raw = read_file(path)
  ok(raw ~= nil and raw:find("task-1", 1, true) and raw:find("task-2", 1, true), "file persisted both tasks")
end

local function test_update()
  local path = fresh()
  local s = Store.new(path)
  s:create({ title = "A" })

  local up = s:update("task-1", { title = "A2", status = "doing" })
  ok(up ~= nil, "update succeeds")
  eq(up.title, "A2", "update title")
  eq(up.status, "doing", "update status")
  eq(up.description, "", "update keeps description")

  local reloaded = Store.new(path)
  local got = reloaded:get("task-1")
  eq(got.title, "A2", "update persisted title")
  eq(got.status, "doing", "update persisted status")

  local unchanged = s:update("task-1", {})
  eq(unchanged, nil, "update with no fields returns nil")
end

local function test_invalid()
  local path = fresh()
  local s = Store.new(path)

  local t, e = s:create({})
  eq(t, nil, "create without title nil")
  eq(e, "title must be a string", "create title type error")

  t, e = s:create({ title = "   " })
  eq(t, nil, "create blank title nil")
  eq(e, "title must not be empty", "create blank title error")

  t, e = s:create({ title = "x", description = 5 })
  eq(t, nil, "create numeric description nil")
  eq(e, "description must be a string", "create description error")

  t, e = s:create({ title = "x", status = "doing" })
  eq(t, nil, "create non-todo status nil")
  eq(e, "invalid status: doing", "create status error")

  t, e = s:create("nope")
  eq(t, nil, "create non-table nil")
  eq(e, "task must be an object", "create non-table error")

  t, e = s:get(1)
  eq(t, nil, "get non-string nil")
  eq(e, "id must be a string", "get non-string error")

  s:create({ title = "A" })

  t, e = s:update("task-1", { status = "bogus" })
  eq(t, nil, "update bad status nil")
  eq(e, "invalid status: bogus", "update bad status error")

  t, e = s:update("task-1", { title = "" })
  eq(t, nil, "update blank title nil")
  eq(e, "title must not be empty", "update blank title error")

  t, e = s:update("task-1", "nope")
  eq(t, nil, "update non-table nil")
  eq(e, "update must be an object", "update non-table error")
end

local function test_unknown()
  local path = fresh()
  write_raw(path, '{"tasks":{"task-1":{"title":"A","description":"","status":"todo"}}}')
  local s = Store.new(path)

  local t, e = s:get("task-9")
  eq(t, nil, "get unknown nil")
  eq(e, "task not found: task-9", "get unknown error")

  t, e = s:update("task-9", { title = "B" })
  eq(t, nil, "update unknown nil")
  eq(e, "task not found: task-9", "update unknown error")
end

local function test_malformed()
  local path = fresh()

  local broken = "{ this is not json"
  write_raw(path, broken)
  local s = Store.new(path)

  local board, e = s:load()
  eq(board, nil, "malformed load nil")
  ok(e and e:find("invalid kanban store"), "malformed load error: " .. tostring(e))

  local got = s:get("task-1")
  eq(got, nil, "get on malformed nil")
  local listed = s:list()
  eq(listed, nil, "list on malformed nil")

  local t = s:create({ title = "A" })
  eq(t, nil, "create on malformed nil")
  eq(read_file(path), broken, "malformed file not overwritten by create")

  local bad_schema = '{"tasks":{"task-1":{"title":"A"}}}'
  write_raw(path, bad_schema)
  board, e = s:load()
  eq(board, nil, "bad schema load nil")
  t = s:create({ title = "A" })
  eq(t, nil, "create on bad schema nil")
  eq(read_file(path), bad_schema, "bad schema file not overwritten")

  local array = '{"tasks":[{"title":"A","description":"","status":"todo"}]}'
  write_raw(path, array)
  board, e = s:load()
  eq(board, nil, "tasks array load nil")
  ok(e and e:find("tasks must be an object"), "tasks array rejected: " .. tostring(e))
  t = s:create({ title = "A" })
  eq(t, nil, "create on tasks array nil")
  eq(read_file(path), array, "tasks array file not overwritten")
end

local function test_collision_no_overwrite()
  local path = fresh()
  write_raw(path, '{"tasks":{"task-1":{"title":"old","description":"","status":"done"}}}')

  local s = Store.new(path)
  local t = s:create({ title = "new" })
  eq(t.id, "task-2", "create avoids existing id")

  local board = s:load()
  eq(board.tasks["task-1"].title, "old", "existing task title preserved")
  eq(board.tasks["task-1"].status, "done", "existing task status preserved")
  eq(board.tasks["task-2"].title, "new", "new task written")

  local stale = Store.new(path)
  local existing = stale:list()
  eq(#existing, 2, "stale instance reads current file")

  local json = maki.json
  local data = json.decode('{"tasks":{"task-1":{"title":"one","description":"","status":"todo"},"task-2":{"title":"two","description":"","status":"todo"}}}')
  write_raw(path, json.encode(data))

  local late = stale:create({ title = "late" })
  eq(late.id, "task-3", "create loads current file before writing")

  local final = Store.new(path):load()
  eq(final.tasks["task-1"].title, "one", "external task-1 preserved")
  eq(final.tasks["task-2"].title, "two", "external task-2 preserved")
  eq(final.tasks["task-3"].title, "late", "late task added")
end

local function test_read_reload()
  local path = fresh()
  local s = Store.new(path)
  s:create({ title = "A" })

  local before = s:get("task-1")
  eq(before.title, "A", "initial title")

  write_raw(path, '{"tasks":{"task-1":{"title":"edited","description":"","status":"doing"}}}')

  local after = s:get("task-1")
  eq(after.title, "edited", "get reloads current file")
  eq(after.status, "doing", "get returns persisted status")

  local list = s:list()
  eq(list[1].title, "edited", "list reloads current file")
end

local tests = {
  test_missing,
  test_create_get_list,
  test_update,
  test_invalid,
  test_unknown,
  test_malformed,
  test_collision_no_overwrite,
  test_read_reload,
}

for _, test in ipairs(tests) do
  local run_ok, err = pcall(test)
  if not run_ok then
    fail = fail + 1
    print("ERROR: " .. tostring(err))
  end
end

shell_ok("rm -rf " .. quote(base))

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then
  os.exit(1)
end
