local Board = {}
Board.__index = Board

local COLUMNS = {
  { status = "todo", title = "TODO" },
  { status = "doing", title = "DOING" },
  { status = "done", title = "DONE" },
}
local COLUMN_COLORS = {
  (maki.ui.theme_style("accent") or {}).fg,
  (maki.ui.theme_style("warning") or {}).fg,
  (maki.ui.theme_style("success") or {}).fg,
}
local HORIZONTAL_PADDING = 2
local VERTICAL_PADDING = 1

local function styled(text, color, background, bold)
  return { text, { fg = color, bg = background, bold = bold } }
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

local function make_cards(tasks)
  local cards = { todo = {}, doing = {}, done = {} }
  for _, task in ipairs(tasks) do
    local bucket = cards[task.status]
    if bucket then
      bucket[#bucket + 1] = task
    end
  end
  return cards
end

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

local function layout(state)
  local horizontal, vertical = padding(state)
  if state.height < 8 then
    vertical = 0
  end
  local available = state.height - 2 * vertical
  local footer_height = math.min(3, available)
  local gap = available >= 6 and 1 or 0
  local column_height = available - footer_height - gap
  return horizontal, vertical, column_height, math.max(0, column_height - 2), gap, footer_height
end

local function clamp_state(state)
  local _, _, _, viewport = layout(state)
  for i, column in ipairs(COLUMNS) do
    local count = #state.cards[column.status]
    state.selected[i] = math.min(math.max(1, state.selected[i]), math.max(1, count))
    local max_offset = math.max(0, count - viewport)
    state.offsets[i] = math.min(math.max(0, state.offsets[i]), max_offset)
    if viewport > 0 then
      if state.selected[i] <= state.offsets[i] then
        state.offsets[i] = state.selected[i] - 1
      elseif state.selected[i] > state.offsets[i] + viewport then
        state.offsets[i] = state.selected[i] - viewport
      end
    end
    state.offsets[i] = math.min(math.max(0, state.offsets[i]), max_offset)
  end
end

local function slice_line(line, start, length)
  local result, position = {}, 0
  if type(line) == "string" then
    line = { styled(line) }
  end
  for _, span in ipairs(line) do
    local text, style = span[1], span[2]
    local width = maki.ui.display_width(text)
    local left, right = math.max(start, position), math.min(start + length, position + width)
    if right > left then
      local prefix = maki.ui.truncate_text(text, left - position)
      local leading = left - position - maki.ui.display_width(prefix.head)
      local tail = prefix.tail
      if leading > 0 then
        local first = maki.ui.truncate_text(tail, 2)
        tail = first.tail
      end
      local part = maki.ui.truncate_text(tail, math.max(0, right - left - leading)).head
      result[#result + 1] = { fit(string.rep(" ", leading) .. part, right - left), style }
    end
    position = position + width
  end
  return result
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

function Board.help_overlay(state, lines, help)
  if state.width <= 0 or state.height <= 0 then
    return
  end
  local width, height = math.min(36, state.width), math.min(#help + 2, state.height)
  if width < 2 or height < 2 then
    lines[math.floor((state.height + 1) / 2)] =
      { styled(fit("? Help: ? / Esc close", state.width), (maki.ui.theme_style("accent") or {}).fg) }
    return
  end
  local x, y = math.floor((state.width - width) / 2), math.floor((state.height - height) / 2)
  local color = maki.ui.theme_color("foreground")
  for row = 1, height do
    local text
    if row == 1 then
      local title = maki.ui.truncate_text("─ Keybindings ", width - 2).head
      text = "┌" .. title .. string.rep("─", width - 2 - maki.ui.display_width(title)) .. "┐"
    elseif row == height then
      text = "└" .. string.rep("─", width - 2) .. "┘"
    else
      text = "│" .. fit(help[row - 1] or "", width - 2) .. "│"
    end
    local line = slice_line(lines[y + row], 0, x)
    line[#line + 1] = styled(text, row == 1 and (maki.ui.theme_style("accent") or {}).fg or color)
    for _, span in ipairs(slice_line(lines[y + row], x + width, state.width - x - width)) do
      line[#line + 1] = span
    end
    lines[y + row] = line
  end
end

local function board_lines(state)
  local horizontal, vertical, column_height, viewport, gap, footer_height = layout(state)
  local pane_width = state.width - 2 * horizontal
  local lines = {}
  local foreground = maki.ui.theme_color("foreground")
  local function add_line(spans)
    table.insert(spans, 1, styled(string.rep(" ", horizontal)))
    spans[#spans + 1] = styled(string.rep(" ", horizontal))
    lines[#lines + 1] = spans
  end
  local function blank()
    lines[#lines + 1] = string.rep(" ", state.width)
  end
  local function border_color(i)
    return i == state.focused_column and COLUMN_COLORS[i] or foreground
  end
  for _ = 1, vertical do
    blank()
  end
  if pane_width >= 3 and column_height >= 2 then
    local widths, visible = pane_widths(pane_width, state.focused_column)
    local header = {}
    for position, i in ipairs(visible) do
      local column = COLUMNS[i]
      local title = "─ " .. column.title .. " · " .. #state.cards[column.status] .. " "
      local heading = maki.ui.truncate_text(title, widths[position] - 2).head
      header[#header + 1] = styled(
        "┌" .. heading .. string.rep("─", widths[position] - 2 - maki.ui.display_width(heading)) .. "┐",
        COLUMN_COLORS[i],
        nil,
        i == state.focused_column
      )
      if position < #visible then
        header[#header + 1] = styled(" ")
      end
    end
    add_line(header)
    local marker_width = maki.ui.display_width("▸ ")
    for row = 1, viewport do
      local line = {}
      for position, i in ipairs(visible) do
        local width = widths[position]
        local index = state.offsets[i] + row
        local task = state.cards[COLUMNS[i].status][index]
        local selected = task and i == state.focused_column and index == state.selected[i]
        local marked = task and state.marked[task.id]
        local marker = selected and "▸ " or "  "
        local content = marker .. (task and task.title or "")
        line[#line + 1] = styled("│", border_color(i), nil, i == state.focused_column)
        line[#line + 1] = styled(
          fit(content, width - 2),
          (selected or marked) and COLUMN_COLORS[i] or foreground,
          nil,
          selected or marked or false
        )
        line[#line + 1] = styled("│", border_color(i), nil, i == state.focused_column)
        if position < #visible then
          line[#line + 1] = styled(" ")
        end
      end
      add_line(line)
    end
    local bottom = {}
    for position, i in ipairs(visible) do
      bottom[#bottom + 1] = styled(
        "└" .. string.rep("─", widths[position] - 2) .. "┘",
        border_color(i),
        nil,
        i == state.focused_column
      )
      if position < #visible then
        bottom[#bottom + 1] = styled(" ")
      end
    end
    add_line(bottom)
  else
    for _ = 1, column_height do
      blank()
    end
  end
  for _ = 1, gap do
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
  for row = 1, footer_height do
    if pane_width < 2 or footer_height == 1 then
      add_line({ styled(fit(message, pane_width), color, nil, bold) })
    elseif row == 1 then
      add_line({ styled("┌" .. string.rep("─", pane_width - 2) .. "┐", foreground) })
    elseif row == 3 then
      add_line({ styled("└" .. string.rep("─", pane_width - 2) .. "┘", foreground) })
    else
      add_line({
        styled("│", foreground),
        styled(fit(" " .. message, pane_width - 2), color, nil, bold),
        styled("│", foreground),
      })
    end
  end
  for _ = 1, vertical do
    blank()
  end
  if state.help_open and not state.pending_delete_ids then
    Board.help_overlay(state, lines, HELP)
  end
  return lines
end

local function refresh_lines(state)
  clamp_state(state)
  state.lines = board_lines(state)
end

function Board.new(width, height)
  local self = setmetatable({}, Board)
  self._state = {
    width = math.max(1, width),
    height = math.max(1, height),
    focused_column = 1,
    offsets = { 0, 0, 0 },
    selected = { 1, 1, 1 },
    marked = {},
    valid = true,
    tasks = {},
    cards = { todo = {}, doing = {}, done = {} },
  }
  refresh_lines(self._state)
  return self
end

function Board:reload(store)
  local state = self._state
  state.error_message, state.pending_delete_ids = nil, nil
  local selected_ids = {}
  for i, column in ipairs(COLUMNS) do
    local task = state.cards[column.status][state.selected[i]]
    selected_ids[i] = task and task.id
  end
  local tasks, err = store:list()
  if not tasks then
    state.valid, state.error, state.tasks = false, err, {}
    state.cards, state.marked = { todo = {}, doing = {}, done = {} }, {}
  else
    state.valid, state.error, state.tasks = true, nil, tasks
    local existing = {}
    for _, task in ipairs(tasks) do
      if task.status == COLUMNS[state.focused_column].status then
        existing[task.id] = true
      end
    end
    for id in pairs(state.marked) do
      if not existing[id] then
        state.marked[id] = nil
      end
    end
    state.cards = make_cards(tasks)
    for i, column in ipairs(COLUMNS) do
      for index, task in ipairs(state.cards[column.status]) do
        if task.id == selected_ids[i] then
          state.selected[i] = index
          break
        end
      end
    end
  end
  refresh_lines(state)
end

function Board:resize(width, height)
  local state = self._state
  state.width, state.height = math.max(1, width), math.max(1, height)
  refresh_lines(state)
end

function Board:render()
  return self._state.lines
end

function Board:handle_key(key, store)
  local state = self._state
  if state.pending_delete_ids then
    local ids = state.pending_delete_ids
    state.pending_delete_ids = nil
    if key == "y" then
      local deleted, err = store:delete_many(ids)
      if deleted then
        self:reload(store)
      else
        state.error_message = tostring(err or "could not delete task")
      end
    end
    refresh_lines(state)
    return true
  end
  if state.help_open then
    if key == "<C-c>" then
      return "quit"
    end
    if key == "?" or key == "<Esc>" then
      state.help_open = false
      refresh_lines(state)
    end
    return true
  end
  if key == "?" then
    state.help_open = true
  elseif key == "<Space>" or key == " " then
    local task = state.valid and self:selected_task()
    if task then
      if state.marked[task.id] then
        state.marked[task.id] = nil
      else
        state.marked[task.id] = true
      end
    end
  elseif key == "g" or key == "G" then
    local i = state.focused_column
    state.selected[i] = key == "g" and 1 or math.max(1, #state.cards[COLUMNS[i].status])
  elseif key == "l" or key == "<Right>" then
    state.marked = {}
    state.focused_column = state.focused_column % #COLUMNS + 1
  elseif key == "h" or key == "<Left>" then
    state.marked = {}
    state.focused_column = (state.focused_column - 2) % #COLUMNS + 1
  elseif key == "<" or key == ">" then
    local tasks = self:selected_tasks()
    local task = self:selected_task()
    local had_marks = next(state.marked) ~= nil
    local target = state.focused_column + (key == "<" and -1 or 1)
    if #tasks == 0 or not COLUMNS[target] then
      return true
    end
    local updates = {}
    for _, item in ipairs(tasks) do
      updates[item.id] = { status = COLUMNS[target].status }
    end
    local updated, err = store:update_many(updates)
    if not updated then
      state.error_message = tostring(err or "could not move task")
    else
      self:reload(store)
      if task then
        self:select_task(task.id)
      end
      if had_marks and state.valid and state.focused_column == target then
        local moved = {}
        for _, item in ipairs(tasks) do
          moved[item.id] = true
        end
        for _, item in ipairs(state.cards[COLUMNS[target].status]) do
          if moved[item.id] then
            state.marked[item.id] = true
          end
        end
      end
    end
  elseif key == "j" or key == "<Down>" or key == "k" or key == "<Up>" then
    local i = state.focused_column
    local count = #state.cards[COLUMNS[i].status]
    state.selected[i] = math.max(1, math.min(count, state.selected[i] + ((key == "j" or key == "<Down>") and 1 or -1)))
    clamp_state(state)
  elseif key == "d" then
    local tasks = self:selected_tasks()
    if #tasks == 0 then
      return true
    end
    local ids = {}
    for _, task in ipairs(tasks) do
      ids[#ids + 1] = task.id
    end
    state.pending_delete_ids = ids
  elseif key == "r" then
    self:reload(store)
    return true
  else
    return false
  end
  refresh_lines(state)
  return true
end

function Board:select_task(id)
  local state = self._state
  for i, column in ipairs(COLUMNS) do
    for index, task in ipairs(state.cards[column.status]) do
      if task.id == id then
        if i ~= state.focused_column then
          state.marked = {}
        end
        state.focused_column, state.selected[i] = i, index
        refresh_lines(state)
        return true
      end
    end
  end
  return false
end

function Board:selected_task()
  local state = self._state
  local column = COLUMNS[state.focused_column]
  return state.cards[column.status][state.selected[state.focused_column]]
end

function Board:selected_tasks()
  local state = self._state
  local tasks = {}
  if not state.valid then
    return tasks
  end
  for index, task in ipairs(state.cards[COLUMNS[state.focused_column].status]) do
    if index == state.selected[state.focused_column] or state.marked[task.id] then
      tasks[#tasks + 1] = task
    end
  end
  return tasks
end

return Board
