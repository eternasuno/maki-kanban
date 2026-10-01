local STATUSES = {}
for _, status in ipairs(require("kanban.status")) do
  STATUSES[status] = true
end

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

local function id_number(id)
  return tonumber(id:match("^task%-(%d+)$"))
end

local function by_id(a, b)
  local na, nb = id_number(a), id_number(b)
  if na and nb then
    if na ~= nb then
      return na < nb
    end
  elseif na then
    return true
  elseif nb then
    return false
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

local function check_array(value, name)
  if type(value) ~= "table" then
    return nil, name .. " must be a non-empty array"
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return nil, name .. " must be a non-empty array"
    end
    count = count + 1
  end
  if count == 0 then
    return nil, name .. " must be a non-empty array"
  end
  for i = 1, count do
    if rawget(value, i) == nil then
      return nil, name .. " must be a non-empty array"
    end
  end
  return true
end

local function check_object(value, name)
  if type(value) ~= "table" then
    return nil, name .. " must be an object"
  end
  for key in pairs(value) do
    if type(key) ~= "string" then
      return nil, name .. " must be an object with string keys"
    end
  end
  return true
end

local function check_ids(ids)
  local ok, err = check_array(ids, "ids")
  if not ok then
    return nil, err
  end
  local seen = {}
  for _, id in ipairs(ids) do
    if type(id) ~= "string" then
      return nil, "id must be a string"
    end
    if seen[id] then
      return nil, "duplicate id: " .. id
    end
    seen[id] = true
  end
  return true
end

local function select_tasks(tasks, ids)
  local out = {}
  for _, id in ipairs(ids) do
    if not tasks[id] then
      return nil, "task not found: " .. id
    end
    out[id] = public(id, tasks[id])
  end
  return out
end

function Store:get_many(ids)
  local ok, err = check_ids(ids)
  if not ok then
    return nil, err
  end
  local tasks, rerr = read_tasks(self.path)
  if not tasks then
    return nil, rerr
  end
  return select_tasks(tasks, ids)
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

function Store:create_many(inputs)
  local ok, err = check_array(inputs, "tasks")
  if not ok then
    return nil, err
  end
  local bodies = {}
  for i, input in ipairs(inputs) do
    local object_ok, object_err = check_object(input, "task")
    if not object_ok then
      return nil, object_err
    end
    local title_ok, title_err = check_title(input.title)
    if not title_ok then
      return nil, title_err
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
    bodies[i] = { title = input.title, description = description, status = "todo" }
  end

  local tasks, rerr = read_tasks(self.path)
  if not tasks then
    return nil, rerr
  end
  local out = {}
  local candidate = 1
  for _, body in ipairs(bodies) do
    local id = "task-" .. candidate
    while tasks[id] ~= nil do
      candidate = candidate + 1
      id = "task-" .. candidate
    end
    tasks[id] = body
    out[id] = public(id, body)
    candidate = candidate + 1
  end
  local wok, werr = write_tasks(self.path, self.dir, tasks)
  if not wok then
    return nil, werr
  end
  return out
end

function Store:update_many(updates)
  local ok, err = check_object(updates, "updates")
  if not ok then
    return nil, err
  end
  if next(updates) == nil then
    return nil, "updates must not be empty"
  end
  local tasks, rerr = read_tasks(self.path)
  if not tasks then
    return nil, rerr
  end
  for id, patch in pairs(updates) do
    if not tasks[id] then
      return nil, "task not found: " .. id
    end
    local object_ok, object_err = check_object(patch, "update")
    if not object_ok then
      return nil, object_err
    end
    if next(patch) == nil then
      return nil, "no fields to update"
    end
    for field in pairs(patch) do
      if field ~= "title" and field ~= "description" and field ~= "status" then
        return nil, "unknown update field: " .. field
      end
    end
    if patch.title ~= nil then
      local title_ok, title_err = check_title(patch.title)
      if not title_ok then
        return nil, title_err
      end
    end
    if patch.description ~= nil and type(patch.description) ~= "string" then
      return nil, "description must be a string"
    end
    if patch.status ~= nil and not is_status(patch.status) then
      return nil, "invalid status: " .. tostring(patch.status)
    end
  end

  local out = {}
  for id, patch in pairs(updates) do
    local body = tasks[id]
    for field, value in pairs(patch) do
      body[field] = value
    end
    out[id] = public(id, body)
  end
  local wok, werr = write_tasks(self.path, self.dir, tasks)
  if not wok then
    return nil, werr
  end
  return out
end

function Store:delete_many(ids)
  local ok, err = check_ids(ids)
  if not ok then
    return nil, err
  end
  local tasks, rerr = read_tasks(self.path)
  if not tasks then
    return nil, rerr
  end
  local out, serr = select_tasks(tasks, ids)
  if not out then
    return nil, serr
  end
  for _, id in ipairs(ids) do
    tasks[id] = nil
  end
  local wok, werr = write_tasks(self.path, self.dir, tasks)
  if not wok then
    return nil, werr
  end
  return out
end

return Store
