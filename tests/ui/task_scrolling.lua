--# selene: allow(undefined_variable, unscoped_variables)
for _, height in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 27 }) do
  local state = Task.new({ title = "Viewport", description = string.rep("line\n", 40), status = "todo" }, 90, height)
  local gap = height >= 6 and 1 or 0
  check(
    state.footer_height == math.min(3, height)
      and state.footer_gap == gap
      and state.pane_height == height - math.min(3, height) - gap
      and state.viewport == math.max(0, state.pane_height - 6),
    "Task layout reserves exact footer gap and viewport at height " .. height
  )
  state:handle_key("G", fake)
  check(
    state.offset == math.max(0, #state.description_lines - state.viewport) and #state:render() == height,
    "Task bottom scroll clamps to viewport at height " .. height
  )
  for _, line in ipairs(state:render()) do
    check(width(text(line)) == 90, "Task layout fits exact width")
  end
  if height >= 3 then
    check(
      row(state:render(), height - 2) == "┌" .. string.rep("─", 88) .. "┐"
        and row(state:render(), height - 1):find("NORMAL", 1, true)
        and row(state:render(), height) == "└" .. string.rep("─", 88) .. "┘",
      "Task three-row footer remains anchored at bottom"
    )
  end
end
local scroll_focus = Task.new({ title = "Scroll", description = string.rep("line\n", 30), status = "todo" }, 30, 12)
for _, field in ipairs({ "title", "description" }) do
  scroll_focus.focused_field = field
  for _, movement in ipairs({
    { "g", 0 },
    { "J", 1 },
    { "K", 0 },
    { "G", #scroll_focus.description_lines - 2 },
    { "J", #scroll_focus.description_lines - 2 },
    { "g", 0 },
    { "K", 0 },
  }) do
    check(
      scroll_focus:handle_key(movement[1], fake)
        and scroll_focus.offset == movement[2]
        and scroll_focus.focused_field == field,
      "description scroll clamps independently of " .. field .. " focus: " .. movement[1]
    )
  end
end
