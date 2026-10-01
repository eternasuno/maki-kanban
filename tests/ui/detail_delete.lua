--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1", "task-2", "task-3" })
local deleting = Task.new({ id = "task-2", title = "Delete me", description = "", status = "todo" }, 80, 12)
local deletes_before = fake.deletes or 0
for _, key in ipairs({
  "<Esc>",
  "<C-c>",
  "n",
  "b",
  "q",
  "<CR>",
  "<Enter>",
  "j",
  "k",
  "<Down>",
  "<Up>",
  "<Tab>",
  "<S-Tab>",
  "J",
  "K",
  "g",
  "G",
  "<",
  ">",
  "?",
  "d",
  "Y",
}) do
  check(deleting:handle_key("d", fake) == true and deleting.confirm_delete, "d enters delete confirmation")
  check(row(deleting:render(), 11):find('Delete "Delete me"?  y/N', 1, true), "confirmation prompt rendered")
  local focus, offset, updates, creates = deleting.focused_field, deleting.offset, #fake.updates, fake.creates
  local action = deleting:handle_key(key, fake)
  check(
    action == true
      and deleting.focused_field == focus
      and deleting.offset == offset
      and #fake.updates == updates
      and fake.creates == creates
      and not deleting.editing
      and not deleting.help_open,
    "confirmation consumes key without other actions: " .. key
  )
  check(
    not deleting.confirm_delete and (fake.deletes or 0) == deletes_before and fake.result.tasks["task-2"],
    "non-y cancels deletion without executing key"
  )
end
for _, err in ipairs({ "malformed JSON", "task not found: task-2", "write failed" }) do
  fake.delete_error = err
  deleting:handle_key("d", fake)
  check(
    deleting:handle_key("y", fake) == true and deleting.error == err and not deleting.confirm_delete,
    "delete failure stays in detail with retryable error"
  )
  check(row(deleting:render(), 11):find(err, 1, true), "delete failure rendered")
end
fake.delete_error = nil
deleting:handle_key("d", fake)
check(
  deleting:handle_key("y", fake) == "deleted" and fake.deleted_id == "task-2" and not fake.result.tasks["task-2"],
  "confirmed delete calls Store and returns deleted action"
)
local no_delete_create = Task.new_create(80, 12)
check(
  no_delete_create:handle_key("d", fake) == false and not no_delete_create.confirm_delete,
  "creation has no delete action"
)

fake.result = board({ "task-1", "task-2", "task-3" })
local delete_lists = fake.calls
observed = {}
run({
  { type = "key", key = "j" },
  { type = "key", key = "<Enter>" },
  { type = "key", key = "d" },
  { type = "key", key = "<Esc>" },
  function()
    observed.cancel = snapshot()
  end,
  { type = "key", key = "d" },
  { type = "key", key = "n" },
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  function()
    observed.deleted = snapshot()
    observed.selected = selected_title()
  end,
  { type = "key", key = "q" },
})
check(
  observed.cancel:find("Title task-2", 1, true) and not observed.cancel:find('Delete "', 1, true),
  "Esc confirmation cancellation does not close detail window"
)
check(
  fake.calls == delete_lists + 2
    and observed.deleted:find("TODO · 2", 1, true)
    and not observed.deleted:find("Title task-2", 1, true),
  "deleted action reloads and returns to board"
)
check(observed.selected:find("Title task-3", 1, true), "deleted middle task falls back to next task at same index")

fake.result = board({ "task-1", "task-2", "task-3", "task-4", "task-5" })
delete_lists, deletes_before = fake.calls, fake.deletes
observed = {}
run({
  { type = "resize", width = 90, height = 10 },
  { type = "key", key = "G" },
  function()
    observed.scrolled = snapshot()
    observed.before = selected_title()
  end,
  { type = "key", key = "<Enter>" },
  function()
    observed.detail = snapshot()
  end,
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  function()
    observed.deleted = snapshot()
    observed.selected = selected_title()
    observed.closed = last_win.closed
  end,
  { type = "key", key = "<Enter>" },
  function()
    observed.fallback = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.before
    and observed.before:find("Title task-5", 1, true)
    and not observed.scrolled:find("Title task-1", 1, true)
    and observed.detail:find("─ Task", 1, true)
    and observed.detail:find("Title task-5", 1, true),
  "final task deletion starts from scrolled Board and opens selected Detail"
)
check(
  fake.deletes == deletes_before + 1
    and fake.deleted_id == "task-5"
    and not fake.result.tasks["task-5"]
    and fake.result.tasks["task-1"]
    and fake.result.tasks["task-4"]
    and fake.calls == delete_lists + 2,
  "final Detail task deletion retains earlier tasks and reloads once"
)
check(
  not observed.closed
    and observed.deleted:find("TODO · 4", 1, true)
    and not observed.deleted:find("─ Task", 1, true)
    and not observed.deleted:find("Title task-5", 1, true)
    and observed.selected
    and observed.selected:find("Title task-4", 1, true),
  "final Detail task deletion returns to Board with visible preceding fallback"
)
check(
  observed.deleted:find("Title task-3", 1, true)
    and not observed.deleted:find("Title task-2", 1, true)
    and observed.fallback:find("─ Task", 1, true)
    and observed.fallback:find("Title task-4", 1, true),
  "scrolled Board clamps viewport after final deletion and fallback opens valid Detail"
)

fake.result = board({ "task-1" })
run({
  { type = "key", key = "<Enter>" },
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  { type = "key", key = "<Enter>" },
  { type = "key", key = "q" },
})
check(
  snapshot():find("TODO · 0", 1, true) and selected_title() == nil,
  "deleting last task leaves legal empty board selection"
)
fake.result = board({ "task-1" })
fake.delete_error = "disk write failed"
observed = {}
run({
  { type = "key", key = "<Enter>" },
  { type = "key", key = "d" },
  { type = "key", key = "y" },
  function()
    observed.failure = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.back = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.failure:find("disk write failed", 1, true)
    and observed.failure:find("─ Task", 1, true)
    and observed.back:find("TODO · 1", 1, true),
  "event loop keeps failed delete detail and permits returning to board"
)
fake.delete_error = nil
