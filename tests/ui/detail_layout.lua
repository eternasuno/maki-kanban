--# selene: allow(undefined_variable, unscoped_variables)
local detail = Task.new({ title = "Short", status = "todo", description = "one\ntwo" }, 16, 12)
local detail_lines = detail:render()
check(
  row(detail_lines, 2):find("▸ Short", 1, true) and row(detail_lines, 3) == "│" .. string.rep(" ", 14) .. "│",
  "single-line title reserves second row"
)
check(
  row(detail_lines, 4) == "│" .. string.rep(" ", 14) .. "│" and row(detail_lines, 5):find("Description", 1, true),
  "description label follows blank field gap without status row"
)
check(
  row(detail_lines, 6):find("one", 1, true)
    and row(detail_lines, 7):find("two", 1, true)
    and row(detail_lines, 8) == "└" .. string.rep("─", 14) .. "┘",
  "description preserves newlines within pane"
)
check(
  row(detail_lines, 9) == string.rep(" ", 16)
    and row(detail_lines, 10) == "┌" .. string.rep("─", 14) .. "┐"
    and width(row(detail_lines, 11)) == 16
    and row(detail_lines, 12) == "└" .. string.rep("─", 14) .. "┘",
  "detail reserves blank gap and three-row bordered footer"
)

for _, status in ipairs({ { "todo", "#7799ff" }, { "doing", "#ffaa00" }, { "done", "#00cc66" } }) do
  local colored = Task.new({ title = "Color task", status = status[1], description = "body" }, 30, 12)
  local lines = colored:render()
  check(
    lines[1][1][2].fg == status[2]
      and lines[8][1][2].fg == status[2]
      and lines[2][1][2].fg == status[2]
      and lines[2][3][2].fg == status[2],
    status[1] .. " colors top bottom and side borders"
  )
  check(
    lines[2][2][2].fg == "#eeeeee" and lines[2][2][2].bold and not lines[5][2][2].bold,
    "focused title is bold foreground without status coloring"
  )
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      for _, span in ipairs(line) do
        check(not span[2].bg, "detail has no background highlighting")
      end
    end
    check(
      not text(line):find("Todo", 1, true)
        and not text(line):find("Doing", 1, true)
        and not text(line):find("Done", 1, true),
      "detail omits status text"
    )
  end
end
local cjk = Task.new(
  { title = "中文中文中文中文中文中文中文", status = "doing", description = "你好世界你好世界" },
  12,
  13
)
local cjk_lines = cjk:render()
check(
  row(cjk_lines, 2):find("中文中文", 1, true)
    and row(cjk_lines, 3):find("…", 1, true)
    and not row(cjk_lines, 4):find("中文", 1, true),
  "CJK title wraps into at most two truncated rows"
)
check(
  row(cjk_lines, 6):find("你好世界", 1, true) and row(cjk_lines, 7):find("你好世界", 1, true),
  "CJK description wraps at display width after marker gutter"
)
for _, line in ipairs(cjk_lines) do
  check(width(text(line)) == 12, "CJK detail row fits exact width")
end
local done = Task.new({ title = "Finished task", status = "done", description = "" }, 12, 12)
check(row(done:render(), 6) == "│" .. string.rep(" ", 10) .. "│", "empty description has no placeholder")
local long = Task.new({
  title = "Scrolling",
  status = "todo",
  description = table.concat({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }, "\n"),
}, 12, 12)
check(
  long.viewport == 2 and row(long:render(), 6):find("a", 1, true),
  "description begins at top with height-minus-ten viewport"
)
check(
  long:handle_key("G")
    and long.offset == 8
    and row(long:render(), 6):find("i", 1, true)
    and row(long:render(), 7):find("j", 1, true),
  "G reaches exact final description page"
)
long:resize(12, 15)
check(
  long.viewport == 5 and long.offset == 5 and row(long:render(), 6):find("f", 1, true),
  "resize clamps description offset"
)
check(
  long:handle_key("<Esc>") == "back"
    and long:handle_key("q") == "quit"
    and long:handle_key("<C-c>") == "quit"
    and long:handle_key("b") == false,
  "detail handles back and quit with legacy b ignored"
)
