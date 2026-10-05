local BoardView = require("kanban.ui.board_view")

local Board = {}
Board.__index = Board

local STATUSES = require("kanban.status")

local function make_cards(tasks)
  local cards = { todo = {}, doing = {}, done = {} }
  for _, task in ipairs(tasks) do
    local bucket = cards[task.status]
    bucket[#bucket + 1] = task
  end
  return cards
end

local function clamp_state(state)
  local viewport = BoardView.layout(state).viewport
  for i, status in ipairs(STATUSES) do
    local count = #state.cards[status]
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

function Board:reload(store, focus_id)
  local state = self._state
  state.error_message, state.pending_delete_ids = nil, nil
  local selected_ids = {}
  for i, status in ipairs(STATUSES) do
    local task = state.cards[status][state.selected[i]]
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
      if task.status == STATUSES[state.focused_column] then
        existing[task.id] = true
      end
    end
    for id in pairs(state.marked) do
      if not existing[id] then
        state.marked[id] = nil
      end
    end
    state.cards = make_cards(tasks)
    for i, status in ipairs(STATUSES) do
      for index, task in ipairs(state.cards[status]) do
        if task.id == selected_ids[i] then
          state.selected[i] = index
          break
        end
      end
    end
  end
  clamp_state(state)
  invalidate(state)
  if not tasks then
    return false
  end
  if focus_id then
    self:select_task(focus_id)
  end
  return true
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

local function restore_moved_marks(state, tasks, target)
  if not state.valid or state.focused_column ~= target then
    return
  end
  local moved = {}
  for _, task in ipairs(tasks) do
    moved[task.id] = true
  end
  for _, task in ipairs(state.cards[STATUSES[target]]) do
    if moved[task.id] then
      state.marked[task.id] = true
    end
  end
end

local function move_tasks(board, store, direction)
  local state = board._state
  local tasks = board:selected_tasks()
  local task = board:selected_task()
  local had_marks = next(state.marked) ~= nil
  local target = state.focused_column + direction
  if #tasks == 0 or not STATUSES[target] then
    return
  end
  local updates = {}
  for _, item in ipairs(tasks) do
    updates[item.id] = { status = STATUSES[target] }
  end
  local updated, err = store:update_many(updates)
  if not updated then
    state.error_message = tostring(err or "could not move task")
    return
  end
  if board:reload(store, task and task.id) and had_marks then
    restore_moved_marks(state, tasks, target)
  end
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
    state.selected[i] = key == "g" and 1 or math.max(1, #state.cards[STATUSES[i]])
    clamp_state(state)
  elseif key == "l" or key == "<Right>" then
    state.marked = {}
    state.focused_column = state.focused_column % #STATUSES + 1
  elseif key == "h" or key == "<Left>" then
    state.marked = {}
    state.focused_column = (state.focused_column - 2) % #STATUSES + 1
  elseif key == "<" or key == ">" then
    move_tasks(self, store, key == "<" and -1 or 1)
  elseif key == "j" or key == "<Down>" or key == "k" or key == "<Up>" then
    local i = state.focused_column
    local count = #state.cards[STATUSES[i]]
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
  for i, status in ipairs(STATUSES) do
    for index, task in ipairs(state.cards[status]) do
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
  local status = STATUSES[state.focused_column]
  return state.cards[status][state.selected[state.focused_column]]
end

function Board:selected_tasks()
  local state = self._state
  local tasks = {}
  if not state.valid then
    return tasks
  end
  for index, task in ipairs(state.cards[STATUSES[state.focused_column]]) do
    if index == state.selected[state.focused_column] or state.marked[task.id] then
      tasks[#tasks + 1] = task
    end
  end
  return tasks
end

return Board
