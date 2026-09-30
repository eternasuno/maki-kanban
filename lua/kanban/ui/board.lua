local Board = {}
Board.__index = Board

local COLUMNS = {
  { status = "todo", title = "TODO" },
  { status = "doing", title = "DOING" },
  { status = "done", title = "DONE" },
}
local COLUMN_COLORS = {
  maki.ui.theme_color("accent"),
  maki.ui.theme_color("warning"),
  maki.ui.theme_color("success"),
}
local HORIZONTAL_PADDING = 2
local VERTICAL_PADDING = 1

local function styled(text, color, background, bold)
  return { text, { fg = color, bg = background, bold = bold } }
end

local function fit(text, width)
  if width <= 0 then return "" end
  if maki.ui.display_width(text) > width then
    text = maki.ui.truncate_text(text, width).head
  end
  return text .. string.rep(" ", math.max(0, width - maki.ui.display_width(text)))
end

local function make_cards(tasks)
  local cards = { todo = {}, doing = {}, done = {} }
  for _, task in ipairs(tasks) do
    local bucket = cards[task.status]
    if bucket then bucket[#bucket + 1] = task end
  end
  return cards
end

local function padding(state)
  local horizontal = state.width >= 8 and HORIZONTAL_PADDING or 0
  local vertical = state.height >= 5 and VERTICAL_PADDING or 0
  return horizontal, vertical
end

local function pane_widths(width, focused)
  if width < 60 then return { width }, { focused } end
  local usable = width - 2
  local base, extra = math.floor(usable / 3), usable % 3
  local widths = {}
  for i = 1, 3 do widths[i] = base + (i <= extra and 1 or 0) end
  return widths, { 1, 2, 3 }
end

local function clamp_state(state)
  local _, vertical = padding(state)
  local viewport = math.max(0, state.height - 2 * vertical - 2)
  for i, column in ipairs(COLUMNS) do
    local count = #state.cards[column.status]
    state.selected[i] = math.min(math.max(1, state.selected[i]), math.max(1, count))
    local max_offset = math.max(0, count - viewport)
    state.offsets[i] = math.min(math.max(0, state.offsets[i]), max_offset)
    if state.selected[i] <= state.offsets[i] then
      state.offsets[i] = state.selected[i] - 1
    elseif state.selected[i] > state.offsets[i] + viewport then
      state.offsets[i] = state.selected[i] - viewport
    end
    state.offsets[i] = math.min(math.max(0, state.offsets[i]), max_offset)
  end
end

local function board_lines(state)
  clamp_state(state)
  local horizontal, vertical = padding(state)
  local pane_width = state.width - 2 * horizontal
  local lines = {}
  if pane_width < 3 or state.height - 2 * vertical < 2 then
    for _ = 1, state.height do lines[#lines + 1] = string.rep(" ", state.width) end
    return lines
  end
  local widths, visible = pane_widths(pane_width, state.focused_column)
  local function add_line(spans)
    if horizontal > 0 then
      table.insert(spans, 1, styled(string.rep(" ", horizontal)))
      spans[#spans + 1] = styled(string.rep(" ", horizontal))
    end
    lines[#lines + 1] = spans
  end
  for _ = 1, vertical do lines[#lines + 1] = string.rep(" ", state.width) end
  local header = {}
  for position, i in ipairs(visible) do
    local column = COLUMNS[i]
    local color = COLUMN_COLORS[i]
    local title = string.format("[%d] %s(%d)", i, column.title, #state.cards[column.status])
    local heading = maki.ui.truncate_text(title, math.max(0, widths[position] - 3)).head
    header[#header + 1] = styled("┌─" .. heading .. string.rep("─", math.max(0, widths[position] - 3 - maki.ui.display_width(heading))) .. "┐", color, nil, i == state.focused_column)
    if position < #visible then header[#header + 1] = styled(" ") end
  end
  add_line(header)

  for row = 1, math.max(0, state.height - 2 * vertical - 2) do
    local line = {}
    for position, i in ipairs(visible) do
      local column = COLUMNS[i]
      local color = COLUMN_COLORS[i]
      local width = widths[position]
      local task_index = state.offsets[i] + row
      local task = state.cards[column.status][task_index]
      local title = task and task.title or ""
      line[#line + 1] = styled("│", color, nil, i == state.focused_column)
      local selected = task and i == state.focused_column and task_index == state.selected[i]
      if selected then
        local selection = maki.ui.theme_style("item_selected") or {}
        line[#line + 1] = styled(" " .. fit(title, math.max(0, width - 4)) .. " ", selection.fg or maki.ui.theme_color("background"), selection.bg or maki.ui.theme_color("accent"))
      else
        line[#line + 1] = styled(" " .. fit(title, math.max(0, width - 4)) .. " ", maki.ui.theme_color("foreground"))
      end
      line[#line + 1] = styled("│", color, nil, i == state.focused_column)
      if position < #visible then line[#line + 1] = styled(" ") end
    end
    add_line(line)
  end
  local bottom = {}
  for position, i in ipairs(visible) do
    bottom[#bottom + 1] = styled("└" .. string.rep("─", math.max(0, widths[position] - 2)) .. "┘", COLUMN_COLORS[i], nil, i == state.focused_column)
    if position < #visible then bottom[#bottom + 1] = styled(" ") end
  end
  add_line(bottom)
  for _ = 1, vertical do lines[#lines + 1] = string.rep(" ", state.width) end
  return lines
end

local function error_lines(err, width, height)
  local text = "Could not load kanban: " .. tostring(err or "unknown error")
  local lines = { fit(text, width) }
  while #lines < height do lines[#lines + 1] = string.rep(" ", width) end
  return lines
end

local function refresh_lines(state)
  state.lines = state.valid and board_lines(state) or error_lines(state.error, state.width, state.height)
  if state.pending_delete_id then
    state.lines[state.height] = { styled(fit("Delete this task? y/N", state.width), maki.ui.theme_color("warning")) }
  elseif state.valid and state.error_message then
    state.lines[state.height] = { styled(fit("error: " .. state.error_message, state.width), maki.ui.theme_color("error")) }
  end
end

function Board.new(width, height)
  local self = setmetatable({}, Board)
  self._state = {
    width = math.max(1, width), height = math.max(1, height), focused_column = 1,
    offsets = { 0, 0, 0 }, selected = { 1, 1, 1 },
    valid = true, tasks = {}, cards = { todo = {}, doing = {}, done = {} },
  }
  refresh_lines(self._state)
  return self
end

function Board:reload(store)
  local state = self._state
  state.error_message, state.pending_delete_id = nil, nil
  local selected_ids = {}
  for i, column in ipairs(COLUMNS) do
    local task = state.cards[column.status][state.selected[i]]
    selected_ids[i] = task and task.id
  end
  local tasks, err = store:list()
  if not tasks then
    state.valid, state.error, state.tasks = false, err, {}
    state.cards = { todo = {}, doing = {}, done = {} }
  else
    state.valid, state.error, state.tasks = true, nil, tasks
    state.cards = make_cards(tasks)
    for i, column in ipairs(COLUMNS) do
      for index, task in ipairs(state.cards[column.status]) do
        if task.id == selected_ids[i] then state.selected[i] = index; break end
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
  if state.pending_delete_id then
    local id = state.pending_delete_id
    state.pending_delete_id = nil
    if key == "y" then
      local deleted, err = store:delete(id)
      if deleted then
        self:reload(store)
      else
        state.error_message = tostring(err or "could not delete task")
      end
    end
    refresh_lines(state)
    return true
  end
  local number = tonumber(key)
  if number and number >= 1 and number <= #COLUMNS then
    state.focused_column = number
  elseif key == "l" or key == "<Right>" then
    state.focused_column = state.focused_column % #COLUMNS + 1
  elseif key == "h" or key == "<Left>" then
    state.focused_column = (state.focused_column - 2) % #COLUMNS + 1
  elseif key == "H" or key == "L" then
    local task = self:selected_task()
    local target = state.focused_column + (key == "H" and -1 or 1)
    if not task or not COLUMNS[target] then return true end
    local updated, err = store:update(task.id, { status = COLUMNS[target].status })
    if not updated then
      state.error_message = tostring(err or "could not move task")
    else
      self:reload(store)
      self:select_task(task.id)
    end
  elseif key == "j" or key == "<Down>" or key == "k" or key == "<Up>" then
    local i = state.focused_column
    local count = #state.cards[COLUMNS[i].status]
    state.selected[i] = math.max(1, math.min(count, state.selected[i] + ((key == "j" or key == "<Down>") and 1 or -1)))
    clamp_state(state)
  elseif key == "d" then
    local task = state.valid and self:selected_task()
    if not task then return true end
    state.pending_delete_id = task.id
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

return Board
