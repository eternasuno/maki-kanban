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
      elseif ev.type == "paste" then
        if state.view == "task" and state.task:handle_paste(ev.text) then
          buf:set_lines(state.task:render())
        end
      elseif ev.type == "key" then
        if state.view == "board" then
          if state.board._state.pending_delete_ids or state.board._state.help_open then
            if state.board:handle_key(ev.key, store) == "quit" then return end
            buf:set_lines(state.board:render())
          elseif ev.key == "q" or ev.key == "<Esc>" or ev.key == "<C-c>" then
            return
          elseif ev.key == "a" and (state.board:selected_task() or next(state.board._state.marked)) then
            local tasks = {}
            if next(state.board._state.marked) then
              for _, task in ipairs(state.board._state.tasks) do if state.board._state.marked[task.id] then tasks[#tasks + 1] = task end end
            else
              tasks[1] = state.board:selected_task()
            end
            local references = {}
            for _, task in ipairs(tasks) do references[#references + 1] = "[task:" .. task.id .. "] " .. task.title end
            local reference = table.concat(references, "\n")
            win:close()
            open_win = nil
            local input, input_err = maki.ui.input()
            if not input then
              maki.notify("Could not reference task in Maki input: " .. tostring(input_err or "input unavailable"), "error", { title = "Kanban" })
              return
            end
            local separator = input.text ~= "" and not input.text:sub(1, input.cursor):match("\n$") and "\n" or ""
            local inserted, edit_err = maki.ui.input_edit({
              start = input.cursor, stop = input.cursor, text = separator .. reference,
              cursor = input.cursor + #separator + #reference,
              version = input.version, session_id = input.session_id,
            })
            if not inserted then
              maki.notify("Could not reference task in Maki input: " .. tostring(edit_err or "input edit failed"), "error", { title = "Kanban" })
            end
            return
          elseif ev.key == "n" then
            state.task = Task.new_create(state.width, state.height)
            state.view = "task"
            buf:set_lines(state.task:render())
          elseif ev.key == "<CR>" or ev.key == "<Enter>" then
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
          local action = state.task:handle_key(ev.key, store)
          if action == "quit" then
            return
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
      end
    end
  end)
  win:close()
  open_win = nil
  if not ok then error(loop_err) end
end

return M
