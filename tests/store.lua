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
  return (
    s:gsub('[%z\1-\31\\"]', function(c)
      if c == '"' then
        return '\\"'
      end
      if c == "\\" then
        return "\\\\"
      end
      if c == "\n" then
        return "\\n"
      end
      if c == "\r" then
        return "\\r"
      end
      if c == "\t" then
        return "\\t"
      end
      return string.format("\\u%04x", c:byte())
    end)
  )
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
        if e == "n" then
          out[#out + 1] = "\n"
        elseif e == "t" then
          out[#out + 1] = "\t"
        elseif e == "r" then
          out[#out + 1] = "\r"
        elseif e == "b" then
          out[#out + 1] = "\b"
        elseif e == "f" then
          out[#out + 1] = "\f"
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
    if c == "{" then
      return parse_object()
    end
    if c == "[" then
      return parse_array()
    end
    if c == '"' then
      return parse_string()
    end
    if c == "t" and text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    end
    if c == "f" and text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    end
    if c == "n" and text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end
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

local function seed(s)
  return assert(s:create_many({
    { title = "A", description = "first" },
    { title = "B" },
    { title = "C" },
  }))
end

local function test_missing()
  local path = fresh()
  local s = Store.new(path)
  local board = assert(s:load())
  eq(next(board.tasks), nil, "missing board is empty")
  eq(#s:list(), 0, "missing list is empty")
  for _, method in ipairs({ "get_many", "update_many", "delete_many" }) do
    local input = method == "update_many" and { ["task-1"] = { title = "A" } } or { "task-1" }
    local result, err = s[method](s, input)
    eq(result, nil, method .. " rejects missing task")
    eq(err, "task not found: task-1", method .. " missing error")
    eq(read_file(path), nil, method .. " does not create file")
  end
  ok(s:save(), "save preserves missing-store behavior")
  eq(#s:list(), 0, "save creates empty board")
end

local function test_success()
  local path = fresh()
  local s = Store.new(path)
  local created = seed(s)
  eq(created["task-1"].id, "task-1", "create returns ID-keyed public task")
  eq(created["task-1"].description, "first", "create description")
  eq(created["task-2"].description, "", "default description")
  eq(created["task-3"].status, "todo", "default status")
  eq(s:create_many({ { title = "D", status = "todo" } })["task-4"].title, "D", "single create")
  eq(s:get_many({ "task-1" })["task-1"].title, "A", "single get")
  local got = assert(s:get_many({ "task-3", "task-1" }))
  eq(got["task-3"].title, "C", "multi get")
  eq(got["task-2"], nil, "get excludes unrequested task")
  got["task-1"].title = "detached"
  eq(s:get_many({ "task-1" })["task-1"].title, "A", "public result detached")

  local patches = {
    ["task-1"] = { title = "A2" },
    ["task-2"] = { description = "second" },
    ["task-3"] = { status = "done" },
  }
  local updated = assert(s:update_many(patches))
  eq(updated["task-1"].title, "A2", "multi update title")
  eq(updated["task-1"].description, "first", "update preserves description")
  eq(updated["task-2"].description, "second", "multi update description")
  eq(updated["task-3"].status, "done", "multi update status")
  eq(patches["task-1"].status, nil, "update does not mutate patches")
  eq(s:update_many({ ["task-1"] = { status = "doing", description = "" } })["task-1"].status, "doing", "single update")
  local list = Store.new(path):list()
  eq(#list, 4, "list preserves all tasks")
  eq(list[1].id, "task-1", "list sorted first")
  eq(list[4].id, "task-4", "list sorted last")
  eq(list[3].status, "done", "update persisted")

  local deleted = assert(s:delete_many({ "task-1", "task-3" }))
  eq(deleted["task-1"].status, "doing", "delete returns prior status")
  eq(deleted["task-3"].title, "C", "multi delete result")
  local fields = 0
  for _ in pairs(deleted["task-1"]) do
    fields = fields + 1
  end
  eq(fields, 4, "delete public fields only")
  eq(#Store.new(path):list(), 2, "multi delete persisted")
  eq(
    s:create_many({ { title = "replacement" }, { title = "replacement2" } })["task-3"].title,
    "replacement2",
    "create fills holes without collisions"
  )
  eq(s:get_many({ "task-2" })["task-2"].description, "second", "collision preserves existing task")
  ok(s:delete_many({ "task-1" }), "single delete")
  ok(s:delete_many({ "task-2", "task-3", "task-4" }), "delete all remaining tasks")
  eq(#s:list(), 0, "empty board persisted")
  eq(s:create_many({ { title = "restart" } })["task-1"].id, "task-1", "empty board reuses first id")
end

local function test_rejected()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local before = read_file(path)
  local function reject(method, input, message)
    local result, err = s[method](s, input)
    eq(result, nil, message)
    ok(type(err) == "string", message .. " has error")
    eq(read_file(path), before, message .. " preserves bytes")
  end
  for _, method in ipairs({ "get_many", "create_many", "delete_many" }) do
    for _, input in ipairs({
      false,
      "nope",
      {},
      { key = "task-1" },
      { [2] = "task-1" },
      { [1] = "task-1", [3] = "task-2" },
      { "task-1", extra = true },
    }) do
      reject(method, input, method .. " rejects non-array/empty/sparse/mixed input")
    end
    reject(method, nil, method .. " rejects nil")
  end
  for _, method in ipairs({ "get_many", "delete_many" }) do
    for _, input in ipairs({ { 1 }, { false }, { {} }, { "task-1", "task-1" }, { "task-1", "task-9", "task-3" } }) do
      reject(method, input, method .. " rejects invalid/duplicate/missing ID")
    end
  end
  for _, input in ipairs({
    {},
    { title = "" },
    { title = "  " },
    { title = false },
    { title = "X", description = 5 },
    { title = "X", status = "doing" },
    { title = "X", status = false },
    "nope",
    { "X" },
    { title = "X", [2] = true },
  }) do
    reject(
      "create_many",
      { { title = "valid" }, input, { title = "also valid" } },
      "invalid middle create rejects whole batch"
    )
  end
  for _, input in ipairs({
    false,
    "nope",
    {},
    { { title = "X" } },
    { [1] = { title = "X" }, ["task-1"] = { title = "X" } },
  }) do
    reject("update_many", input, "update rejects non-object/empty/non-string key")
  end
  reject("update_many", nil, "update rejects nil")
  for _, patch in ipairs({
    {},
    false,
    "nope",
    { "X" },
    { title = "" },
    { title = false },
    { description = 1 },
    { status = "bogus" },
    { status = false },
    { unknown = true },
    { title = "valid", id = "task-2" },
  }) do
    reject(
      "update_many",
      { ["task-1"] = { title = "changed" }, ["task-2"] = patch, ["task-3"] = { status = "done" } },
      "invalid patch rejects whole batch"
    )
  end
  reject(
    "update_many",
    { ["task-1"] = { title = "changed" }, ["task-9"] = { status = "done" } },
    "missing update rejects whole batch"
  )
  eq(s:create_many({ { title = "next" } })["task-4"].id, "task-4", "rejected create consumes no IDs")
end

local function test_malformed()
  local path = fresh()
  local s = Store.new(path)
  for _, broken in ipairs({
    "{ this is not json",
    '{"tasks":{"task-1":{"title":"A"}}}',
    '{"tasks":[{"title":"A","status":"todo"}]}',
  }) do
    write_raw(path, broken)
    for _, operation in ipairs({
      { "load" },
      { "save" },
      { "list" },
      { "get_many", { "task-1" } },
      { "create_many", { { title = "A" }, { title = "B" } } },
      { "update_many", { ["task-1"] = { title = "B" } } },
      { "delete_many", { "task-1" } },
    }) do
      local result, err = s[operation[1]](s, operation[2])
      eq(result, nil, operation[1] .. " rejects malformed store")
      ok(err and err:find("invalid kanban store", 1, true), operation[1] .. " malformed error")
      eq(read_file(path), broken, operation[1] .. " preserves malformed bytes")
    end
  end
end

local function test_reload()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  write_raw(path, '{"tasks":{"task-1":{"title":"external","description":"details","status":"doing"}}}')
  eq(s:get_many({ "task-1" })["task-1"].title, "external", "get reloads")
  eq(s:list()[1].status, "doing", "list reloads")
  eq(s:create_many({ { title = "new" }, { title = "new2" } })["task-3"].title, "new2", "create reads current IDs")
  eq(
    s:update_many({ ["task-1"] = { title = "updated" } })["task-1"].description,
    "details",
    "update preserves external fields"
  )
  eq(s:delete_many({ "task-1" })["task-1"].status, "doing", "delete returns latest fields")
  eq(#s:list(), 2, "external replacement not overwritten")
end

local function test_io_counts()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local old_read, old_write = maki.fs.read, maki.fs.atomic_write
  local reads, writes = 0, 0
  maki.fs.read = function(...)
    reads = reads + 1
    return old_read(...)
  end
  maki.fs.atomic_write = function(...)
    writes = writes + 1
    return old_write(...)
  end
  local operations = {
    { "get_many", { "task-1", "task-2" }, 0 },
    { "create_many", { { title = "D" }, { title = "E" } }, 1 },
    { "update_many", { ["task-1"] = { title = "A2" }, ["task-2"] = { status = "done" } }, 1 },
    { "delete_many", { "task-4", "task-5" }, 1 },
    { "update_many", { ["task-1"] = { title = "bad" }, ["task-2"] = {} }, 0 },
    { "delete_many", { "task-1", "missing" }, 0 },
    { "get_many", { "task-1", "missing" }, 0 },
  }
  for _, operation in ipairs(operations) do
    reads, writes = 0, 0
    local result = s[operation[1]](s, operation[2])
    eq(reads, 1, operation[1] .. " reads once")
    eq(writes, operation[3], operation[1] .. " atomic write count")
    if operation[3] == 1 then
      ok(result, operation[1] .. " succeeds")
    end
  end
  reads, writes = 0, 0
  eq(s:create_many({ { title = "valid" }, {} }), nil, "invalid create fails before allocation")
  eq(writes, 0, "invalid create does not write")
  ok(reads <= 1, "invalid create reads at most once")
  maki.fs.read, maki.fs.atomic_write = old_read, old_write
end

local function test_persistence_failure()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local before = read_file(path)
  for _, failure in ipairs({
    { maki.json, "encode", "could not encode store: injected failure" },
    { maki.fs, "mkdir", "could not create store directory: injected failure" },
    { maki.fs, "atomic_write", "could not write store: injected failure" },
  }) do
    for _, operation in ipairs({
      { "create_many", { { title = "D" }, { title = "E" } } },
      { "update_many", { ["task-1"] = { title = "changed" }, ["task-2"] = { status = "done" } } },
      { "delete_many", { "task-1", "task-2" } },
    }) do
      local owner, key = failure[1], failure[2]
      local original = owner[key]
      owner[key] = function()
        return nil, "injected failure"
      end
      local result, err = s[operation[1]](s, operation[2])
      owner[key] = original
      eq(result, nil, operation[1] .. " persistence failure")
      eq(err, failure[3], "persistence error propagated")
      eq(read_file(path), before, "persistence failure preserves bytes")
    end
  end
  ok(s:delete_many({ "task-1", "task-2" }), "write recovers")
end

local function test_tool_registration()
  local registered = {}
  local function check_schema(schema)
    if schema.type == "object" then
      assert(type(schema.properties) == "table", "object schema missing properties")
      for _, property in pairs(schema.properties) do
        check_schema(property)
      end
      if type(schema.additionalProperties) == "table" then
        check_schema(schema.additionalProperties)
      end
    elseif schema.type == "array" then
      check_schema(schema.items)
    end
  end
  maki.api = {
    register_tool = function(spec)
      check_schema(spec.schema)
      registered[spec.name] = spec
    end,
  }
  require("kanban.tools").register()
  for _, name in ipairs({ "task_list", "task_get", "task_create", "task_update", "task_delete" }) do
    ok(registered[name] ~= nil, name .. " registers")
  end
  local tasks = registered.task_update.schema.properties.tasks
  eq(tasks.type, nil, "update preserves dynamic task IDs through host validation")
  eq(tasks.properties, nil, "update does not discard dynamic keys")
  ok(tasks.description:find("todo, doing, or done", 1, true) ~= nil, "update describes valid statuses")
end

local tests = {
  test_tool_registration,
  test_missing,
  test_success,
  test_rejected,
  test_malformed,
  test_reload,
  test_io_counts,
  test_persistence_failure,
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
