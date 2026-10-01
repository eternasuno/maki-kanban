--# selene: allow(undefined_variable, unscoped_variables)
fake.result = {
  tasks = {
    ["task-1"] = {
      title = "A long detail title that wraps across two lines",
      description = "first line\n\n" .. string.rep("long description words ", 300),
      status = "doing",
    },
  },
}
local observed = {}
run({
  { type = "key", key = "l" },
  { type = "key", key = "<CR>" },
  function()
    observed.detail = snapshot()
  end,
  { type = "key", key = "j" },
  function()
    observed.j = snapshot()
  end,
  { type = "key", key = "<Down>" },
  function()
    observed.down = snapshot()
  end,
  { type = "key", key = "J" },
  function()
    observed.scroll = snapshot()
  end,
  { type = "key", key = "<PageDown>" },
  function()
    observed.page_down = snapshot()
  end,
  { type = "key", key = "G" },
  function()
    observed.bottom = snapshot()
  end,
  { type = "key", key = "<PageUp>" },
  function()
    observed.page_up = snapshot()
  end,
  { type = "key", key = "K" },
  function()
    observed.k = snapshot()
  end,
  { type = "key", key = "g" },
  function()
    observed.top = snapshot()
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.back = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.detail:find("A long detail title", 1, true) and not observed.detail:find("Doing", 1, true),
  "Enter opens detail with title but no status text"
)
check(
  observed.detail:find("first line", 1, true)
    and observed.detail:find("┌", 1, true)
    and observed.detail:find("└", 1, true)
    and observed.detail:find("Esc back", 1, true),
  "detail displays description and bordered back footer"
)
check(
  observed.j:find("▸ Description", 1, true)
    and observed.j:find("first line", 1, true)
    and observed.down == observed.detail,
  "j and Down wrap field focus without scrolling"
)
check(
  observed.scroll ~= observed.down and observed.page_down ~= observed.scroll and observed.bottom ~= observed.page_down,
  "J, PageDown and G advance description viewport"
)
check(
  observed.page_up ~= observed.bottom and observed.k ~= observed.page_up and observed.top == observed.detail,
  "PageUp, K and g navigate viewport independently of focus"
)
check(
  observed.back:find("DOING · 1", 1, true) and observed.back:find("▸ A long detail title", 1, true),
  "Esc restores board focus and selected task"
)

fake.result =
  { tasks = { ["task-1"] = { title = "待辦標題 that is far too long", description = "", status = "done" } } }
observed = {}
run({
  { type = "key", key = "h" },
  { type = "key", key = "<Enter>" },
  function()
    observed.detail = snapshot()
  end,
  { type = "resize", width = 20, height = 10 },
  function()
    observed.resize = snapshot()
    check(#last_buf.lines == 10 and not last_win.closed, "detail resize keeps view open with exact height")
    for _, line in ipairs(last_buf.lines) do
      check(width(text(line)) == 20, "resized detail fits exact width")
    end
  end,
  { type = "key", key = "<Esc>" },
  function()
    observed.back = snapshot()
  end,
  { type = "key", key = "q" },
})
check(
  observed.detail:find("待辦標題", 1, true)
    and observed.resize:find("待辦標題", 1, true)
    and observed.detail ~= observed.resize
    and not observed.resize:find("Done", 1, true),
  "resize rewraps CJK title without status label"
)
check(
  observed.back:find("DONE · 1", 1, true) and last_win.closed,
  "detail back retains done-column focus after resize"
)

fake.result = { tasks = {} }
run({ { type = "key", key = "<CR>" }, { type = "key", key = "q" } })
check(text(last_buf.lines[2]):find("TODO", 1, true) ~= nil, "Enter on empty selection remains on board")
run({ { type = "key", key = "<Esc>" } })
check(last_win.closed, "Esc closes from board view")
