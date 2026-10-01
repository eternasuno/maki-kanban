--# selene: allow(undefined_variable, unscoped_variables)
local view = require("kanban.ui.board_view")
local render = view.render
local frames = 0
view.render = function(state)
  frames = frames + 1
  return render(state)
end
fake.result = board({ "task-1", "task-2", "task-3" })
local state = Board.new(90, 12)
state:reload(fake)
check(frames == 0, "Board construction and reload do not render")
local initial = state:render()
check(frames == 1 and state:render() == initial and frames == 1, "Board renders once then reuses frame")
local function final_frame(label, action, verify)
  local count = frames
  action()
  check(frames == count, label .. " does not render intermediate frames")
  local lines = state:render()
  check(frames == count + 1 and verify(lines), label .. " renders exactly one correct final frame")
  check(state:render() == lines and frames == count + 1, label .. " reuses final frame")
end
final_frame("navigation", function()
  state:handle_key("j", fake)
  state:handle_key("j", fake)
  state:handle_key("k", fake)
end, function()
  return state:selected_task().id == "task-2"
end)
final_frame("move with reload and select", function()
  state:handle_key(">", fake)
end, function(lines)
  return state:selected_task().id == "task-2"
    and state._state.focused_column == 2
    and row(lines, 2):find("DOING · 1", 1, true)
end)
final_frame("delete confirmation and delete reload", function()
  state:handle_key("d", fake)
  state:handle_key("y", fake)
end, function(lines)
  return fake.result.tasks["task-2"] == nil and row(lines, 2):find("DOING · 0", 1, true)
end)
final_frame("external reload", function()
  fake.result.tasks["task-1"].title = "External final"
  state:handle_key("h", fake)
  state:reload(fake)
end, function(lines)
  return row(lines, 3):find("External final", 1, true)
end)
final_frame("resize burst", function()
  state:resize(20, 10)
  state:resize(90, 12)
end, function(lines)
  return #lines == 12 and width(row(lines, 3)) == 90
end)
view.render = render
