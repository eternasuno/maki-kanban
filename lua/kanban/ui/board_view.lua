local Display = require("kanban.ui.display")

local BoardView = {}
local fit, styled = Display.fit, Display.styled

local COLUMNS = {}
for i, status in ipairs(require("kanban.status")) do
  COLUMNS[i] = { status = status, title = status:upper() }
end
local COLUMN_COLORS = {
  (maki.ui.theme_style("accent") or {}).fg,
  (maki.ui.theme_style("warning") or {}).fg,
  (maki.ui.theme_style("success") or {}).fg,
}
local HORIZONTAL_PADDING = 2
local VERTICAL_PADDING = 1

local function padding(state)
  local horizontal = state.width >= 8 and HORIZONTAL_PADDING or 0
  local vertical = state.height >= 5 and VERTICAL_PADDING or 0
  return horizontal, vertical
end

local function pane_widths(width, focused)
  if width < 60 then
    return { width }, { focused }
  end
  local usable = width - 2
  local base, extra = math.floor(usable / 3), usable % 3
  local widths = {}
  for i = 1, 3 do
    widths[i] = base + (i <= extra and 1 or 0)
  end
  return widths, { 1, 2, 3 }
end

function BoardView.layout(state)
  local horizontal, vertical = padding(state)
  if state.height < 8 then
    vertical = 0
  end
  local available = state.height - 2 * vertical
  local footer_height = math.min(3, available)
  local gap = available >= 6 and 1 or 0
  local column_height = available - footer_height - gap
  return {
    horizontal = horizontal,
    vertical = vertical,
    column_height = column_height,
    viewport = math.max(0, column_height - 2),
    gap = gap,
    footer_height = footer_height,
  }
end

local HELP = {
  "Navigation",
  "  h / Left    previous column",
  "  l / Right   next column",
  "  j / Down    next task",
  "  k / Up      previous task",
  "  g / G       first / last task",
  "",
  "Actions",
  "  Enter       open task",
  "  Space       mark / unmark task",
  "  < / >       move task(s)",
  "  n           create task",
  "  a           reference task in input",
  "  d           delete task(s)",
  "  r           reload",
  "  q / Esc     close kanban",
  "  Ctrl-C      quit kanban",
  "",
  "  ? / Esc     close help",
}

function BoardView.render(state)
  local layout = BoardView.layout(state)
  local pane_width = state.width - 2 * layout.horizontal
  local lines = {}
  local foreground = maki.ui.theme_color("foreground")
  local function add_line(spans)
    table.insert(spans, 1, styled(string.rep(" ", layout.horizontal)))
    spans[#spans + 1] = styled(string.rep(" ", layout.horizontal))
    lines[#lines + 1] = spans
  end
  local function blank()
    lines[#lines + 1] = string.rep(" ", state.width)
  end
  local function border_color(i)
    return i == state.focused_column and COLUMN_COLORS[i] or foreground
  end
  for _ = 1, layout.vertical do
    blank()
  end
  if pane_width >= 3 and layout.column_height >= 2 then
    local widths, visible = pane_widths(pane_width, state.focused_column)
    local header = {}
    for position, i in ipairs(visible) do
      local column = COLUMNS[i]
      local title = "─ " .. column.title .. " · " .. #state.cards[column.status] .. " "
      local heading = maki.ui.truncate_text(title, widths[position] - 2).head
      header[#header + 1] = styled(
        "┌" .. heading .. string.rep("─", widths[position] - 2 - maki.ui.display_width(heading)) .. "┐",
        COLUMN_COLORS[i],
        i == state.focused_column
      )
      if position < #visible then
        header[#header + 1] = styled(" ")
      end
    end
    add_line(header)
    for row = 1, layout.viewport do
      local line = {}
      for position, i in ipairs(visible) do
        local width = widths[position]
        local index = state.offsets[i] + row
        local task = state.cards[COLUMNS[i].status][index]
        local selected = task and i == state.focused_column and index == state.selected[i]
        local marked = task and state.marked[task.id]
        local marker = selected and "▸ " or "  "
        local content = marker .. (task and task.title or "")
        line[#line + 1] = styled("│", border_color(i), i == state.focused_column)
        line[#line + 1] = styled(
          fit(content, width - 2),
          (selected or marked) and COLUMN_COLORS[i] or foreground,
          selected or marked or false
        )
        line[#line + 1] = styled("│", border_color(i), i == state.focused_column)
        if position < #visible then
          line[#line + 1] = styled(" ")
        end
      end
      add_line(line)
    end
    local bottom = {}
    for position, i in ipairs(visible) do
      bottom[#bottom + 1] =
        styled("└" .. string.rep("─", widths[position] - 2) .. "┘", border_color(i), i == state.focused_column)
      if position < #visible then
        bottom[#bottom + 1] = styled(" ")
      end
    end
    add_line(bottom)
  else
    for _ = 1, layout.column_height do
      blank()
    end
  end
  for _ = 1, layout.gap do
    blank()
  end
  local message, color, bold = "NORMAL", foreground, false
  if state.pending_delete_ids then
    message = "Delete " .. #state.pending_delete_ids .. " task(s)?  y/N"
    color, bold = (maki.ui.theme_style("error") or {}).fg, true
  elseif not state.valid or state.error_message then
    message = "Error: " .. tostring(state.error_message or state.error or "unknown error")
    color, bold = (maki.ui.theme_style("error") or {}).fg, true
  else
    local hint = "? help   q quit"
    local inner = math.max(0, pane_width - 4)
    message = message .. string.rep(" ", math.max(1, inner - #message - #hint)) .. hint
  end
  for row = 1, layout.footer_height do
    if pane_width < 2 or layout.footer_height == 1 then
      add_line({ styled(fit(message, pane_width), color, bold) })
    elseif row == 1 then
      add_line({ styled("┌" .. string.rep("─", pane_width - 2) .. "┐", foreground) })
    elseif row == 3 then
      add_line({ styled("└" .. string.rep("─", pane_width - 2) .. "┘", foreground) })
    else
      add_line({
        styled("│", foreground),
        styled(fit(" " .. message, pane_width - 2), color, bold),
        styled("│", foreground),
      })
    end
  end
  for _ = 1, layout.vertical do
    blank()
  end
  if state.help_open and not state.pending_delete_ids then
    Display.help_overlay(state, lines, HELP)
  end
  return lines
end

return BoardView
