--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1", "task-2", "task-3" })
local board_delete = Board.new(80, 12)
board_delete:reload(fake)
board_delete:select_task("task-2")
local board_deletes, board_lists = fake.deletes, fake.calls
board_delete:handle_key("d", fake)
check(
  #board_delete._state.pending_delete_ids == 1
    and board_delete._state.pending_delete_ids[1] == "task-2"
    and fake.deletes == board_deletes
    and fake.calls == board_lists,
  "board d records selected ID without deleting or reloading"
)
check(row(board_delete:render(), 10):find("Delete 1 task(s)?  y/N", 1, true), "board renders batch delete confirmation")
for _, size in ipairs({ { 20, 10 }, { 1, 1 }, { 80, 12 } }) do
  board_delete:resize(size[1], size[2])
  check(
    #board_delete._state.pending_delete_ids == 1
      and board_delete._state.pending_delete_ids[1] == "task-2"
      and #board_delete:render() == size[2],
    "board resize retains pending delete ID and height"
  )
  local footer_row = size[2] >= 8 and size[2] - 2 or size[2] >= 3 and size[2] - 1 or 1
  local prompt = size[1] >= 2
      and size[2] >= 3
      and "│ " .. truncate("Delete 1 task(s)?  y/N", math.max(0, size[1] - 8)).head
    or "D"
  check(
    row(board_delete:render(), footer_row):find(prompt, 1, true),
    "board resize retains fitted titled confirmation prompt"
  )
  for _, line in ipairs(board_delete:render()) do
    check(width(text(line)) <= size[1], "board confirmation resize fits width")
  end
end
board_delete:handle_key("y", fake)
check(
  fake.deleted_id == "task-2"
    and fake.deletes == board_deletes + 1
    and fake.calls == board_lists + 1
    and not board_delete._state.pending_delete_ids,
  "board y deletes recorded ID and reloads once"
)
check(
  board_delete:selected_task().id == "task-3"
    and board_delete._state.focused_column == 1
    and board_delete._state.selected[1] == 2,
  "board middle deletion retains same index and focus"
)
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(
  board_delete:selected_task().id == "task-1" and board_delete._state.selected[1] == 1,
  "board final-index deletion clamps to preceding task"
)
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(
  not board_delete:selected_task() and board_delete._state.selected[1] == 1 and board_delete._state.offsets[1] == 0,
  "board last deletion leaves legal empty selection"
)
board_deletes, board_lists = fake.deletes, fake.calls
board_delete:handle_key("d", fake)
check(
  not board_delete._state.pending_delete_ids and fake.deletes == board_deletes and fake.calls == board_lists,
  "empty board d is a no-op"
)
fake.error = "malformed JSON"
board_delete:reload(fake)
board_delete:handle_key("d", fake)
check(
  not board_delete._state.pending_delete_ids and not board_delete._state.valid and fake.deletes == board_deletes,
  "invalid board d is a no-op"
)
fake.error = nil
fake.result = board({ "task-1", "task-2", "task-3" })
fake.result.tasks["task-2"].status = "doing"
board_delete:reload(fake)
board_delete:select_task("task-2")
for _, key in ipairs({ "n", "<Esc>", "q", "<CR>", "<Enter>", "j", "k", "l", "h", "2", "<", ">", "r", "d", "Y" }) do
  local cards, selected, offsets =
    board_delete._state.cards, board_delete._state.selected[2], board_delete._state.offsets[2]
  board_delete:handle_key("d", fake)
  check(
    board_delete:handle_key(key, fake)
      and not board_delete._state.pending_delete_ids
      and board_delete._state.cards == cards
      and board_delete._state.focused_column == 2
      and board_delete._state.selected[2] == selected
      and board_delete._state.offsets[2] == offsets
      and fake.deletes == board_deletes,
    "board confirmation consumes cancellation key " .. key
  )
end
board_delete:handle_key("d", fake)
board_delete:reload(fake)
check(
  not board_delete._state.pending_delete_ids and not row(board_delete:render(), 10):find("Delete ", 1, true),
  "board reload clears pending confirmation"
)
board_delete:handle_key("h", fake)
board_delete:handle_key("j", fake)
board_lists = fake.calls
local failure_cards, failure_task = board_delete._state.cards, board_delete:selected_task()
fake.delete_error = "delete write failed"
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(
  board_delete._state.cards == failure_cards
    and board_delete:selected_task() == failure_task
    and board_delete._state.focused_column == 1
    and board_delete._state.selected[1] == 2
    and fake.calls == board_lists
    and not board_delete._state.pending_delete_ids,
  "board delete failure retains cards focus selection without reload"
)
check(
  board_delete._state.error_message == "delete write failed"
    and row(board_delete:render(), 10):find("Error: delete write failed", 1, true)
    and board_delete:render()[10][3][2].fg == "#ff4444"
    and board_delete:render()[10][3][2].bold,
  "board delete failure renders bold prefixed error"
)
fake.delete_error = nil
board_delete:handle_key("d", fake)
board_delete:handle_key("y", fake)
check(
  not fake.result.tasks[failure_task.id] and not board_delete._state.error_message,
  "board failed deletion can retry successfully"
)

for _, key in ipairs({ "n", "<Esc>", "q", "<CR>", "<Enter>", "j", "l", ">", "r" }) do
  fake.result = board({ "task-1", "task-2", "task-3" })
  board_deletes, board_lists = fake.deletes, fake.calls
  local reached = false
  run({
    { type = "key", key = "j" },
    { type = "key", key = "d" },
    function()
      check(
        snapshot():find("Delete 1 task(s)?  y/N", 1, true)
          and not snapshot():find("Enter Edit", 1, true)
          and fake.deletes == board_deletes,
        "event loop d confirms on board without immediate deletion"
      )
    end,
    { type = "key", key = key },
    function()
      reached = true
      check(
        snapshot():find("TODO · 3", 1, true)
          and not snapshot():find("Delete 1 task", 1, true)
          and selected_title():find("Title task-2", 1, true),
        "event loop consumes board cancellation " .. key
      )
    end,
    { type = "key", key = "q" },
  })
  check(
    reached and fake.deletes == board_deletes and fake.calls == board_lists + 1,
    "board cancellation does not close create open move or reload: " .. key
  )
end
fake.result = board({ "task-1", "task-2", "task-3" })
board_lists = fake.calls
run({
  { type = "key", key = "j" },
  { type = "key", key = "d" },
  { type = "resize", width = 20, height = 10 },
  function()
    check(
      row(last_buf.lines, 8):find("│ Delete 1 task", 1, true) and snapshot():find("TODO · 3", 1, true),
      "event loop narrow resize retains board confirmation"
    )
  end,
  { type = "key", key = "y" },
  function()
    check(snapshot():find("TODO · 2", 1, true), "event loop board y reloads and falls back at same index")
  end,
  { type = "key", key = "q" },
})
check(
  fake.deleted_id == "task-2" and fake.calls == board_lists + 2,
  "event loop resize retains recorded deletion ID and reloads once"
)
fake.result = board({ "task-1" })
fake.delete_error = "board disk write failed"
board_lists = fake.calls
run({
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  function()
    check(
      snapshot():find("TODO · 1", 1, true)
        and snapshot():find("board disk write failed", 1, true)
        and selected_title():find("Title task-1", 1, true),
      "event loop delete failure stays board with selection and error"
    )
    fake.delete_error = nil
  end,
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  function()
    check(snapshot():find("TODO · 0", 1, true) and not selected_title(), "event loop board retry deletes last card")
  end,
  { type = "key", key = "q" },
})
check(fake.calls == board_lists + 2, "event loop failed board delete does not reload before successful retry")
