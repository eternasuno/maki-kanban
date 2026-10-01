--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1", "task-2", "task-3" })
for _, key in ipairs({ "h", "l", "<Left>", "<Right>" }) do
  local column_multi = Board.new(90, 27)
  column_multi:reload(fake)
  column_multi:handle_key("<Space>", fake)
  column_multi:handle_key("j", fake)
  column_multi:handle_key("<Space>", fake)
  column_multi:handle_key(key, fake)
  check(
    not next(column_multi._state.marked) and column_multi._state.focused_column ~= 1,
    "column navigation clears all multiselect marks: " .. key
  )
end
for _, status in ipairs({ { "todo", "#7799ff" }, { "doing", "#ffaa00" }, { "done", "#00cc66" } }) do
  fake.result = board({ "task-1", "task-2" })
  fake.result.tasks["task-1"].status = status[1]
  fake.result.tasks["task-2"].status = status[1]
  local colored_multi = Board.new(90, 27)
  colored_multi:reload(fake)
  colored_multi:select_task("task-1")
  colored_multi:handle_key("<Space>", fake)
  colored_multi:handle_key("j", fake)
  local spans = colored_multi:render()
  local content = (colored_multi._state.focused_column - 1) * 4 + 3
  check(
    spans[3][content][2].fg == status[2]
      and spans[4][content][2].fg == status[2]
      and spans[3][content][2].bold
      and spans[4][content][2].bold,
    "marks and cursor share column color in " .. status[1]
  )
end
fake.result = board({ "task-1", "task-2", "task-3" })
local multi = Board.new(90, 27)
multi:reload(fake)
check(multi:handle_key("<Space>", fake) and multi._state.marked["task-1"], "canonical Space marks the focused task")
check(
  multi:render()[3][3][2].fg == "#7799ff" and multi:render()[3][3][1]:find("▸", 1, true),
  "marked cursor task keeps column color and cursor marker"
)
multi:handle_key("j", fake)
multi:handle_key("<Space>", fake)
multi:handle_key("j", fake)
check(
  multi._state.marked["task-1"] and multi._state.marked["task-2"] and not multi._state.marked["task-3"],
  "navigation preserves multiple marks independently of cursor"
)
for index = 1, 2 do
  local span = multi:render()[index + 2][3]
  check(
    span[2].fg == "#7799ff"
      and span[2].fg == multi:render()[5][3][2].fg
      and span[2].bold
      and not span[1]:find("▸", 1, true),
    "marked task shares cursor color after cursor moves"
  )
end
for _, line in ipairs(multi:render()) do
  check(
    not text(line):find("[ ]", 1, true) and not text(line):find("[x]", 1, true),
    "board rows and empty cells omit checkboxes"
  )
end
multi:handle_key("k", fake)
multi:handle_key("<Space>", fake)
multi:handle_key("j", fake)
check(
  not multi._state.marked["task-2"] and multi:render()[4][3][2].fg == "#eeeeee" and not multi:render()[4][3][2].bold,
  "Space unmarks task and restores plain style after navigation"
)
multi:handle_key("g", fake)
multi:handle_key(" ", fake)
check(not next(multi._state.marked), "literal Space remains compatible and toggles marks off")
multi:handle_key("<Space>", fake)
multi:handle_key("j", fake)
multi:handle_key("<Space>", fake)
multi:handle_key("j", fake)
multi:handle_key(">", fake)
check(
  fake.result.tasks["task-1"].status == "doing"
    and fake.result.tasks["task-2"].status == "doing"
    and fake.result.tasks["task-3"].status == "doing",
  "batch move includes marks and cursor task"
)
multi:handle_key("d", fake)
check(#multi._state.pending_delete_ids == 3, "batch delete confirms the effective selection")
multi:handle_key("y", fake)
check(
  not fake.result.tasks["task-1"]
    and not fake.result.tasks["task-2"]
    and not fake.result.tasks["task-3"]
    and not next(multi._state.marked),
  "batch deletion removes effective selection and cleans marks"
)

fake.result = board({ "task-1", "task-2", "task-3" })
_ENV.input_snapshot = { text = "", cursor = 0, version = 7, session_id = "session-1" }
run({
  { type = "key", key = "<Space>" },
  { type = "key", key = "j" },
  { type = "key", key = "<Space>" },
  { type = "key", key = "j" },
  { type = "key", key = "a" },
})
check(
  input_edit_opts.text == "[task:task-1] Title task-1\n[task:task-2] Title task-2\n[task:task-3] Title task-3",
  "references include marks and cursor task in board order"
)
_ENV.input_snapshot = nil
fake.result = board({ "task-1", "task-2" })
local effective = Board.new(90, 27)
effective:reload(fake)
check(#effective:selected_tasks() == 1, "unmarked cursor remains selected")
effective:handle_key("<Space>", fake)
check(#effective:selected_tasks() == 1, "marked cursor is naturally deduplicated")
effective:handle_key("j", fake)
local effective_tasks = effective:selected_tasks()
check(
  #effective_tasks == 2 and effective_tasks[1].id == "task-1" and effective_tasks[2].id == "task-2",
  "effective selection is stable union of cursor and marks"
)
local effective_updates, effective_lists = #fake.updates, fake.calls
effective:handle_key("<", fake)
check(
  #fake.updates == effective_updates
    and fake.calls == effective_lists
    and effective._state.focused_column == 1
    and effective._state.marked["task-1"]
    and #effective:selected_tasks() == 2,
  "boundary move preserves effective selection without store calls"
)
fake.update_error = "union move failed"
effective:handle_key(">", fake)
check(
  effective._state.focused_column == 1
    and effective:selected_task().id == "task-2"
    and effective._state.marked["task-1"]
    and not effective._state.marked["task-2"]
    and #effective:selected_tasks() == 2
    and fake.calls == effective_lists,
  "failed union move preserves focus and exact marks"
)
fake.update_error = nil
effective_updates = #fake.updates
effective:handle_key(">", fake)
check(
  #fake.updates == effective_updates + 1
    and fake.result.tasks["task-1"].status == "doing"
    and fake.result.tasks["task-2"].status == "doing"
    and effective._state.focused_column == 2
    and effective:selected_task().id == "task-2",
  "two-task reproduction moves both once and follows second cursor"
)
check(
  effective._state.marked["task-1"] and effective._state.marked["task-2"],
  "successful batch move retains entire effective set as marks"
)
effective:handle_key("<Space>", fake)
check(
  not effective._state.marked["task-2"]
    and effective._state.marked["task-1"]
    and #effective:selected_tasks() == 2
    and effective:selected_task().status == "doing",
  "Space after move toggles only target mark without cross-column selection"
)
effective:handle_key(">", fake)
check(
  effective._state.focused_column == 3
    and #effective:selected_tasks() == 2
    and fake.result.tasks["task-1"].status == "done",
  "repeated batch move keeps effective set"
)
effective:handle_key("<Space>", fake)
effective:handle_key("d", fake)
local frozen_ids = effective._state.pending_delete_ids
check(
  #frozen_ids == 2 and frozen_ids[1] == "task-1" and frozen_ids[2] == "task-2",
  "delete freezes union ids in board order"
)
effective:handle_key("<Space>", fake)
check(
  not effective._state.pending_delete_ids
    and effective._state.marked["task-1"]
    and not effective._state.marked["task-2"]
    and #effective:selected_tasks() == 2,
  "delete cancellation consumes Space and preserves selection"
)
effective:handle_key("d", fake)
frozen_ids = effective._state.pending_delete_ids
fake.delete_error = "union delete failed"
effective:handle_key("y", fake)
check(
  fake.deleted_ids == frozen_ids
    and effective._state.focused_column == 3
    and effective._state.marked["task-1"]
    and not effective._state.marked["task-2"]
    and #effective:selected_tasks() == 2,
  "failed delete uses frozen union and preserves focus and marks"
)
fake.delete_error = nil
effective:select_task("task-1")
check(effective._state.marked["task-1"], "same-column select_task preserves marks")
fake.result.tasks["task-1"].status = "todo"
effective:reload(fake)
check(
  not next(effective._state.marked)
    and #effective:selected_tasks() == 1
    and effective:selected_tasks()[1].id == "task-2",
  "external status change reload removes cross-column marks"
)
effective:handle_key("<Space>", fake)
effective:select_task("task-1")
check(
  not next(effective._state.marked) and effective._state.focused_column == 1,
  "cross-column select_task clears marks"
)
effective:handle_key("<Space>", fake)
fake.error = "union reload failed"
effective:reload(fake)
check(
  not next(effective._state.marked) and #effective:selected_tasks() == 0,
  "failed reload clears marks and invalid effective selection"
)
fake.error = nil
for _, reload_failure in ipairs({ true, false }) do
  fake.result = board({ "task-1", "task-2" })
  effective:reload(fake)
  effective:select_task("task-1")
  effective:handle_key("<Space>", fake)
  effective:handle_key("j", fake)
  local list = fake.list
  fake.list = function(self)
    if reload_failure then
      return nil, "post-move reload failed"
    end
    self.result.tasks["task-2"].status = "todo"
    return list(self)
  end
  effective:handle_key(">", fake)
  fake.list = list
  check(
    not next(effective._state.marked) and effective._state.focused_column == 1,
    "post-move failed or mismatched reload never restores target marks: " .. tostring(reload_failure)
  )
end
fake.result = board({ "task-1", "task-2" })
run({
  { type = "key", key = "<Space>" },
  { type = "key", key = "j" },
  { type = "key", key = "<Enter>" },
  function()
    check(
      snapshot():find("Title task-2", 1, true) and not snapshot():find("Title task-1", 1, true),
      "Enter opens only cursor detail despite marks"
    )
  end,
  { type = "key", key = "q" },
})
