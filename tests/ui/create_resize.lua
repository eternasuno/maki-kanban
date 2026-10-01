--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1" })
local cursor_create = Task.new_create(9, 12)
cursor_create:handle_key("<CR>", fake)
check(
  cursor(cursor_create).text == " " and not row(cursor_create:render(), 2):find("Title", 1, true),
  "empty create shows cursor without placeholder"
)
cursor_create:handle_paste("abcdefghijklmnop")
check(
  cursor(cursor_create).row == 3 and cursor_create.title_offset == 2,
  "long title follows end cursor across two rows"
)
check(
  row(cursor_create:render(), 2):find("klmno", 1, true) and row(cursor_create:render(), 3):find("p ", 1, true),
  "long title viewport retains two styled content rows"
)
cursor_create:handle_key("<Home>", fake)
check(
  cursor(cursor_create).row == 2 and cursor(cursor_create).text == "a" and cursor_create.title_offset == 0,
  "Home scrolls long title back to start"
)
for _ = 1, 10 do
  cursor_create:handle_key("<Right>", fake)
end
check(
  cursor(cursor_create).row == 3 and cursor(cursor_create).text == "k" and cursor_create.title_offset == 1,
  "arrows scroll long title viewport"
)
cursor_create:handle_key("<End>", fake)
cursor_create:resize(9, 7)
check(cursor(cursor_create).row == 2, "one visible title row still tracks cursor")
cursor_create:resize(30, 12)
check(cursor(cursor_create).row == 2 and cursor_create.title_offset == 0, "widening clamps title viewport")
cursor_create:handle_key("<CR>", fake)
check(not cursor(cursor_create), "create title completion removes cursor")

local resized_create = Task.new_create(80, 12)
resized_create:handle_key("<CR>", fake)
resized_create:handle_paste("中文创建标题中文创建标题")
for _, size in ipairs({
  { 20, 10 },
  { 9, 12 },
  { 6, 12 },
  { 5, 12 },
  { 4, 12 },
  { 3, 12 },
  { 2, 12 },
  { 3, 4 },
  { 1, 1 },
  { 0, 0 },
  { 80, 12 },
}) do
  resized_create:resize(size[1], size[2])
  check(#resized_create:render() == size[2], "create resize respects height")
  for _, line in ipairs(resized_create:render()) do
    check(width(text(line)) <= size[1], "create resize stays within display width")
  end
end
for _, size in ipairs({ 20, 9, 6, 5, 80 }) do
  resized_create:resize(size, 12)
  resized_create:handle_key("<Home>", fake)
  local current = cursor(resized_create)
  check(current and current.text == (size == 5 and " " or "中"), "CJK Home cursor fits available content width")
  resized_create:handle_key("<Right>", fake)
  check(cursor(resized_create).text == (size == 5 and " " or "文"), "CJK arrow moves by codepoint")
  resized_create:handle_key("<End>", fake)
  check(cursor(resized_create).text == " ", "CJK end cursor remains visible after resize")
  for _, line in ipairs(resized_create:render()) do
    check(width(text(line)) <= size, "CJK cursor movement stays within bounds")
  end
end
check(
  resized_create.title_input:value() == "中文创建标题中文创建标题",
  "create resize preserves CJK title input"
)
run({
  { type = "key", key = "n" },
  { type = "paste", text = "ignored" },
  { type = "resize", width = 1, height = 1 },
  function()
    check(#last_buf.lines == 1 and width(text(last_buf.lines[1])) <= 1, "event-loop resize renders bounded create view")
  end,
  { type = "key", key = "<Esc>" },
  { type = "key", key = "<Esc>" },
  { type = "key", key = "q" },
})

fake.create_error = "disk write failed"
observed = {}
run({
  { type = "key", key = "n" },
  { type = "paste", text = "ignored" },
  { type = "key", key = "<Enter>" },
  { type = "paste", text = "Keep this title" },
  { type = "key", key = "<CR>" },
  { type = "key", key = "<Tab>" },
  { type = "key", key = "s" },
  function()
    observed.failure = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.board = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.failure:find("Keep this title", 1, true)
    and observed.failure:find("disk write failed", 1, true)
    and observed.failure:find("─ Create", 1, true),
  "event loop keeps create view and input after Store failure"
)
check(observed.board:find("TODO", 1, true) ~= nil, "failed create can be cancelled back to board")
fake.create_error = nil
reset_editor()
editor.exit_code = 1
local cancelled_description = Task.new_create(80, 12)
cancelled_description:handle_key("<CR>", fake)
cancelled_description:handle_paste("Draft")
cancelled_description:handle_key("<CR>", fake)
cancelled_description:handle_key("<Tab>", fake)
cancelled_description:handle_key("<CR>", fake)
check(
  cancelled_description.task.description == ""
    and #editor.removes == 1
    and cancelled_description.error == "editor exited with status 1",
  "cancelled create description editor preserves draft and cleans file"
)
reset_editor()
