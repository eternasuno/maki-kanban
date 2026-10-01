local Display = require("kanban.ui.display")
local Text = require("kanban.ui.text")
local fit, styled = Display.fit, Display.styled

local View = {}

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

local function status_color(status)
  return (maki.ui.theme_style(status == "doing" and "warning" or status == "done" and "success" or "accent") or {}).fg
end

local function layout(self, width, height)
  self.width, self.height = math.max(0, width or 0), math.max(0, height or 0)
  self.footer_height = math.min(FOOTER_HEIGHT, self.height)
  self.footer_gap = self.height >= FOOTER_HEIGHT + FOOTER_GAP + PANE_BORDERS and FOOTER_GAP or 0
  self.pane_height = self.height - self.footer_height - self.footer_gap
  self.viewport = math.max(0, self.pane_height - PANE_BORDERS - TITLE_HEIGHT - FIELD_GAP - DESCRIPTION_LABEL_HEIGHT)
end

function View.title(self)
  local inner = math.max(0, self.width - 2 - maki.ui.display_width("▸ "))
  if self.title_input then
    local title, cursor_row = Text.wrap_input(self.title_input, inner)
    local visible = math.max(1, math.min(TITLE_HEIGHT, self.pane_height - PANE_BORDERS))
    local offset = math.min(self.title_offset or 0, math.max(0, #title - visible))
    offset = math.max(math.min(offset, cursor_row - 1), cursor_row - visible)
    self.title_offset = offset
    self.title_lines = { title[offset + 1] or {}, title[offset + 2] or {} }
  else
    local title = Text.wrap(self.task.title, inner)
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
end

local function description(self)
  local inner = math.max(0, self.width - 2 - maki.ui.display_width("▸ "))
  local content = self.task.description
  if self.description_content == content and self.description_width == inner then
    return
  end
  self.description_content, self.description_width = content, inner
  self.description_lines = Text.wrap(content, inner)
  if #self.description_lines == 0 then
    self.description_lines = { "" }
  end
end

local function viewport(self)
  self.offset = math.min(math.max(0, self.offset), math.max(0, #self.description_lines - self.viewport))
end

function View.resize(self, width, height)
  layout(self, width, height)
  View.title(self)
  self.status_color = status_color(self.creating and "todo" or self.task.status)
  description(self)
  viewport(self)
end

function View.render(self)
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
    message = 'Delete "' .. self.task.title .. '"?  y/N'
    color, bold = (maki.ui.theme_style("error") or {}).fg, true
  elseif self.error or self.cleanup_error then
    message = "Error: " .. tostring(self.error or self.cleanup_error)
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
    Display.help_overlay(self, lines, self.creating and CREATE_HELP or DETAIL_HELP)
  end
  return lines
end

return View
