--# selene: allow(undefined_variable, unscoped_variables)
return function(_ENV)
  _ENV.ui = require("kanban.ui")
  _ENV.passed, _ENV.failed = 0, 0
  function _ENV.check(condition, message)
    if condition then
      _ENV.passed = passed + 1
    else
      _ENV.failed = failed + 1
      print("FAIL: " .. message)
    end
  end
  function _ENV.text(line)
    local out = {}
    if type(line) == "string" then
      return line
    end
    for _, span in ipairs(line) do
      out[#out + 1] = span[1]
    end
    return table.concat(out)
  end
  function _ENV.cursor(task)
    local found, count = nil, 0
    for row_index, line in ipairs(task:render()) do
      local column = 0
      if type(line) == "table" then
        for _, span in ipairs(line) do
          if span[2] == "cursor" then
            count = count + 1
            found = { row = row_index, column = column, text = span[1] }
          end
          column = column + width(span[1])
        end
      end
    end
    check(count <= 1, "title renders at most one cursor span")
    return found
  end
  function _ENV.run(events, term)
    _ENV.EVENTS, _ENV.TERM = events, term or { cols = 100, rows = 30 }
    _ENV.last_opts, _ENV.last_buf, _ENV.last_win = nil, nil, nil
    ui.open()
    return last_win
  end
  function _ENV.board(ids)
    local tasks = {}
    for _, id in ipairs(ids) do
      tasks[id] = { title = "Title " .. id, description = "secret description", status = "todo" }
    end
    return { tasks = tasks }
  end
  function _ENV.snapshot()
    local lines = {}
    for _, line in ipairs(last_buf.lines) do
      lines[#lines + 1] = text(line)
    end
    return table.concat(lines, "\n")
  end
  _ENV.Task = require("kanban.ui.task")
  _ENV.Board = require("kanban.ui.board")
  function _ENV.row(lines, i)
    return text(lines[i])
  end
  function _ENV.reset_editor()
    editor.files, editor.writes, editor.reads, editor.removes = {}, {}, {}, {}
    editor.exit_code, editor.write_error, editor.read_error, editor.editor_path = 0, nil, nil, nil
  end
  function _ENV.selected_title()
    for _, line in ipairs(last_buf.lines) do
      if type(line) == "table" then
        for _, span in ipairs(line) do
          if type(span[2]) == "table" and span[2].bold and span[1]:find("▸ ", 1, true) then
            return span[1]
          end
        end
      end
    end
  end
  _ENV.description_open = maki.ui.open_editor
  _ENV.observed = {}
end
