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

function M.open()
  if open_win then return end
  local term = maki.ui.terminal_size()
  local width, height = window_width(term), window_height(term)
  local buf = maki.ui.buf({ scratch = true })
  local state = { view = "board", board = Board.new(width, height), task = nil, width = width, height = height }
  state.board:reload(store)
  buf:set_lines(state.board:render())
  local win = maki.ui.open_win(buf, {
    width = "90%", height = "90%", border = "none", focus = true, cursor_line = false,
  })
  open_win = win

  local ok, loop_err = pcall(function()
    while true do
      local ev = win:recv()
      if not ev or ev.type == "close" then return end
      if ev.type == "resize" then
        local new_term = maki.ui.terminal_size()
        local new_width = ev.width or window_width(new_term)
        local new_height = ev.height or window_height(new_term)
        if new_width ~= state.width or new_height ~= state.height then
          state.width, state.height = new_width, new_height
          state.board:resize(new_width, new_height)
          if state.task then state.task:resize(new_width, new_height) end
          buf:set_lines(state.view == "board" and state.board:render() or state.task:render())
        end
      elseif ev.type == "key" then
        if ev.key == "q" or ev.key == "<Esc>" then return end
        if state.view == "board" then
          if ev.key == "<CR>" or ev.key == "<Enter>" then
            local selected = state.board:selected_task()
            if selected then
              state.task = Task.new(selected, state.width, state.height)
              state.view = "task"
              buf:set_lines(state.task:render())
            end
          elseif state.board:handle_key(ev.key, store) then
            buf:set_lines(state.board:render())
          end
        else
          local action = state.task:handle_key(ev.key)
          if action == "back" then
            state.view, state.task = "board", nil
            buf:set_lines(state.board:render())
          elseif action then
            buf:set_lines(state.task:render())
          end
        end
      end
    end
  end)
  win:close()
  open_win = nil
  if not ok then error(loop_err) end
end

return M
