--# selene: allow(undefined_variable, unscoped_variables)
fake.result = board({ "task-1" })
fake.update_error = "detail status write failed"
observed = {}
local status_lists = fake.calls
run({
  { type = "key", key = "<CR>" },
  { type = "key", key = "j" },
  { type = "key", key = ">" },
  function()
    observed.failed_status = snapshot()
    check(
      fake.calls == status_lists + 1 and last_buf.lines[1][1][2].fg == "#7799ff" and not last_win.closed,
      "failed detail status does not reload or recolor"
    )
    fake.update_error = nil
  end,
  { type = "key", key = ">" },
  function()
    observed.retry_status = snapshot()
    check(fake.calls == status_lists + 1, "successful status retry does not reload hidden board")
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.back = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.failed_status:find("Error: detail status write failed", 1, true)
    and observed.failed_status:find("▸ Description", 1, true)
    and observed.retry_status:find("▸ Description", 1, true)
    and not observed.retry_status:find("Error:", 1, true)
    and observed.back:find("DOING · 1", 1, true),
  "detail status failure retains focus and retry updates selected board card"
)

for _, entry in ipairs({ "<CR>", "n" }) do
  fake.result = { tasks = { ["task-1"] = { title = "Literal", description = "", status = "todo" } } }
  local updates, creates = #fake.updates, fake.creates
  observed = {}
  run({
    { type = "key", key = entry },
    { type = "key", key = "<CR>" },
    { type = "key", key = "q" },
    function()
      observed.literal = snapshot()
      check(
        not last_win.closed and #fake.updates == updates and fake.creates == creates,
        "title q remains literal without Store write"
      )
    end,
    { type = "key", key = "<Esc>" },
    function()
      observed.cancel = snapshot()
    end,
    { type = "key", key = "<CR>" },
    { type = "key", key = "q" },
    { type = "key", key = "<Enter>" },
    function()
      observed.saved = snapshot()
    end,
    { type = "key", key = "q" },
  })
  check(
    observed.literal:find(entry == "n" and "▸ q" or "Literalq", 1, true)
      and not observed.cancel:find(entry == "n" and "▸ q" or "Literalq", 1, true)
      and observed.saved:find(entry == "n" and "▸ q" or "Literalq", 1, true),
    "title integration Esc discards literal q and Enter saves"
  )
  check(
    #fake.updates == updates + (entry == "n" and 0 or 1) and fake.creates == creates,
    "Enter saves only Detail title or local Create draft"
  )
end

reset_editor()
maki.ui.open_editor = function(path)
  editor.files[path] = "Preserved body"
  return 0
end
fake.result = board({ "task-1" })
fake.create_error = "create retry failed"
observed = {}
local attempts = fake.creates
run({
  { type = "key", key = "n" },
  { type = "key", key = "<CR>" },
  { type = "paste", text = "Preserved title" },
  { type = "key", key = "<CR>" },
  { type = "key", key = "j" },
  { type = "key", key = "<Enter>" },
  function()
    check(
      fake.creates == attempts and snapshot():find("Preserved body", 1, true),
      "Create description Enter edits draft without creating"
    )
  end,
  { type = "key", key = "s" },
  function()
    observed.failure = snapshot()
    fake.create_error = nil
  end,
  { type = "key", key = "s" },
  function()
    observed.success = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    check((selected_title() or ""):find("▸ Preserved title", 1, true), "Create retry returns to selected new task")
  end,
  { type = "key", key = "q" },
})
check(
  observed.failure:find("─ Create", 1, true)
    and observed.failure:find("Preserved title", 1, true)
    and observed.failure:find("Preserved body", 1, true)
    and observed.failure:find("Error: create retry failed", 1, true),
  "Create failure integration preserves both drafts"
)
check(
  fake.creates == attempts + 2
    and observed.success:find("─ Task", 1, true)
    and not observed.success:find("Error:", 1, true)
    and fake.result.tasks["task-2"].title == "Preserved title"
    and fake.result.tasks["task-2"].description == "Preserved body"
    and fake.result.tasks["task-2"].status == "todo",
  "Create retry becomes todo Detail with preserved drafts"
)
maki.ui.open_editor = description_open
reset_editor()
