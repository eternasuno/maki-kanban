local Store = require("kanban.store")
local Board = require("kanban.ui.board")
local Task = require("kanban.ui.task")

local store = Store.new()
local M = {}
local open_win = nil

local function window_width(term)
  return math.max(1, math.floor(term.cols * 0.9))
end

local function window_height(term)
  return math.max(1, math.floor(term.rows * 0.9))
end

local function handle_resize(state, buf, ev)
  local term = maki.ui.terminal_size()
  local width = ev.width or window_width(term)
  local height = ev.height or window_height(term)
  if width == state.width and height == state.height then
    return
  end
  state.width, state.height = width, height
  state.board:resize(width, height)
  if state.task then
    state.task:resize(width, height)
  end
  buf:set_lines(state.view == "board" and state.board:render() or state.task:render())
end

local function handle_reference(board, win)
  local tasks = board:selected_tasks()
  if #tasks == 0 then
    return
  end
  local references = {}
  for _, task in ipairs(tasks) do
    references[#references + 1] = "[task:" .. task.id .. "] " .. task.title
  end
  local reference = table.concat(references, "\n")
  win:close()
  open_win = nil
  local input, input_err = maki.ui.input()
  if not input then
    maki.notify(
      "Could not reference task in Maki input: " .. tostring(input_err or "input unavailable"),
      "error",
      { title = "Kanban" }
    )
    return "quit"
  end
  local separator = input.text ~= "" and not input.text:sub(1, input.cursor):match("\n$") and "\n" or ""
  local inserted, edit_err = maki.ui.input_edit({
    start = input.cursor,
    stop = input.cursor,
    text = separator .. reference,
    cursor = input.cursor + #separator + #reference,
    version = input.version,
    session_id = input.session_id,
  })
  if not inserted then
    maki.notify(
      "Could not reference task in Maki input: " .. tostring(edit_err or "input edit failed"),
      "error",
      { title = "Kanban" }
    )
  end
  return "quit"
end

local function handle_board_key(state, buf, win, key)
  if state.board:is_modal() then
    if state.board:handle_key(key, store) == "quit" then
      return "quit"
    end
    buf:set_lines(state.board:render())
  elseif key == "q" or key == "<Esc>" or key == "<C-c>" then
    return "quit"
  elseif key == "a" then
    return handle_reference(state.board, win)
  elseif key == "n" then
    state.task = Task.new_create(state.width, state.height)
    state.view = "task"
    buf:set_lines(state.task:render())
  elseif key == "<CR>" or key == "<Enter>" then
    local selected = state.board:selected_task()
    if selected then
      state.task = Task.new(selected, state.width, state.height)
      state.view = "task"
      buf:set_lines(state.task:render())
    end
  elseif state.board:handle_key(key, store) then
    buf:set_lines(state.board:render())
  end
end

local function handle_task_key(state, buf, key)
  local action = state.task:handle_key(key, store)
  if action == "quit" then
    return "quit"
  elseif action == "deleted" or action == "back" then
    state.board:reload(store)
    state.view, state.task = "board", nil
    buf:set_lines(state.board:render())
  elseif action == "created" or action == "changed" then
    state.board:reload(store)
    state.board:select_task(state.task.task.id)
    buf:set_lines(state.task:render())
  elseif action then
    buf:set_lines(state.task:render())
  end
end

local function handle_key(state, buf, win, key)
  if state.view == "board" then
    return handle_board_key(state, buf, win, key)
  end
  return handle_task_key(state, buf, key)
end

function M.open()
  if open_win then
    return
  end
  local term = maki.ui.terminal_size()
  local width, height = window_width(term), window_height(term)
  local buf = maki.ui.buf({ scratch = true })
  local state = { view = "board", board = Board.new(width, height), task = nil, width = width, height = height }
  state.board:reload(store)
  buf:set_lines(state.board:render())
  local win = maki.ui.open_win(buf, {
    width = "90%",
    height = "90%",
    border = "none",
    focus = true,
    cursor_line = false,
  })
  open_win = win

  local ok, loop_err = pcall(function()
    while true do
      local ev = win:recv()
      if not ev or ev.type == "close" then
        return
      end
      if ev.type == "resize" then
        handle_resize(state, buf, ev)
      elseif ev.type == "paste" then
        if state.view == "task" and state.task:handle_paste(ev.text) then
          buf:set_lines(state.task:render())
        end
      elseif ev.type == "key" and handle_key(state, buf, win, ev.key) == "quit" then
        return
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
