local TextInput = require("maki.text_input")
local View = require("kanban.ui.task_view")
local Editor = require("kanban.ui.editor")

local Task = {}
Task.__index = Task

local FIELDS = { "title", "description" }
local STATUSES = { "todo", "doing", "done" }

function Task.new(task, width, height)
  local self = setmetatable({ task = task or {}, width = width, height = height, offset = 0 }, Task)
  self.focused_field = "title"
  self:resize(width, height)
  return self
end

function Task.new_create(width, height)
  local self = Task.new({ title = "", description = "", status = "todo" }, width, height)
  self.creating = true
  return self
end

function Task:resize(width, height)
  View.resize(self, width, height)
end

function Task:_begin(store)
  self.error = nil
  local field = self.focused_field
  if field == "description" then
    return self:_edit_description(store)
  end
  self.editing = field
  if field == "title" then
    self.title_input = TextInput.new()
    self.title_input:insert_text(tostring(self.task.title or ""))
  end
  self:resize(self.width, self.height)
  return true
end

function Task:_finish_edit()
  self.editing, self.title_input = nil, nil
  self.error = nil
  self:resize(self.width, self.height)
end

function Task:_save(store, field, value)
  if self.creating then
    self.task[field] = value
    self:_finish_edit()
    return true
  end
  local updated, err
  if store then
    updated, err = store:update_many({ [self.task.id] = { [field] = value } })
  else
    err = "store unavailable"
  end
  if not updated then
    self.error = tostring(err or "could not update task")
    self:resize(self.width, self.height)
    return true
  end
  self.task = updated[self.task.id]
  self:_finish_edit()
  return "changed"
end

function Task:_edit_description(store)
  local original = tostring(self.task.description or "")
  local seed = self.description_draft or original
  local text, err = Editor.edit(seed)
  if text == nil or err then
    if text ~= nil then
      self.description_draft = text
    end
    self.error = tostring(err)
    return true
  end
  if text == original and self.description_draft == nil then
    self.error = nil
    return true
  end
  if self.creating then
    self.task.description = text
    self.description_draft = nil
    self:resize(self.width, self.height)
    return true
  end
  local updated, update_err
  if store then
    local ok, result, save_err = pcall(store.update_many, store, { [self.task.id] = { description = text } })
    if ok then
      updated, update_err = result and result[self.task.id], save_err
    else
      update_err = result
    end
  else
    update_err = "store unavailable"
  end
  if not updated then
    self.description_draft = text
    self.error = tostring(update_err or "could not update task")
    return true
  end
  self.task, self.description_draft, self.error = updated, nil, nil
  self:resize(self.width, self.height)
  return "changed"
end

function Task:render()
  return View.render(self)
end

function Task:handle_paste(text)
  if self.editing == "title" and self.title_input then
    self.title_input:insert_text(tostring(text or ""):gsub("%s*[\r\n]+%s*", " "))
    View.title(self)
    return true
  end
  return false
end

function Task:handle_key(key, store)
  if self.confirm_delete then
    self.confirm_delete = false
    if key ~= "y" then
      return true
    end
    local deleted, err
    if store then
      deleted, err = store:delete_many({ self.task.id })
    else
      err = "store unavailable"
    end
    if not deleted then
      self.error = tostring(err or "could not delete task")
      return true
    end
    return "deleted"
  end
  if key == "<C-c>" then
    return "quit"
  end
  if self.help_open then
    if key == "?" or key == "<Esc>" then
      self.help_open = false
    end
    return true
  end
  if self.editing == "title" then
    if key == "<Esc>" then
      self:_finish_edit()
      return true
    end
    if key == "<CR>" or key == "<Enter>" then
      return self:_save(store, "title", self.title_input:value())
    end
    local result = self.title_input:handle_key(key)
    if result ~= TextInput.Result.IGNORED then
      View.title(self)
      return true
    end
    return false
  end
  if key == "q" then
    return "quit"
  end
  if key == "<Esc>" then
    return "back"
  end
  if key == "?" then
    self.help_open = true
    return true
  end
  if key == "d" and not self.creating then
    self.confirm_delete, self.error = true, nil
    return true
  end
  if key == "<Tab>" or key == "<S-Tab>" or key == "j" or key == "<Down>" or key == "k" or key == "<Up>" then
    local current = 1
    for i, field in ipairs(FIELDS) do
      if field == self.focused_field then
        current = i
      end
    end
    local forward = key == "<Tab>" or key == "j" or key == "<Down>"
    local next_index = forward and current % #FIELDS + 1 or (current - 2) % #FIELDS + 1
    self.focused_field = FIELDS[next_index]
    return true
  elseif key == "<CR>" or key == "<Enter>" then
    return self:_begin(store)
  elseif self.creating and key == "s" then
    local created, err
    if store then
      created, err = store:create_many({ { title = self.task.title, description = self.task.description } })
    else
      err = "store unavailable"
    end
    if not created then
      self.error = tostring(err or "could not create task")
      return true
    end
    local _, task = next(created)
    self.task, self.creating, self.error = task, false, nil
    self.focused_field, self.offset = "title", 0
    self:resize(self.width, self.height)
    return "created"
  elseif not self.creating and (key == "<" or key == ">") then
    local current = 1
    for i, status in ipairs(STATUSES) do
      if status == self.task.status then
        current = i
      end
    end
    local target = current + (key == "<" and -1 or 1)
    if not STATUSES[target] then
      return true
    end
    return self:_save(store, "status", STATUSES[target])
  end
  if self.creating then
    return false
  end
  local viewport = self.viewport
  local max_offset = math.max(0, #self.description_lines - viewport)
  local next_offset = self.offset
  if key == "J" then
    next_offset = next_offset + 1
  elseif key == "K" then
    next_offset = next_offset - 1
  elseif key == "<PageDown>" then
    next_offset = next_offset + math.max(1, viewport)
  elseif key == "<PageUp>" then
    next_offset = next_offset - math.max(1, viewport)
  elseif key == "g" then
    next_offset = 0
  elseif key == "G" then
    next_offset = max_offset
  else
    return false
  end
  self.offset = math.min(math.max(0, next_offset), max_offset)
  return true
end

return Task
