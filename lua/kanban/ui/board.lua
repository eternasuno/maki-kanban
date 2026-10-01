local BoardView = require("kanban.ui.board_view")

local Board = {}
Board.__index = Board

local COLUMNS = BoardView.columns

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

local function clamp_state(state)
  local _, _, _, viewport = BoardView.layout(state)
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

local function invalidate(state)
  state.lines = nil
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
    cards = { todo = {}, doing = {}, done = {} },
  }
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
    state.valid, state.error = false, err
    state.cards, state.marked = { todo = {}, doing = {}, done = {} }, {}
  else
    state.valid, state.error = true, nil
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
  clamp_state(state)
  invalidate(state)
end

function Board:resize(width, height)
  local state = self._state
  state.width, state.height = math.max(1, width), math.max(1, height)
  clamp_state(state)
  invalidate(state)
end

function Board:render()
  local state = self._state
  if not state.lines then
    state.lines = BoardView.render(state)
  end
  return state.lines
end

function Board:is_modal()
  local state = self._state
  return state.pending_delete_ids ~= nil or state.help_open == true
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
    invalidate(state)
    return true
  end
  if state.help_open then
    if key == "<C-c>" then
      return "quit"
    end
    if key == "?" or key == "<Esc>" then
      state.help_open = false
      invalidate(state)
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
    clamp_state(state)
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
  invalidate(state)
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
        clamp_state(state)
        invalidate(state)
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
