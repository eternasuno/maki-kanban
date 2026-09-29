local Task = {}
Task.__index = Task

local function styled(text, color, bold)
  return { text, { fg = color, bold = bold } }
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

function Task.new(task, width, height)
  local self = setmetatable({ task = task or {}, width = width, height = height, offset = 0 }, Task)
  self:resize(width, height)
  return self
end

function Task:resize(width, height)
  self.width, self.height = math.max(0, width or 0), math.max(0, height or 0)
  local inner = math.max(0, self.width - 2)
  local title = wrap(self.task.title or "", inner)
  while #title < 2 do title[#title + 1] = "" end
  if #title > 2 and inner > 0 then
    local head = maki.ui.truncate_text(title[2], math.max(0, inner - 1)).head
    title[2] = head .. "…"
  end
  self.title_lines = { title[1], title[2] }
  local status = tostring(self.task.status or ""):lower()
  self.status_text = status == "todo" and "Todo" or status == "doing" and "Doing" or status == "done" and "Done" or "Todo"
  self.status_color = maki.ui.theme_color(status == "doing" and "warning" or status == "done" and "success" or "accent")
  self.description_lines = wrap(self.task.description or "", inner)
  if #self.description_lines == 0 then self.description_lines = { "" } end
  local viewport = math.max(0, self.height - 8)
  self.offset = math.min(math.max(0, self.offset), math.max(0, #self.description_lines - viewport))
end

function Task:render()
  local lines = {}
  if self.height <= 0 then return lines end
  local width, height = self.width, self.height
  local inner = math.max(0, width - 2)
  local accent = maki.ui.theme_color("accent")
  for row = 1, height do
    if width < 2 then
      lines[row] = string.rep(" ", width)
    elseif row == 1 then
      lines[row] = { styled("┌" .. string.rep("─", math.max(0, width - 2)) .. "┐", accent) }
    elseif row == height then
      lines[row] = { styled("└" .. string.rep("─", inner) .. "┘", accent) }
    elseif row == height - 1 then
      local footer = maki.ui.truncate_text("b Back", inner).head
      local label = string.rep(" ", inner - maki.ui.display_width(footer)) .. footer
      lines[row] = { styled("│", accent), styled(label), styled("│", accent) }
    else
      local content_row = row - 1
      local spans = { styled("│", accent) }
      if content_row <= 2 then
        spans[#spans + 1] = styled(fit(self.title_lines[content_row] or "", inner), maki.ui.theme_color("foreground"))
      elseif content_row == 3 then
        spans = { styled("├" .. string.rep("─", inner) .. "┤", accent) }
      elseif content_row == 4 then
        spans[#spans + 1] = styled(fit(self.status_text, inner), self.status_color, true)
      elseif content_row == 5 then
        spans[#spans + 1] = styled(string.rep(" ", inner))
      else
        local description = self.description_lines[self.offset + content_row - 5]
        spans[#spans + 1] = styled(fit(description or "", inner), maki.ui.theme_color("foreground"))
      end
      if content_row ~= 3 then spans[#spans + 1] = styled("│", accent) end
      lines[row] = spans
    end
  end
  return lines
end

function Task:handle_key(key)
  if key == "b" then return "back" end
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
