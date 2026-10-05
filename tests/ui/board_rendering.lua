--# selene: allow(undefined_variable, unscoped_variables)
local regression_ids = {}
for i = 1, 30 do
  regression_ids[i] = "task-" .. i
end
fake.result = board(regression_ids)
fake.result.tasks["task-1"].title = "中文 first"
fake.result.tasks["task-2"].title = "中文 second"
local phase = Board.new(90, 12)
phase:reload(fake)
check(
  width("▸") == 1 and width("▸ 中文") == 6 and truncate("▸ 中文", 4).head == "▸ 中",
  "mock treats marker as one cell while preserving CJK widths"
)
local phase_lines = phase:render()
check(
  phase_lines[3][3][1]:find("▸ 中文", 1, true) and phase_lines[4][3][1]:find("  中文", 1, true),
  "selected and unselected titles use a cursor without checkbox indicators"
)
check(
  phase_lines[3][3][2].fg == "#7799ff"
    and phase_lines[3][3][2].bold
    and not phase_lines[3][3][2].bg
    and phase_lines[4][3][2].fg == "#eeeeee"
    and not phase_lines[4][3][2].bold
    and not phase_lines[4][3][2].bg,
  "marker title styling is accent bold without background only on selection"
)
for _, line_number in ipairs({ 2, 3, 7 }) do
  local spans = phase_lines[line_number]
  check(spans[2][2].fg == "#7799ff" and spans[2][2].bold, "focused top side and bottom borders use accent bold")
end
check(
  phase_lines[2][4][2].fg == "#ffaa00"
    and not phase_lines[2][4][2].bold
    and phase_lines[3][6][2].fg == "#eeeeee"
    and not phase_lines[3][6][2].bold
    and phase_lines[7][4][2].fg == "#eeeeee"
    and not phase_lines[7][4][2].bold,
  "inactive headers use status color while side and bottom borders retain foreground without bold"
)
local header_colors = { "#7799ff", "#ffaa00", "#00cc66" }
local header_titles = { "TODO · 30", "DOING · 0", "DONE · 0" }
for focused = 1, 3 do
  local lines = phase:render()
  for column, color in ipairs(header_colors) do
    local span = lines[2][column * 2]
    check(
      span[1]:find(header_titles[column], 1, true)
        and span[2].fg == color
        and span[2].bold == (column == focused)
        and not span[2].bg,
      "all headers retain status color and only focused header is bold: " .. focused .. "/" .. column
    )
  end
  if focused < 3 then
    phase:handle_key("l", fake)
  end
end
phase:handle_key("h", fake)
phase:handle_key("h", fake)
phase:resize(20, 12)
for focused, color in ipairs(header_colors) do
  local lines = phase:render()
  check(
    lines[2][2][1]:find(header_titles[focused], 1, true)
      and lines[2][2][2].fg == color
      and lines[2][2][2].bold
      and not lines[2][2][2].bg,
    "narrow header uses focused status color: " .. focused
  )
  for _, line in ipairs(lines) do
    check(width(text(line)) <= 20, "status-colored narrow board respects width")
  end
  if focused < 3 then
    phase:handle_key("l", fake)
  end
end
phase:resize(90, 12)
phase:handle_key("h", fake)
phase:handle_key("h", fake)
phase:handle_key("G", fake)
check(
  phase:selected_task().id == "task-30"
    and phase._state.offsets[1] == 26
    and row(phase:render(), 6):find("▸ Title task-30", 1, true),
  "G reaches last task and exact final viewport row"
)
phase:handle_key("g", fake)
check(phase:selected_task().id == "task-1" and phase._state.offsets[1] == 0, "g restores first task and offset")
for _, key in ipairs({ "1", "2", "3", "H", "L" }) do
  local lines, calls, updates = phase:render(), fake.calls, #fake.updates
  check(
    phase:handle_key(key, fake) == false
      and phase:render() == lines
      and phase._state.focused_column == 1
      and phase:selected_task().id == "task-1"
      and fake.calls == calls
      and #fake.updates == updates,
    "removed Board shortcut is ignored: " .. key
  )
end
for _, height in ipairs({ 3, 4, 5, 6, 7, 8, 9, 12, 27 }) do
  phase:resize(90, height)
  phase:handle_key("G", fake)
  local lines = phase:render()
  local footer_row = height >= 8 and height - 2 or height - 1
  check(
    #lines == height
      and row(lines, footer_row):find("NORMAL", 1, true)
      and row(lines, footer_row):find("? help   q quit", 1, true),
    "footer content occupies exact row at height " .. height
  )
  check(
    row(lines, footer_row - 1):find("┌", 1, true) and row(lines, footer_row + 1):find("└", 1, true),
    "footer reserves three bordered rows at height " .. height
  )
  if height >= 8 then
    check(
      row(lines, 1) == string.rep(" ", 90)
        and row(lines, height) == string.rep(" ", 90)
        and row(lines, height - 4) == string.rep(" ", 90)
        and row(lines, height - 5):find("└", 1, true),
      "vertical padding and footer gap define exact column boundary at height " .. height
    )
    if height > 8 then
      check(
        phase._state.offsets[1] == 30 - (height - 8) and row(lines, height - 6):find("▸ Title task-30", 1, true),
        "column viewport is height minus eight at height " .. height
      )
    end
  end
  for _, line in ipairs(lines) do
    check(width(text(line)) == 90, "footer layout has exact display width")
  end
end
phase:resize(90, 12)
phase:handle_key("g", fake)
phase:handle_key("j", fake)
phase:handle_key("d", fake)
check(
  row(phase:render(), 10):find("Delete 1 task(s)?  y/N", 1, true)
    and phase:render()[10][3][2].fg == "#ff4444"
    and phase:render()[10][3][2].bold,
  "titled CJK delete prompt uses bold error styling in footer"
)
phase:handle_key("n", fake)
fake.error = "reload failed"
phase:reload(fake)
check(
  row(phase:render(), 10):find("Error: reload failed", 1, true)
    and phase:render()[10][3][2].fg == "#ff4444"
    and phase:render()[10][3][2].bold,
  "reload errors use Error prefix and bold error footer styling"
)
fake.error = nil
phase:reload(fake)
phase:handle_key("G", fake)
