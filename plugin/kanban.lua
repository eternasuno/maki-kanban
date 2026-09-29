require("kanban.tools").register()

local ui = require("kanban.ui")

maki.api.register_command({
  name = "/kanban",
  description = "Show the kanban board",
  handler = function()
    ui.open()
  end,
})
