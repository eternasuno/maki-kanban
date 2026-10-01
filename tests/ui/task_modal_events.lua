--# selene: allow(undefined_variable, unscoped_variables)
for _, entry in ipairs({ "<CR>", "n" }) do
  fake.result = board({ "task-1" })
  local calls, updates, deletes, creates = fake.calls, #fake.updates, fake.deletes, fake.creates
  local seen = {}
  run({
    { type = "key", key = entry },
    function()
      seen.before = snapshot()
    end,
    { type = "key", key = "?" },
    function()
      seen.help = snapshot()
    end,
    { type = "key", key = "q" },
    { type = "key", key = "s" },
    { type = "key", key = "d" },
    { type = "key", key = ">" },
    function()
      seen.consumed = snapshot()
      check(not last_win.closed, "Task help consumes q without closing event loop")
    end,
    { type = "resize", width = 1, height = 1 },
    function()
      check(
        #last_buf.lines == 1 and row(last_buf.lines, 1) == "?",
        "Task help event-loop narrow resize remains visible"
      )
    end,
    { type = "resize", width = 90, height = 27 },
    { type = "key", key = "<Esc>" },
    function()
      seen.dismissed = snapshot()
    end,
    { type = "key", key = "?" },
    { type = "key", key = "?" },
    function()
      seen.toggled = snapshot()
    end,
    { type = "key", key = "<Esc>" },
    function()
      seen.back = snapshot()
    end,
    { type = "key", key = "q" },
  })
  check(
    seen.help:find("Keybindings", 1, true)
      and seen.consumed == seen.help
      and seen.dismissed == seen.before
      and seen.toggled == seen.before
      and seen.back:find("TODO · 1", 1, true),
    "Task help integration dismisses and toggles without leaving view before Esc back"
  )
  check(
    fake.calls == calls + 2 and #fake.updates == updates and fake.deletes == deletes and fake.creates == creates,
    "Task help integration has no mutation side effects"
  )
end

for _, key in ipairs({ "q", "<C-c>" }) do
  fake.result = board({ "task-1" })
  local reached = false
  run({
    { type = "key", key = "n" },
    function()
      check(snapshot():find("─ Create", 1, true) and not last_win.closed, "Create is open before quit")
    end,
    { type = "key", key = key },
    function()
      reached = true
    end,
  })
  check(last_win.closed and not reached, key .. " closes Create immediately")
end
for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
  fake.result = board({ "task-1" })
  local reached, deletes = false, fake.deletes
  run({
    { type = "key", key = "<CR>" },
    { type = "key", key = "d" },
    function()
      check(
        snapshot():find('Delete "Title task-1"?  y/N', 1, true),
        "Detail delete modal shows titled prompt before cancellation"
      )
    end,
    { type = "key", key = key },
    function()
      reached = true
      check(
        not last_win.closed and snapshot():find("─ Task", 1, true) and not snapshot():find('Delete "', 1, true),
        "Detail delete consumes " .. key .. " and stays open"
      )
    end,
    { type = "key", key = "q" },
  })
  check(
    reached and fake.deletes == deletes and last_win.closed,
    "Detail modal cancellation does not delete or execute " .. key
  )
end
