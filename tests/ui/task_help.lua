--# selene: allow(undefined_variable, unscoped_variables)
for _, creating in ipairs({ false, true }) do
  local state = creating and Task.new_create(90, 27)
    or Task.new({ id = "task-1", title = "Help title", description = "first\nsecond\nthird", status = "todo" }, 90, 27)
  state.focused_field = "description"
  local calls, updates, deletes, creates = fake.calls, #fake.updates, fake.deletes, fake.creates
  state:handle_key("?", fake)
  local help = {}
  for _, line in ipairs(state:render()) do
    help[#help + 1] = text(line)
  end
  help = table.concat(help, "\n")
  check(
    help:find("Keybindings", 1, true)
      and help:find("Tab / S-Tab", 1, true)
      and help:find(creating and "s           create task" or "J / K", 1, true),
    "Task help describes mode-specific phase2 actions"
  )
  for _, key in ipairs({
    "q",
    "n",
    "s",
    "d",
    "y",
    "<",
    ">",
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
    "<PageDown>",
    "<PageUp>",
  }) do
    check(
      state:handle_key(key, fake) == true
        and state.help_open
        and state.focused_field == "description"
        and state.offset == 0
        and not state.editing
        and not state.confirm_delete
        and fake.calls == calls
        and #fake.updates == updates
        and fake.deletes == deletes
        and fake.creates == creates,
      "Task help consumes key without side effects: " .. key
    )
  end
  check(not state:handle_paste("ignored"), "Task help ignores paste outside editing")
  for _, size in ipairs({ { 0, 0 }, { 1, 1 }, { 2, 2 }, { 3, 4 }, { 20, 10 }, { 90, 27 } }) do
    state:resize(size[1], size[2])
    check(state.help_open and #state:render() == size[2], "Task help resize preserves modal and exact height")
    for _, line in ipairs(state:render()) do
      check(width(text(line)) == size[1], "Task help resize fits exact width")
    end
  end
  check(
    state:handle_key("?", fake) and not state.help_open and state.focused_field == "description",
    "question mark closes Task help preserving focus"
  )
  state:handle_key("?", fake)
  check(
    state:handle_key("<Esc>", fake) == true and not state.help_open,
    "Esc dismisses Task help rather than returning to Board"
  )
  state:handle_key("?", fake)
  check(state:handle_key("<C-c>", fake) == "quit", "Ctrl-C quits Task help")
end
