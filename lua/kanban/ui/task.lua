local TextInput = require("maki.text_input")

local Task = {}
Task.__index = Task

local FIELDS = { "title", "status", "description" }
local STATUSES = { "todo", "doing", "done" }

local function styled(text, color, bold, background)
  return { text, { fg = color, bold = bold, bg = background } }
end

local function fit(text, width)
  if width <= 0 then return "" end
  if maki.ui.display_width(text) > width then text = maki.ui.truncate_text(text, width).head end
  return text .. string.rep(" ", math.max(0, width - maki.ui.display_width(text)))
end

local function split_lines(text)
  local lines = {}
  text = tostring(text or "")
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  return lines
end

local function wrap(text, width)
  local lines = {}
  if width <= 0 then return lines end
  for _, source in ipairs(split_lines(text)) do
    if source == "" then
      lines[#lines + 1] = ""
    else
      while maki.ui.display_width(source) > width do
        local part = maki.ui.truncate_text(source, width).head
        if part == "" then break end
        lines[#lines + 1] = part
        source = source:sub(#part + 1)
      end
      lines[#lines + 1] = source
    end
  end
  return lines
end

local function status_label(status)
  status = tostring(status or ""):lower()
  return status == "todo" and "Todo" or status == "doing" and "Doing" or status == "done" and "Done" or "Todo"
end

local function status_color(status)
  return maki.ui.theme_color(status == "doing" and "warning" or status == "done" and "success" or "accent")
end

function Task.new(task, width, height)
  local self = setmetatable({ task = task or {}, width = width, height = height, offset = 0 }, Task)
  self.focused_field = "title"
  self:resize(width, height)
  return self
end

function Task:resize(width, height)
  self.width, self.height = math.max(0, width or 0), math.max(0, height or 0)
  local inner = math.max(0, self.width - 2)
  local title_text = self.title_input and self.title_input:value() or self.task.title or ""
  local title = wrap(title_text, inner)
  while #title < 2 do title[#title + 1] = "" end
  if #title > 2 and inner > 0 then
    local head = maki.ui.truncate_text(title[2], math.max(0, inner - 1)).head
    title[2] = head .. "…"
  end
  self.title_lines = { title[1], title[2] }
  local status = self.status_draft or tostring(self.task.status or "todo"):lower()
  self.status_text = status_label(status)
  self.status_color = status_color(status)
  self.description_lines = wrap(self.task.description or "", inner)
  if #self.description_lines == 0 then self.description_lines = { "" } end
  local viewport = math.max(0, self.height - 8)
  self.offset = math.min(math.max(0, self.offset), math.max(0, #self.description_lines - viewport))
end

function Task:_begin(store)
  self.error = nil
  local field = self.focused_field
  if field == "description" then return self:_edit_description(store) end
  self.editing = field
  if field == "title" then
    self.title_input = TextInput.new()
    self.title_input:insert_text(tostring(self.task.title or ""))
  else
    local current = tostring(self.task.status or "todo"):lower()
    self.status_index = 1
    for i, value in ipairs(STATUSES) do if value == current then self.status_index = i end end
    self.status_draft = STATUSES[self.status_index]
  end
  self:resize(self.width, self.height)
  return true
end

function Task:_finish_edit()
  self.editing, self.title_input, self.title_draft, self.status_draft, self.status_index = nil, nil, nil, nil, nil
  self.error = nil
  self:resize(self.width, self.height)
end

function Task:_save(store, field, value)
  local updated, err
  if store then updated, err = store:update(self.task.id, { [field] = value }) else err = "store unavailable" end
  if not updated then
    self.error = tostring(err or "could not update task")
    self:resize(self.width, self.height)
    return true
  end
  self.task = updated
  self:_finish_edit()
  return "changed"
end

function Task:_edit_description(store)
  local path
  if os and type(os.tmpname) == "function" then
    local ok, result = pcall(os.tmpname)
    if ok then path = result end
  end
  if not path then
    local dir = maki.env.state_dir()
    for _ = 1, 10 do
      local candidate = maki.fs.joinpath(dir, string.format("kanban-description-%08x-%08x.md", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff)))
      local meta, err = maki.fs.metadata(candidate)
      if not meta and not err then path = candidate; break end
    end
  end
  if not path then self.error = "temporary file path unavailable"; return true end
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
      if store then updated, update_err = store:update(self.task.id, { description = text }) else update_err = "store unavailable" end
      if updated then
        self.task = updated
        changed = true
      else
        self.error = tostring(update_err or "could not update task")
      end
    end
  end
  maki.fs.rm(path)
  self:resize(self.width, self.height)
  return changed and "changed" or true
end

function Task:render()
  local lines = {}
  if self.height <= 0 then return lines end
  local width, height = self.width, self.height
  local inner = math.max(0, width - 2)
  local accent = maki.ui.theme_color("accent")
  local selection = maki.ui.theme_style("item_selected") or {}
  local focus_bg = selection.bg or accent
  local focus_fg = selection.fg or maki.ui.theme_color("background")
  for row = 1, height do
    if width < 2 then
      lines[row] = string.rep(" ", width)
    elseif row == 1 then
      lines[row] = { styled("┌" .. string.rep("─", math.max(0, width - 2)) .. "┐", accent) }
    elseif row == height then
      lines[row] = { styled("└" .. string.rep("─", inner) .. "┘", accent) }
    elseif row == height - 1 then
      local footer_text = self.editing == "title" and "Enter Save   Esc Cancel" or self.editing == "status" and "←/→ Change   Enter Save   Esc Cancel" or "Enter Edit   b Back"
      local footer = maki.ui.truncate_text(footer_text, inner).head
      local label = string.rep(" ", math.max(0, inner - maki.ui.display_width(footer))) .. footer
      lines[row] = { styled("│", accent), styled(label), styled("│", accent) }
    elseif row == height - 2 and self.error then
      lines[row] = { styled("│", accent), styled(fit(tostring(self.error), inner), maki.ui.theme_color("error")), styled("│", accent) }
    else
      local content_row = row - 1
      local spans = { styled("│", accent) }
      if content_row <= 2 then
        local focused = self.focused_field == "title"
        spans[#spans + 1] = styled(fit(self.title_lines[content_row] or "", inner), focused and focus_fg or maki.ui.theme_color("foreground"), focused, focused and focus_bg)
      elseif content_row == 3 then
        spans = { styled("├" .. string.rep("─", inner) .. "┤", accent) }
      elseif content_row == 4 then
        local focused = self.focused_field == "status"
        spans[#spans + 1] = styled(fit(self.status_text, inner), focused and focus_fg or self.status_color, true, focused and focus_bg)
      elseif content_row == 5 then
        spans[#spans + 1] = styled(string.rep(" ", inner))
      else
        local focused = self.focused_field == "description"
        local description = self.description_lines[self.offset + content_row - 5]
        spans[#spans + 1] = styled(fit(description or "", inner), focused and focus_fg or maki.ui.theme_color("foreground"), focused, focused and focus_bg)
      end
      if content_row ~= 3 then spans[#spans + 1] = styled("│", accent) end
      lines[row] = spans
    end
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
  if self.editing == "title" then
    if key == "<Esc>" then self:_finish_edit(); return true end
    if key == "<CR>" or key == "<Enter>" then return self:_save(store, "title", self.title_input:value()) end
    local result = self.title_input:handle_key(key)
    if result ~= TextInput.Result.IGNORED then self.title_draft = self.title_input:value(); self:resize(self.width, self.height); return true end
    return false
  elseif self.editing == "status" then
    if key == "<Esc>" then self:_finish_edit(); return true end
    if key == "<CR>" or key == "<Enter>" then return self:_save(store, "status", STATUSES[self.status_index]) end
    if key == "h" or key == "<Left>" then self.status_index = (self.status_index - 2) % #STATUSES + 1
    elseif key == "l" or key == "<Right>" then self.status_index = self.status_index % #STATUSES + 1
    else return false end
    self.status_draft = STATUSES[self.status_index]; self:resize(self.width, self.height); return true
  end
  if key == "<Tab>" or key == "<S-Tab>" then
    local current = 1
    for i, field in ipairs(FIELDS) do if field == self.focused_field then current = i end end
    local next_index = key == "<Tab>" and current % #FIELDS + 1 or (current - 2) % #FIELDS + 1
    self.focused_field = FIELDS[next_index]
    return true
  elseif key == "<CR>" or key == "<Enter>" then
    return self:_begin(store)
  elseif key == "b" then return "back"
  end
  local viewport = math.max(0, self.height - 8)
  local max_offset = math.max(0, #self.description_lines - viewport)
  local next_offset = self.offset
  if key == "j" or key == "<Down>" then next_offset = next_offset + 1
  elseif key == "k" or key == "<Up>" then next_offset = next_offset - 1
  elseif key == "<PageDown>" then next_offset = next_offset + math.max(1, viewport)
  elseif key == "<PageUp>" then next_offset = next_offset - math.max(1, viewport)
  elseif key == "g" then next_offset = 0
  elseif key == "G" then next_offset = max_offset
  else return false end
  next_offset = math.min(math.max(0, next_offset), max_offset)
  if next_offset == self.offset then return false end
  self.offset = next_offset
  return true
end

return Task
