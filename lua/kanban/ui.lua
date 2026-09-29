local Store = require("kanban.store")

local store = Store.new()

local M = {}

local COLUMNS = {
  { status = "todo", title = "TODO" },
  { status = "doing", title = "Doing" },
  { status = "done", title = "Complete" },
}

local FOOTER = { { "h/l", "column" }, { "1-3", "jump" }, { "j/k", "task" }, { "q", "close" } }
local COLUMN_COLORS = {
  maki.ui.theme_color("accent"),
  maki.ui.theme_color("warning"),
  maki.ui.theme_color("success"),
}
local MARGIN = 4
local MIN_WIDTH = 24
local MAX_WIDTH = 140
local TARGET_HEIGHT = 18
local FOOTER_ROWS = 3
local RESERVED_TOP = 1
local open_win = nil

local function fit(text, width)
  if maki.ui.display_width(text) > width then
    text = maki.ui.truncate_text(text, width).head
  end
  return text .. string.rep(" ", math.max(0, width - maki.ui.display_width(text)))
end

local function board_tasks(board)
  local tasks = {}
  for id, task in pairs(board.tasks) do
    tasks[#tasks + 1] = { id = id, title = task.title, status = task.status }
  end
  table.sort(tasks, function(a, b)
    return a.id < b.id
  end)
  return tasks
end

local function column_widths(content_width)
  local num_cols = #COLUMNS
  local spacing = num_cols - 1
  local borders = num_cols * 2
  local outer_padding = 2
  local avail = math.max(0, content_width - spacing - borders - outer_padding)
  local base = math.floor(avail / num_cols)
  local rem = avail % num_cols
  local widths = {}
  for i = 1, num_cols do
    widths[i] = math.max(1, base + (i <= rem and 1 or 0))
  end
  return widths
end
local function styled(text, color, background)
  return { text, { fg = color, bg = background } }
end

local function border_cell(text, color)
  return styled(text, color)
end

local function footer_lines(width)
  local footer_color = maki.ui.theme_color("accent")
  local inner_width = math.max(0, width - 2)
  local hints = {}
  for _, item in ipairs(FOOTER) do
    hints[#hints + 1] = " " .. item[1] .. " " .. item[2]
  end
  local hint_text = maki.ui.truncate_text(table.concat(hints, " "), inner_width).head
  return {
    { styled("┌" .. string.rep("─", inner_width) .. "┐", footer_color) },
    {
      styled("│", footer_color),
      styled(fit(hint_text, inner_width), maki.ui.theme_color("foreground"), maki.ui.theme_color("background")),
      styled("│", footer_color),
    },
    { styled("└" .. string.rep("─", inner_width) .. "┘", footer_color) },
  }
end

local function append_footer(lines, width)
  for _, line in ipairs(footer_lines(width)) do
    lines[#lines + 1] = line
  end
end

local function error_lines(err, width, height)
  local lines = {
    { { "Could not load the kanban board", "bold" } },
    fit(tostring(err or "unknown error"), width),
  }
  while #lines < height - FOOTER_ROWS do
    lines[#lines + 1] = ""
  end
  append_footer(lines, width)
  return lines
end

local function board_lines(tasks, content_width, content_height, offsets, focused_column, selected)
  local widths = column_widths(content_width)
  local cards = {}
  for _, column in ipairs(COLUMNS) do
    cards[column.status] = {}
  end
  for _, task in ipairs(tasks) do
    local bucket = cards[task.status]
    if bucket then
      bucket[#bucket + 1] = task
    end
  end
  local rows = math.max(1, content_height - FOOTER_ROWS - 2)
  local lines = {}
  local header = {}
  for i, column in ipairs(COLUMNS) do
    local color = COLUMN_COLORS[i]
    local title = "[" .. i .. "] " .. column.title
    local segment = "┌" .. title .. string.rep("─", math.max(0, widths[i] - maki.ui.display_width(title))) .. "┐"
    header[#header + 1] = styled(segment, color)
    if i < #COLUMNS then header[#header + 1] = styled(" ", color) end
  end
  lines[1] = header

  for row = 1, rows do
    local line = {}
    for i, column in ipairs(COLUMNS) do
      local bucket = cards[column.status]
      local task_index = row + offsets[i]
      local task = bucket[task_index]
      local color = COLUMN_COLORS[i]
      local is_selected = task and i == focused_column and selected[i] == task_index
      local text = task and task.title or (row == 1 and #bucket == 0 and "(no tasks)" or "")
      line[#line + 1] = border_cell("│", color)
      if is_selected then
        line[#line + 1] = { " " .. fit(text, math.max(0, widths[i] - 2)) .. " ", { fg = color, bg = maki.ui.theme_color("accent") } }
      else
        line[#line + 1] = styled(" " .. fit(text, math.max(0, widths[i] - 2)) .. " ", color)
      end
      line[#line + 1] = border_cell("│", color)
      if i < #COLUMNS then line[#line + 1] = styled(" ", color) end
    end
    lines[#lines + 1] = line
  end

  local bottom = {}
  for i, width in ipairs(widths) do
    bottom[#bottom + 1] = border_cell("└" .. string.rep("─", width) .. "┘", COLUMN_COLORS[i])
    if i < #widths then bottom[#bottom + 1] = styled(" ", COLUMN_COLORS[i]) end
  end
  lines[#lines + 1] = bottom
  while #lines < content_height - FOOTER_ROWS - 1 do
    local blank = {}
    for i, width in ipairs(widths) do
      blank[#blank + 1] = border_cell("│", COLUMN_COLORS[i])
      blank[#blank + 1] = styled(string.rep(" ", width), COLUMN_COLORS[i])
      blank[#blank + 1] = border_cell("│", COLUMN_COLORS[i])
      if i < #widths then blank[#blank + 1] = styled(" ", COLUMN_COLORS[i]) end
    end
    lines[#lines + 1] = blank
  end

  append_footer(lines, content_width)
  return lines
end

local function window_width(term)
  return math.min(MAX_WIDTH, math.max(MIN_WIDTH, term.cols - MARGIN))
end
local function window_height(term)
  return math.max(1, math.min(TARGET_HEIGHT + FOOTER_ROWS, term.rows - MARGIN))
end

local function clamp_offset(offset, max_offset)
  if offset < 0 then
    return 0
  end
  if offset > max_offset then
    return max_offset
  end
  return offset
end

local function column_metrics(state, index)
  local count = #state.cards[COLUMNS[index].status]
  local viewport = math.max(1, state.height - FOOTER_ROWS - 2)
  local max_offset = math.max(0, count - viewport)
  return viewport, max_offset
end

local function handle_key(state, key)
  local number = tonumber(key)
  if number and number >= 1 and number <= #COLUMNS then
    state.focused_column = number
  elseif key == "l" or key == "<Right>" then
    state.focused_column = state.focused_column % #COLUMNS + 1
  elseif key == "h" or key == "<Left>" then
    state.focused_column = (state.focused_column - 2) % #COLUMNS + 1
  elseif key == "j" or key == "<Down>" or key == "k" or key == "<Up>" then
    local column = state.focused_column
    local count = #state.cards[COLUMNS[column].status]
    local viewport, max_offset = column_metrics(state, column)
    if key == "j" or key == "<Down>" then
      state.selected[column] = math.min(count, state.selected[column] + 1)
    else
      state.selected[column] = math.max(1, state.selected[column] - 1)
    end
    state.offsets[column] = clamp_offset(state.selected[column] - viewport, max_offset)
    if state.selected[column] <= state.offsets[column] then
      state.offsets[column] = state.selected[column] - 1
    end
  else
    return false
  end
  state.lines = board_lines(state.tasks, state.content_width, state.content_height, state.offsets, state.focused_column, state.selected)
  return true
end
function M.open()
  if open_win then
    return
  end

  local term = maki.ui.terminal_size()
  local width = window_width(term)
  local height = window_height(term)
  local buf = maki.ui.buf({ scratch = true })
  local board, err = store:load()
  local tasks = board and board_tasks(board) or nil
  local cards = {}
  for _, column in ipairs(COLUMNS) do
    cards[column.status] = {}
  end

  local valid = tasks ~= nil
  local lines
  if valid then
    for _, task in ipairs(tasks) do
      local bucket = cards[task.status]
      if bucket then
        bucket[#bucket + 1] = task
      end
    end
    lines = board_lines(tasks, width, height, { 0, 0, 0 }, 1, { 1, 1, 1 })
  else
    lines = error_lines(err, width, height)
  end
  buf:set_lines(lines)

  local win = maki.ui.open_win(buf, {
    width = width,
    height = height,
    border = "none",
    focus = true,
    cursor_line = false,
  })
  open_win = win

  local state = {
    valid = valid,
    error = err,
    tasks = tasks or {},
    cards = cards,
    offsets = { 0, 0, 0 },
    selected = { 1, 1, 1 },
    focused_column = 1,
    height = height,
    content_width = width,
    content_height = height,
  }

  local ok, loop_err = pcall(function()
    while true do
      local ev = win:recv()
      if not ev or ev.type == "close" then
        return
      elseif ev.type == "resize" then
        local new_term = maki.ui.terminal_size()
        local new_width = window_width(new_term)
        local new_height = window_height(new_term)
        if new_width ~= width or new_height ~= state.height then
          width = new_width
          state.height = new_height
          state.content_width = new_width
          state.content_height = new_height
          win:set_config({ width = new_width, height = new_height })
          if state.valid then
            state.lines = board_lines(state.tasks, new_width, new_height, state.offsets, state.focused_column, state.selected)
          else
            state.lines = error_lines(state.error, new_width, new_height)
          end
          buf:set_lines(state.lines)
        end
      elseif ev.type == "key" then
        if ev.key == "q" or ev.key == "<Esc>" then
          return
        end
        if handle_key(state, ev.key) then
          buf:set_lines(state.lines)
        end
      end
    end
  end)

  win:close()
  open_win = nil
  if not ok then
    error(loop_err)
  end
end

return M
