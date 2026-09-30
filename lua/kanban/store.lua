local STATUSES = { todo = true, doing = true, done = true }

local function is_status(value)
  return type(value) == "string" and STATUSES[value] == true
end

local function check_title(title)
  if type(title) ~= "string" then
    return false, "title must be a string"
  end
  if title:match("^%s*$") then
    return false, "title must not be empty"
  end
  return true
end

local function validate_data(data)
  if type(data) ~= "table" then
    return "store data must be an object"
  end
  local tasks = data.tasks
  if type(tasks) ~= "table" then
    return "store data must have a tasks object"
  end
  if rawget(tasks, 1) ~= nil then
    return "store data tasks must be an object"
  end
  for id, body in pairs(tasks) do
    if type(id) ~= "string" then
      return "task id must be a string"
    end
    if type(body) ~= "table" then
      return "task " .. id .. " must be an object"
    end
    if not check_title(body.title) then
      return "task " .. id .. " has an invalid title"
    end
    if body.description ~= nil and type(body.description) ~= "string" then
      return "task " .. id .. " has an invalid description"
    end
    if not is_status(body.status) then
      return "task " .. id .. " has an invalid status"
    end
  end
  return nil
end

local function public(id, body)
  return {
    id = id,
    title = body.title,
    description = body.description,
    status = body.status,
  }
end

local function next_id(tasks)
  local n = 1
  while tasks["task-" .. n] ~= nil do
    n = n + 1
  end
  return "task-" .. n
end

local function id_number(id)
  return tonumber(id:match("^task%-(%d+)$"))
end

local function by_id(a, b)
  local na, nb = id_number(a), id_number(b)
  if na and nb then
    return na < nb
  end
  return a < b
end

local function read_tasks(path)
  local meta, merr = maki.fs.metadata(path)
  if merr then
    return nil, "could not read store: " .. merr
  end
  if meta == nil then
    return {}, nil
  end

  local text, rerr = maki.fs.read(path)
  if not text then
    return nil, "could not read store: " .. rerr
  end

  local decoded, derr = maki.json.decode(text)
  if not decoded then
    return nil, "invalid kanban store: " .. tostring(derr)
  end

  local verr = validate_data(decoded)
  if verr then
    return nil, "invalid kanban store: " .. verr
  end

  local tasks = {}
  for id, body in pairs(decoded.tasks) do
    tasks[id] = {
      title = body.title,
      description = body.description or "",
      status = body.status,
    }
  end
  return tasks, nil
end

local function write_tasks(path, dir, tasks)
  local verr = validate_data({ tasks = tasks })
  if verr then
    return nil, verr
  end

  local encoded, eerr = maki.json.encode({ tasks = tasks })
  if not encoded then
    return nil, "could not encode store: " .. tostring(eerr)
  end

  if dir and dir ~= "" then
    local mok, mkerr = maki.fs.mkdir(dir, { parents = true })
    if not mok then
      return nil, "could not create store directory: " .. mkerr
    end
  end

  local wok, werr = maki.fs.atomic_write(path, encoded)
  if not wok then
    return nil, "could not write store: " .. werr
  end
  return true
end

local Store = {}
Store.__index = Store

function Store.new(path)
  if path == nil then
    local cwd = maki.uv.cwd()
    if cwd then
      path = maki.fs.joinpath(cwd, ".maki", "kanban.json")
    else
      path = maki.fs.joinpath(".maki", "kanban.json")
    end
  end
  return setmetatable({
    path = path,
    dir = maki.fs.dirname(path),
  }, Store)
end

function Store:load()
  local tasks, err = read_tasks(self.path)
  if not tasks then
    return nil, err
  end
  return { tasks = tasks }
end

function Store:save()
  local tasks, err = read_tasks(self.path)
  if not tasks then
    return nil, err
  end
  return write_tasks(self.path, self.dir, tasks)
end

function Store:get(id)
  if type(id) ~= "string" then
    return nil, "id must be a string"
  end
  local tasks, err = read_tasks(self.path)
  if not tasks then
    return nil, err
  end
  local body = tasks[id]
  if not body then
    return nil, "task not found: " .. id
  end
  return public(id, body)
end

function Store:list()
  local tasks, err = read_tasks(self.path)
  if not tasks then
    return nil, err
  end
  local ids = {}
  for id in pairs(tasks) do
    ids[#ids + 1] = id
  end
  table.sort(ids, by_id)
  local out = {}
  for i, id in ipairs(ids) do
    out[i] = public(id, tasks[id])
  end
  return out
end

function Store:create(input)
  if input == nil then
    input = {}
  end
  if type(input) ~= "table" then
    return nil, "task must be an object"
  end

  local ok, terr = check_title(input.title)
  if not ok then
    return nil, terr
  end

  local description = input.description
  if description == nil then
    description = ""
  end
  if type(description) ~= "string" then
    return nil, "description must be a string"
  end

  if input.status ~= nil and input.status ~= "todo" then
    return nil, "invalid status: " .. tostring(input.status)
  end

  local data, err = self:load()
  if not data then
    return nil, err
  end

  local id = next_id(data.tasks)
  local body = {
    title = input.title,
    description = description,
    status = "todo",
  }
  data.tasks[id] = body

  local wok, werr = write_tasks(self.path, self.dir, data.tasks)
  if not wok then
    return nil, werr
  end
  return public(id, body)
end

function Store:update(id, input)
  if type(id) ~= "string" then
    return nil, "id must be a string"
  end
  if input == nil then
    input = {}
  end
  if type(input) ~= "table" then
    return nil, "update must be an object"
  end

  local data, err = self:load()
  if not data then
    return nil, err
  end

  local body = data.tasks[id]
  if not body then
    return nil, "task not found: " .. id
  end

  local updated = {
    title = body.title,
    description = body.description,
    status = body.status,
  }
  local changed = false

  if input.title ~= nil then
    local ok, terr = check_title(input.title)
    if not ok then
      return nil, terr
    end
    updated.title = input.title
    changed = true
  end

  if input.description ~= nil then
    if type(input.description) ~= "string" then
      return nil, "description must be a string"
    end
    updated.description = input.description
    changed = true
  end

  if input.status ~= nil then
    if not is_status(input.status) then
      return nil, "invalid status: " .. tostring(input.status)
    end
    updated.status = input.status
    changed = true
  end

  if not changed then
    return nil, "no fields to update"
  end

  data.tasks[id] = updated

  local wok, werr = write_tasks(self.path, self.dir, data.tasks)
  if not wok then
    return nil, werr
  end
  return public(id, updated)
end

function Store:delete(id)
  if type(id) ~= "string" then
    return nil, "id must be a string"
  end

  local data, err = self:load()
  if not data then
    return nil, err
  end

  local body = data.tasks[id]
  if not body then
    return nil, "task not found: " .. id
  end
  data.tasks[id] = nil

  local wok, werr = write_tasks(self.path, self.dir, data.tasks)
  if not wok then
    return nil, werr
  end
  return public(id, body)
end

return Store
