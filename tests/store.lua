local script = (arg and arg[0]) or "tests/store.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/lua/?.lua;" .. package.path

local function clone(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = clone(item)
  end
  return copy
end

local files, snapshots, errors, calls = {}, { ["[]"] = {} }, {}, {}
local next_token = 0
local function called(name)
  calls[name] = (calls[name] or 0) + 1
  return errors[name]
end

local maki = {
  uv = {
    cwd = function()
      return "/project"
    end,
  },
  fs = {
    metadata = function(path)
      local err = called("metadata")
      if err then
        return nil, err
      end
      return files[path] ~= nil and {} or nil
    end,
    read = function(path)
      local err = called("read")
      if err then
        return nil, err
      end
      if files[path] == nil then
        return nil, "file not found"
      end
      return files[path]
    end,
    dirname = function(path)
      return path:match("^(.*)/[^/]*$") or "."
    end,
    joinpath = function(...)
      return table.concat({ ... }, "/")
    end,
    mkdir = function()
      local err = called("mkdir")
      if err then
        return nil, err
      end
      return true
    end,
    atomic_write = function(path, token)
      local err = called("atomic_write")
      if err then
        return nil, err
      end
      files[path] = token
      return true
    end,
  },
  json = {
    encode = function(value)
      local err = called("encode")
      if err then
        return nil, err
      end
      next_token = next_token + 1
      local token = "snapshot-" .. next_token
      snapshots[token] = clone(value)
      return token
    end,
    decode = function(token)
      local err = called("decode")
      if err then
        return nil, err
      end
      if snapshots[token] == nil then
        return nil, "unknown snapshot token"
      end
      return clone(snapshots[token])
    end,
  },
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

local n = 0
local function fresh()
  n = n + 1
  return "/cases/" .. n .. "/kanban.json"
end

local function persist(path, value)
  files[path] = assert(maki.json.encode(value))
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
  eq(#assert(s:list()), 0, "missing list is empty")
  eq(files[path], nil, "list does not create missing store")
  for _, method in ipairs({ "get_many", "update_many", "delete_many" }) do
    local input = method == "update_many" and { ["task-1"] = { title = "A" } } or { "task-1" }
    local result, err = s[method](s, input)
    eq(result, nil, method .. " rejects missing task")
    eq(err, "task not found: task-1", method .. " missing error")
    eq(files[path], nil, method .. " does not create file")
  end
  eq(assert(s:create_many({ { title = "first" } }))["task-1"].id, "task-1", "first mutation creates store")
  ok(s:delete_many({ "task-1" }), "delete last task")
  eq(#assert(Store.new(path):list()), 0, "CRUD persists empty board")
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

local function test_id_sorting()
  for _, expected in ipairs({
    { "task-2", "task-10", "", "alpha", "task-1x", "zeta" },
    { "task-002", "task-02", "task-2", "task-010", "task-10" },
  }) do
    local path = fresh()
    local tasks = {}
    for _, id in ipairs(expected) do
      tasks[id] = { title = "Task " .. id, status = "todo" }
    end
    persist(path, { tasks = tasks })
    local list = assert(Store.new(path):list())
    eq(#list, #expected, "sorting preserves arbitrary string IDs")
    for i, id in ipairs(expected) do
      eq(list[i].id, id, "IDs sort numerically before lexical IDs, with lexical numeric ties")
    end
  end
end

local function test_rejected()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local before = files[path]
  local function reject(method, input, message)
    local result, err = s[method](s, input)
    eq(result, nil, message)
    ok(type(err) == "string", message .. " has error")
    eq(files[path], before, message .. " preserves snapshot")
  end
  for _, method in ipairs({ "get_many", "create_many", "delete_many" }) do
    for _, input in ipairs({
      false,
      "nope",
      {},
      { key = "task-1" },
      { [2] = "task-1" },
      { [1] = "task-1", [3] = "task-2" },
      -- selene: allow(mixed_table)
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
    { title = " \t\n" },
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
  local broken_values = {
    "not a store object",
    {},
    { tasks = false },
    { tasks = { { title = "A", status = "todo" } } },
    { tasks = { [2] = { title = "A", status = "todo" } } },
    { tasks = { ["task-1"] = false } },
    { tasks = { ["task-1"] = { status = "todo" } } },
    { tasks = { ["task-1"] = { title = " \t\n", status = "todo" } } },
    { tasks = { ["task-1"] = { title = false, status = "todo" } } },
    { tasks = { ["task-1"] = { title = "A", description = false, status = "todo" } } },
    { tasks = { ["task-1"] = { title = "A" } } },
    { tasks = { ["task-1"] = { title = "A", status = "bogus" } } },
    { tasks = { ["task-1"] = { title = "A", status = false } } },
  }
  local tokens = { "malformed raw token" }
  for _, value in ipairs(broken_values) do
    tokens[#tokens + 1] = assert(maki.json.encode(value))
  end
  for _, broken in ipairs(tokens) do
    files[path] = broken
    for _, operation in ipairs({
      { "list" },
      { "get_many", { "task-1" } },
      { "create_many", { { title = "A" }, { title = "B" } } },
      { "update_many", { ["task-1"] = { title = "B" } } },
      { "delete_many", { "task-1" } },
    }) do
      local result, err = s[operation[1]](s, operation[2])
      eq(result, nil, operation[1] .. " rejects malformed store")
      ok(err and err:find("invalid kanban store", 1, true), operation[1] .. " malformed error")
      eq(files[path], broken, operation[1] .. " preserves malformed snapshot")
    end
  end
end

local function test_read_failure()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local before = files[path]
  for _, boundary in ipairs({ "metadata", "read", "decode" }) do
    errors[boundary] = "injected failure"
    for _, operation in ipairs({
      { "list" },
      { "get_many", { "task-1" } },
      { "create_many", { { title = "new" } } },
      { "update_many", { ["task-1"] = { title = "changed" } } },
      { "delete_many", { "task-1" } },
    }) do
      local result, err = s[operation[1]](s, operation[2])
      eq(result, nil, operation[1] .. " rejects " .. boundary .. " failure")
      local prefix = boundary == "decode" and "invalid kanban store: " or "could not read store: "
      eq(err, prefix .. "injected failure", "read boundary error propagated")
      eq(files[path], before, "read failure preserves snapshot")
    end
    errors[boundary] = nil
  end
  eq(s:create_many({ { title = "recovered" } })["task-4"].title, "recovered", "read failures consume no IDs")
end

local function test_detached_snapshots()
  local value = { tasks = { ["task-1"] = { title = "original", status = "todo" } } }
  local token = assert(maki.json.encode(value))
  value.tasks["task-1"].title = "changed after encode"
  local decoded = assert(maki.json.decode(token))
  eq(decoded.tasks["task-1"].title, "original", "encode detaches snapshot")
  decoded.tasks["task-1"].title = "changed after decode"
  eq(maki.json.decode(token).tasks["task-1"].title, "original", "decode detaches snapshot")

  local path = fresh()
  local s = Store.new(path)
  local inputs = { { title = "original" } }
  local created = assert(s:create_many(inputs))
  inputs[1].title, created["task-1"].title = "input mutation", "result mutation"
  local updated = assert(s:update_many({ ["task-1"] = { status = "doing" } }))
  updated["task-1"].status = "done"
  local list = assert(s:list())
  eq(list[1].title, "original", "create inputs and results detached")
  eq(list[1].status, "doing", "update result detached")
  list[1].title = "list mutation"
  eq(s:get_many({ "task-1" })["task-1"].title, "original", "list result detached")
end

local function test_reload()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  persist(path, { tasks = { ["task-1"] = { title = "external", description = "details", status = "doing" } } })
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

local function test_allocation_scale()
  local s = Store.new(fresh())
  local inputs, holes = {}, {}
  for i = 1, 1000 do
    inputs[i] = { title = "existing " .. i }
    if i % 2 == 1 then
      holes[#holes + 1] = "task-" .. i
    end
  end
  assert(s:create_many(inputs))
  assert(s:delete_many(holes))
  inputs = {}
  for i = 1, 600 do
    inputs[i] = { title = "new " .. i }
  end
  local created = assert(s:create_many(inputs))
  for i = 1, 500 do
    eq(created["task-" .. (2 * i - 1)].title, "new " .. i, "batch fills lowest free holes in order")
  end
  for i = 501, 600 do
    eq(created["task-" .. (i + 500)].title, "new " .. i, "batch extends past occupied prefix")
  end
  local list = assert(s:list())
  eq(#list, 1100, "large batch preserves total task count")
  for i, task in ipairs(list) do
    eq(task.id, "task-" .. i, "large board sorted numerically")
    if i <= 1000 and i % 2 == 0 then
      eq(task.title, "existing " .. i, "allocation preserves occupied IDs")
    end
  end
end

local function test_normalization()
  local path = fresh()
  local s = Store.new(path)
  persist(path, { tasks = { ["task-2"] = { id = "ignored", title = "external", status = "done" } } })
  eq(assert(s:get_many({ "task-2" }))["task-2"].description, "", "read normalizes missing description")
  local created = assert(s:create_many({ { title = "first hole" }, { title = "next hole" } }))
  eq(created["task-1"].title, "first hole", "reload fills first hole")
  eq(created["task-3"].title, "next hole", "reload skips occupied ID")
  local persisted = assert(maki.json.decode(files[path])).tasks
  eq(persisted["task-2"].description, "", "CRUD persists normalized description")
  eq(persisted["task-2"].id, nil, "CRUD strips stored body ID")
  eq(persisted["task-2"].status, "done", "CRUD preserves external status")
end

local function test_io_counts()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
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
    calls = {}
    local result = s[operation[1]](s, operation[2])
    eq(calls.read, 1, operation[1] .. " reads once")
    eq(calls.atomic_write or 0, operation[3], operation[1] .. " atomic write count")
    if operation[3] == 1 then
      ok(result, operation[1] .. " succeeds")
    end
  end
end

local function test_persistence_failure()
  local path = fresh()
  local s = Store.new(path)
  seed(s)
  local before = files[path]
  for _, failure in ipairs({
    { "encode", "could not encode store: injected failure" },
    { "mkdir", "could not create store directory: injected failure" },
    { "atomic_write", "could not write store: injected failure" },
  }) do
    for _, operation in ipairs({
      { "create_many", { { title = "D" }, { title = "E" } } },
      { "update_many", { ["task-1"] = { title = "changed" }, ["task-2"] = { status = "done" } } },
      { "delete_many", { "task-1", "task-2" } },
    }) do
      errors[failure[1]] = "injected failure"
      local result, err = s[operation[1]](s, operation[2])
      errors[failure[1]] = nil
      eq(result, nil, operation[1] .. " persistence failure")
      eq(err, failure[2], "persistence error propagated")
      eq(files[path], before, "persistence failure preserves snapshot")
    end
  end
  local recovered = assert(s:create_many({ { title = "D" }, { title = "E" } }))
  eq(recovered["task-4"].title, "D", "failed writes consume no first ID")
  eq(recovered["task-5"].title, "E", "failed writes consume no second ID")
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

  local function output(name, input)
    local result = registered[name].handler(input or {})
    eq(result.is_error, nil, name .. " succeeds")
    return assert(maki.json.decode(result.llm_output))
  end
  eq(#output("task_list"), 0, "empty tool list has no tasks")
  local created = output("task_create", { tasks = { { title = "tool task" } } })
  eq(created["task-1"].status, "todo", "create tool returns ID-keyed tasks")
  eq(output("task_get", { ids = { "task-1" } })["task-1"].title, "tool task", "get tool output")
  eq(output("task_list")[1].id, "task-1", "list tool returns task array")
  eq(
    output("task_update", { tasks = { ["task-1"] = { status = "done" } } })["task-1"].status,
    "done",
    "update tool output"
  )
  eq(output("task_delete", { ids = { "task-1" } })["task-1"].status, "done", "delete tool returns prior task")
  eq(#output("task_list"), 0, "tool deletion leaves empty list")
  local missing = registered.task_get.handler({ ids = { "task-1" } })
  eq(missing.is_error, true, "tool marks business failures")
  eq(missing.llm_output, "error: task not found: task-1", "tool reports business error")
  errors.encode = "injected failure"
  local failed = registered.task_list.handler({})
  errors.encode = nil
  eq(failed.is_error, true, "tool marks output encoding failure")
  eq(failed.llm_output, "error: could not encode json: injected failure", "tool reports output encoding error")
end

local tests = {
  test_tool_registration,
  test_missing,
  test_success,
  test_id_sorting,
  test_rejected,
  test_malformed,
  test_read_failure,
  test_detached_snapshots,
  test_reload,
  test_allocation_scale,
  test_normalization,
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

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then
  os.exit(1)
end
