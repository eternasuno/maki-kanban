--# selene: allow(undefined_variable, unscoped_variables)
for _, keys in ipairs({
  {},
  { "?" },
  { "<CR>" },
  { "<CR>", "<CR>" },
  { "n" },
  { "n", "<CR>" },
  { "<CR>", "?" },
  { "n", "?" },
}) do
  fake.result = board({ "task-1" })
  local events = {}
  for _, key in ipairs(keys) do
    events[#events + 1] = { type = "key", key = key }
  end
  local reached, deletes, updates, creates = false, fake.deletes, #fake.updates, fake.creates
  events[#events + 1] = { type = "key", key = "<C-c>" }
  events[#events + 1] = function()
    reached = true
  end
  run(events)
  check(last_win.closed and not reached, "Ctrl+C immediately closes kanban from " .. table.concat(keys, ","))
  check(
    fake.deletes == deletes and #fake.updates == updates and fake.creates == creates,
    "Ctrl+C exits without saving or deleting"
  )
end

fake.result = board({ "task-1" })
local consumed_ctrl_c = false
local ctrl_deletes, ctrl_updates, ctrl_creates = fake.deletes, #fake.updates, fake.creates
run({
  { type = "key", key = "d" },
  { type = "key", key = "<C-c>" },
  function()
    consumed_ctrl_c = true
    check(
      not last_win.closed and snapshot():find("TODO · 1", 1, true) and not snapshot():find('Delete "', 1, true),
      "Board delete confirmation consumes Ctrl-C as cancellation"
    )
  end,
  { type = "key", key = "<C-c>" },
})
check(
  consumed_ctrl_c
    and last_win.closed
    and fake.deletes == ctrl_deletes
    and #fake.updates == ctrl_updates
    and fake.creates == ctrl_creates,
  "Board Ctrl-C cancellation preserves Store then second Ctrl-C quits"
)
