local TextInput = require("maki.text_input")
local Board = require("kanban.ui.board")

local Task = {}
Task.__index = Task

local FIELDS = { "title", "description" }
local STATUSES = { "todo", "doing", "done" }
local CREATE_FIELDS = { "title", "description" }
local FOOTER_HEIGHT = 3
local FOOTER_GAP = 1
local PANE_BORDERS = 2
local TITLE_HEIGHT = 2
local FIELD_GAP = 1
local DESCRIPTION_LABEL_HEIGHT = 1
local DETAIL_HELP = {
  "Navigation",
  "  j / k       field",
  "  Tab / S-Tab field",
  "  J / K       scroll description",
  "  g / G       top / bottom",
  "",
  "Actions",
  "  Enter       edit field",
  "  < / >       change status",
  "  d           delete",
  "",
  "  Esc         back",
  "  q           quit",
  "  Ctrl-C      quit",
  "  ? / Esc     close help",
}
local CREATE_HELP = {
  "Navigation",
  "  j / k       field",
  "  Tab / S-Tab field",
  "",
  "Actions",
  "  Enter       edit field",
  "  s           create task",
  "",
  "  Esc         back",
  "  q           quit",
  "  Ctrl-C      quit",
  "  ? / Esc     close help",
}

local function styled(text, color, bold, background)
  return { text, { fg = color, bold = bold, bg = background } }
end

local function fit(text, width)
  if width <= 0 then
    return ""
  end
  if maki.ui.display_width(text) > width then
    text = maki.ui.truncate_text(text, width).head
  end
  return text .. string.rep(" ", math.max(0, width - maki.ui.display_width(text)))
end

local function split_lines(text)
  local lines = {}
  text = tostring(text or "")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function wrap(text, width)
  local lines = {}
  if width <= 0 then
    return lines
  end
  for _, source in ipairs(split_lines(text)) do
    if source == "" then
      lines[#lines + 1] = ""
    else
      while maki.ui.display_width(source) > width do
        local part = maki.ui.truncate_text(source, width).head
        if part == "" then
          break
        end
        lines[#lines + 1] = part
        source = source:sub(#part + 1)
      end
      lines[#lines + 1] = source
    end
  end
  return lines
end

local function wrap_input(input, width)
  local lines, cursor_row = { {} }, 1
  if width <= 0 then
    return lines, cursor_row
  end
  local used = 0
  for _, source in ipairs(input:render("", 0).lines) do
    for _, span in ipairs(source) do
      local remaining = span[1]
      while remaining ~= "" do
        local part = maki.ui.truncate_text(remaining, width - used)
        if part.head ~= "" then
          local line = lines[#lines]
          line[#line + 1] = { part.head, span[2] }
          if span[2] == "cursor" then
            cursor_row = #lines
          end
          used = used + maki.ui.display_width(part.head)
          remaining = part.tail
        elseif used > 0 then
          lines[#lines + 1], used = {}, 0
        else
          local char = remaining:match("^.[\128-\191]*")
          if span[2] == "cursor" then
            local line = lines[#lines]
            line[#line + 1] = { " ", "cursor" }
            cursor_row, used = #lines, 1
          end
          remaining = remaining:sub(#char + 1)
        end
      end
    end
  end
  return lines, cursor_row
end

local function status_color(status)
  return (maki.ui.theme_style(status == "doing" and "warning" or status == "done" and "success" or "accent") or {}).fg
end

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
  self.width, self.height = math.max(0, width or 0), math.max(0, height or 0)
  self.footer_height = math.min(FOOTER_HEIGHT, self.height)
  self.footer_gap = self.height >= FOOTER_HEIGHT + FOOTER_GAP + PANE_BORDERS and FOOTER_GAP or 0
  self.pane_height = self.height - self.footer_height - self.footer_gap
  self.viewport = math.max(0, self.pane_height - PANE_BORDERS - TITLE_HEIGHT - FIELD_GAP - DESCRIPTION_LABEL_HEIGHT)
  local inner = math.max(0, self.width - 2 - maki.ui.display_width("▸ "))
  if self.title_input then
    local title, cursor_row = wrap_input(self.title_input, inner)
    local visible = math.max(1, math.min(TITLE_HEIGHT, self.pane_height - PANE_BORDERS))
    local offset = math.min(self.title_offset or 0, math.max(0, #title - visible))
    offset = math.max(math.min(offset, cursor_row - 1), cursor_row - visible)
    self.title_offset = offset
    self.title_lines = { title[offset + 1] or {}, title[offset + 2] or {} }
  else
    local title = wrap(self.task.title or "", inner)
    while #title < 2 do
      title[#title + 1] = ""
    end
    if #title > 2 and inner > 0 then
      local head = maki.ui.truncate_text(title[2], math.max(0, inner - 1)).head
      title[2] = head .. "…"
    end
    self.title_offset = 0
    self.title_lines = { title[1], title[2] }
  end
  self.status_color = status_color(self.creating and "todo" or self.task.status)
  self.description_lines = wrap(self.task.description or "", inner)
  if #self.description_lines == 0 then
    self.description_lines = { "" }
  end
  self.offset = math.min(math.max(0, self.offset), math.max(0, #self.description_lines - self.viewport))
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
  self.editing, self.title_input, self.title_draft = nil, nil, nil
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
  local path
  if os and type(os.tmpname) == "function" then
    local ok, result = pcall(os.tmpname)
    if ok then
      path = result
    end
  end
  if not path then
    local dir = maki.env.state_dir()
    for _ = 1, 10 do
      local candidate = maki.fs.joinpath(
        dir,
        string.format("kanban-description-%08x-%08x.md", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
      )
      local meta, err = maki.fs.metadata(candidate)
      if not meta and not err then
        path = candidate
        break
      end
    end
  end
  if not path then
    self.error = "temporary file path unavailable"
    return true
  end
  local original = tostring(self.task.description or "")
  local ok, err = maki.fs.write(path, original)
  if not ok then
    self.error = tostring(err or "could not write temporary file")
    maki.fs.rm(path)
    return true
  end
  local exit_code = maki.ui.open_editor(path)
  local changed = false
  if exit_code == 0 then
    local text, read_err = maki.fs.read(path)
    if not text then
      self.error = tostring(read_err or "could not read temporary file")
    elseif text ~= original then
      local updated, update_err
      if self.creating then
        self.task.description = text
        updated = self.task
      elseif store then
        local results
        results, update_err = store:update_many({ [self.task.id] = { description = text } })
        updated = results and results[self.task.id]
      else
        update_err = "store unavailable"
      end
      if updated then
        self.task = updated
        changed = true
      else
        self.error = tostring(update_err or "could not update task")
      end
    end
  else
    self.error = "editor exited with status " .. tostring(exit_code)
  end
  maki.fs.rm(path)
  self:resize(self.width, self.height)
  return changed and not self.creating and "changed" or true
end

function Task:render()
  local lines = {}
  local width, height = self.width, self.height
  if height <= 0 then
    return lines
  end
  local inner = math.max(0, width - 2)
  local foreground = maki.ui.theme_color("foreground")
  local marker_width = maki.ui.display_width("▸ ")
  local border = self.status_color
  local function pane_line(content, focused, marked)
    local marker = marked and focused and "▸ " or string.rep(" ", marker_width)
    if type(content) == "string" then
      return { styled("│", border), styled(fit(marker .. content, inner), foreground, focused), styled("│", border) }
    end
    local spans = { styled("│", border) }
    marker = maki.ui.truncate_text(marker, inner).head
    local marker_color = foreground
    if self.editing == "title" and focused and marked then
      marker_color = (maki.ui.theme_style("accent") or {}).fg or foreground
    end
    spans[#spans + 1] = styled(marker, marker_color, focused)
    local used = maki.ui.display_width(marker)
    for _, span in ipairs(content) do
      spans[#spans + 1] = span[2] == "" and styled(span[1], foreground, focused) or span
      used = used + maki.ui.display_width(span[1])
    end
    spans[#spans + 1] = styled(string.rep(" ", math.max(0, inner - used)), foreground, focused)
    spans[#spans + 1] = styled("│", border)
    return spans
  end
  for row = 1, self.pane_height do
    if width < 2 or self.pane_height < 2 then
      lines[#lines + 1] = string.rep(" ", width)
    elseif row == 1 then
      local title = maki.ui.truncate_text(self.creating and "─ Create " or "─ Task ", inner).head
      lines[#lines + 1] =
        { styled("┌" .. title .. string.rep("─", inner - maki.ui.display_width(title)) .. "┐", border) }
    elseif row == self.pane_height then
      lines[#lines + 1] = { styled("└" .. string.rep("─", inner) .. "┘", border) }
    else
      local content_row = row - 1
      if content_row <= TITLE_HEIGHT then
        local content = self.title_lines[content_row] or ""
        if self.creating and content_row == 1 and content == "" then
          content = "Title"
        end
        lines[#lines + 1] = pane_line(content, self.focused_field == "title", content_row == 1)
      elseif content_row <= TITLE_HEIGHT + FIELD_GAP then
        lines[#lines + 1] = pane_line("", false, false)
      elseif content_row == TITLE_HEIGHT + FIELD_GAP + DESCRIPTION_LABEL_HEIGHT then
        lines[#lines + 1] = pane_line("Description", self.focused_field == "description", true)
      else
        local index = self.offset + content_row - TITLE_HEIGHT - FIELD_GAP - DESCRIPTION_LABEL_HEIGHT
        lines[#lines + 1] = pane_line(self.description_lines[index] or "", false, false)
      end
    end
  end
  for _ = 1, self.footer_gap do
    lines[#lines + 1] = string.rep(" ", width)
  end
  local message, hint, color, bold
  color, bold = foreground, false
  if self.confirm_delete then
    message = 'Delete "' .. tostring(self.task.title or "") .. '"?  y/N'
    color, bold = (maki.ui.theme_style("error") or {}).fg, true
  elseif self.error then
    message = "Error: " .. tostring(self.error)
    color, bold = (maki.ui.theme_style("error") or {}).fg, true
  elseif self.editing == "title" then
    message, hint = "EDIT TITLE", self.creating and "Enter done   Esc cancel" or "Enter save   Esc cancel"
  elseif self.creating then
    message, hint = "CREATE", "? help   s create   Esc back"
  else
    message, hint = "NORMAL", "? help   Esc back   q quit"
  end
  if hint then
    message = message
      .. string.rep(" ", math.max(1, inner - 2 - maki.ui.display_width(message) - maki.ui.display_width(hint)))
      .. hint
  end
  for row = 1, self.footer_height do
    if width < 2 or self.footer_height < FOOTER_HEIGHT then
      lines[#lines + 1] = { styled(fit(message, width), color, bold) }
    elseif row == 1 then
      lines[#lines + 1] = { styled("┌" .. string.rep("─", inner) .. "┐", foreground) }
    elseif row == self.footer_height then
      lines[#lines + 1] = { styled("└" .. string.rep("─", inner) .. "┘", foreground) }
    else
      lines[#lines + 1] =
        { styled("│", foreground), styled(fit(" " .. message, inner), color, bold), styled("│", foreground) }
    end
  end
  if self.help_open and not self.confirm_delete then
    Board.help_overlay(self, lines, self.creating and CREATE_HELP or DETAIL_HELP)
  end
  return lines
end

function Task:handle_paste(text)
  if self.editing == "title" and self.title_input then
    self.title_input:insert_text(tostring(text or ""):gsub("%s*[\r\n]+%s*", " "))
    self.title_draft = self.title_input:value()
    self:resize(self.width, self.height)
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
      self.title_draft = self.title_input:value()
      self:resize(self.width, self.height)
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
    local fields = self.creating and CREATE_FIELDS or FIELDS
    local current = 1
    for i, field in ipairs(fields) do
      if field == self.focused_field then
        current = i
      end
    end
    local forward = key == "<Tab>" or key == "j" or key == "<Down>"
    local next_index = forward and current % #fields + 1 or (current - 2) % #fields + 1
    self.focused_field = fields[next_index]
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
