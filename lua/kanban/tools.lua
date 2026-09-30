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
  local task, err = store:get_many(input.ids)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_create(input)
  local task, err = store:create_many(input.tasks)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_update(input)
  local task, err = store:update_many(input.tasks)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_delete(input)
  local task, err = store:delete_many(input.ids)
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
    description = "Read kanban tasks by ids. Read-only, all-or-nothing. "
      .. "Use a one-item array for a single task. Returns an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = { ids = { type = "array", items = ID, minItems = 1 } },
      required = { "ids" },
    },
    handler = task_get,
  })

  maki.api.register_tool({
    name = "task_create",
    description = "Create kanban tasks in the todo column. Use a one-item array for a single task. "
      .. "All-or-nothing: validates the whole batch before one atomic write. Returns an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = {
        tasks = {
          type = "array",
          minItems = 1,
          items = {
            type = "object",
            properties = { title = TITLE, description = DESCRIPTION },
            required = { "title" },
          },
        },
      },
      required = { "tasks" },
    },
    handler = task_create,
  })

  maki.api.register_tool({
    name = "task_update",
    description = "Update kanban tasks using an ID-keyed object of non-empty patches. "
      .. "Only the fields you pass are changed. Use one entry for a single task. "
      .. "All-or-nothing: validates the whole batch before one atomic write. Returns an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = {
        tasks = {
          type = "object",
          properties = {},
          minProperties = 1,
          additionalProperties = {
            type = "object",
            properties = { title = TITLE, description = DESCRIPTION, status = STATUS },
            minProperties = 1,
          },
        },
      },
      required = { "tasks" },
    },
    handler = task_update,
  })

  maki.api.register_tool({
    name = "task_delete",
    description = "Delete kanban tasks by ids. Use a one-item array for a single task. "
      .. "All-or-nothing: validates the whole batch before one atomic write. Returns deleted tasks as an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = { ids = { type = "array", items = ID, minItems = 1 } },
      required = { "ids" },
    },
    handler = task_delete,
  })
end

return M
