local Store = require("kanban.store")

local store = Store.new()

local EMPTY_LIST = maki.json.decode("[]")

local M = {}

local function failure(err)
  return { llm_output = "error: " .. tostring(err), is_error = true }
end

local function verify_write_path(input)
  if input.path ~= store.path then
    return failure("write path must match the kanban store path")
  end
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
  local path_error = verify_write_path(input)
  if path_error then
    return path_error
  end
  local task, err = store:create_many(input.tasks)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_update(input)
  local path_error = verify_write_path(input)
  if path_error then
    return path_error
  end
  local task, err = store:update_many(input.tasks)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local function task_delete(input)
  local path_error = verify_write_path(input)
  if path_error then
    return path_error
  end
  local task, err = store:delete_many(input.ids)
  if not task then
    return failure(err)
  end
  return json_output(task)
end

local ID = { type = "string", description = "Task id from task_list or task_create." }
local TITLE = { type = "string", description = "Short task title." }
local DESCRIPTION = { type = "string", description = "Longer task details." }

function M.register()
  maki.api.register_tool({
    name = "task_list",
    description = "List all kanban tasks. Read-only. Returns a JSON array of tasks.",
    schema = { type = "object", properties = {} },
    permission = "fs_read",
    permission_scopes = function()
      return { scopes = { store.path }, force_prompt = false }
    end,
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
    permission = "fs_read",
    permission_scopes = function()
      return { scopes = { store.path }, force_prompt = false }
    end,
    handler = task_get,
  })

  maki.api.register_tool({
    name = "task_create",
    description = "Create kanban tasks in the todo column. Use a one-item array for a single task. "
      .. "All-or-nothing: validates the whole batch before one atomic write. Returns an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = {
        path = { type = "string", enum = { store.path } },
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
      required = { "path", "tasks" },
    },
    permission = "fs_write",
    permission_scopes = "path",
    mutable_path = "path",
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
        path = { type = "string", enum = { store.path } },
        tasks = {
          description = "Non-empty object keyed by task ID. Each value is a non-empty patch with optional "
            .. "title (nonblank string), description (string), and status (todo, doing, or done). "
            .. 'For example: {"task-1": {"status": "doing"}}. Validated by the task store.',
        },
      },
      required = { "path", "tasks" },
    },
    permission = "fs_write",
    permission_scopes = "path",
    mutable_path = "path",
    handler = task_update,
  })

  maki.api.register_tool({
    name = "task_delete",
    description = "Delete kanban tasks by ids. Use a one-item array for a single task. "
      .. "All-or-nothing: validates the whole batch before one atomic write. Returns deleted tasks as an ID-keyed JSON object.",
    schema = {
      type = "object",
      properties = {
        path = { type = "string", enum = { store.path } },
        ids = { type = "array", items = ID, minItems = 1 },
      },
      required = { "path", "ids" },
    },
    permission = "fs_write",
    permission_scopes = "path",
    mutable_path = "path",
    handler = task_delete,
  })
end

return M
