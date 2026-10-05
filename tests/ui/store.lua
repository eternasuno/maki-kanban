--# selene: allow(undefined_variable, unscoped_variables)
return function(_ENV)
  _ENV.fake = { result = nil, error = nil, update_error = nil, calls = 0, updates = {}, creates = 0, deletes = 0 }
  function fake:update_many(updates)
    self.updates[#self.updates + 1] = updates
    if self.update_error then
      return nil, self.update_error
    end
    local result = {}
    for _, patch in pairs(updates) do
      if patch.title ~= nil and patch.title == "" then
        return nil, "title must not be empty"
      end
    end
    for id, patch in pairs(updates) do
      local source = self.result.tasks[id] or {}
      for key, value in pairs(patch) do
        source[key] = value
      end
      self.result.tasks[id] = source
      result[id] = { id = id, title = source.title, description = source.description, status = source.status }
    end
    return result
  end
  function fake:delete_many(ids)
    self.deletes = (self.deletes or 0) + 1
    self.deleted_ids = ids
    self.deleted_id = ids[1]
    if self.delete_error then
      return nil, self.delete_error
    end
    local result = {}
    for _, id in ipairs(ids) do
      local task = self.result.tasks[id]
      if not task then
        return nil, "task not found: " .. id
      end
      result[id] = { id = id, title = task.title, description = task.description, status = task.status }
    end
    for _, id in ipairs(ids) do
      self.result.tasks[id] = nil
    end
    return result
  end
  function fake:create_many(inputs)
    assert(
      #inputs == 1 and type(inputs[1]) == "table" and next(inputs, 1) == nil,
      "UI create must send one input in an array"
    )
    local input = inputs[1]
    self.creates = (self.creates or 0) + 1
    self.create_inputs = self.create_inputs or {}
    self.create_inputs[#self.create_inputs + 1] = { title = input.title, description = input.description }
    if self.create_error then
      return nil, self.create_error
    end
    if type(input.title) ~= "string" or input.title:match("^%s*$") then
      return nil, "title must not be empty"
    end
    local number = 1
    while self.result.tasks["task-" .. number] do
      number = number + 1
    end
    local id = "task-" .. number
    self.result.tasks[id] = { title = input.title, description = input.description, status = "todo" }
    return { [id] = { id = id, title = input.title, description = input.description, status = "todo" } }
  end
  function fake:list()
    self.calls = self.calls + 1
    if self.error then
      return nil, self.error
    end
    local tasks = {}
    for id, task in pairs((self.result and self.result.tasks) or {}) do
      tasks[#tasks + 1] = { id = id, title = task.title, description = task.description, status = task.status }
    end
    table.sort(tasks, function(a, b)
      local x, y = tonumber(a.id:match("^task%-(%d+)$")), tonumber(b.id:match("^task%-(%d+)$"))
      if x and y then
        return x < y
      end
      return a.id < b.id
    end)
    return tasks
  end
  package.loaded["kanban.store"] = {
    new = function()
      return fake
    end,
  }
end
