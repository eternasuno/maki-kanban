local Store = require("kanban.store")

local store = Store.new()

local STATUSES = { "todo", "doing", "done" }

local EMPTY_LIST = maki.json.decode("[]")

local M = {}

local function failure(err)
  return { llm_output = "error: " .. tostring(err), is_error = true }
end

local function json_output(value)
  local text, err = maki.json.encode(value)
  if not text then
    return failure("could not encode json: " .. tostring(err))
  end
  return { llm_output = text }
end

local function task_list()
  local tasks, err = store:list()
  if not tasks then
    return failure(err)
  end
  if #tasks == 0 then
    tasks = EMPTY_LIST
  end
  return json_output(tasks)
end

local function task_get(input)
  local task, err = store:get(input.id)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_create(input)
  local task, err = store:create(input)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_update(input)
  local task, err = store:update(input.id, input)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local ID = { type = "string", description = "Task id from task_list or task_create." }
local TITLE = { type = "string", description = "Short task title." }
local DESCRIPTION = { type = "string", description = "Longer task details." }
local STATUS = { type = "string", enum = STATUSES, description = "Board column." }

function M.register()
  maki.api.register_tool({
    name = "task_list",
    description = "List all kanban tasks. Read-only. Returns a JSON array of tasks.",
    schema = { type = "object", properties = {} },
    handler = task_list,
  })

  maki.api.register_tool({
    name = "task_get",
    description = "Read one kanban task by id. Read-only. Returns the task as JSON.",
    schema = { type = "object", properties = { id = ID }, required = { "id" } },
    handler = task_get,
  })

  maki.api.register_tool({
    name = "task_create",
    description = "Create a kanban task in the todo column. Returns the created task as JSON.",
    schema = {
      type = "object",
      properties = { title = TITLE, description = DESCRIPTION },
      required = { "title" },
    },
    handler = task_create,
  })

  maki.api.register_tool({
    name = "task_update",
    description = "Update a kanban task by id. Only the fields you pass are changed. "
      .. "Returns the updated task as JSON.",
    schema = {
      type = "object",
      properties = { id = ID, title = TITLE, description = DESCRIPTION, status = STATUS },
      required = { "id" },
    },
    handler = task_update,
  })
end

return M
