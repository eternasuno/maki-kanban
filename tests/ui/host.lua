--# selene: allow(undefined_variable, unscoped_variables)
return function(_ENV)
  _ENV.TERM = { cols = 100, rows = 30 }
  _ENV.EVENTS, _ENV.last_opts, _ENV.last_buf, _ENV.last_win = {}, nil, nil, nil
  _ENV.input_snapshot, _ENV.input_edit_result, _ENV.input_edit_error, _ENV.notifications, _ENV.input_edit_closed =
    nil, true, nil, {}, nil
  function _ENV.make_buf()
    local buf = { lines = {} }
    function buf:set_lines(lines)
      assert(type(lines) == "table", "lines must be a table")
      for line_index, line in ipairs(lines) do
        assert(type(line) == "string" or type(line) == "table", "invalid line " .. line_index)
        if type(line) == "table" then
          for span_index, span in ipairs(line) do
            assert(
              type(span) == "table"
                and type(span[1]) == "string"
                and (span[2] == nil or type(span[2]) == "table" or type(span[2]) == "string")
                and span[3] == nil,
              "invalid span at line " .. line_index .. ", span " .. span_index
            )
          end
        end
      end
      self.lines = lines
    end
    function buf:len()
      return #self.lines
    end
    return buf
  end
  function _ENV.make_win(buf, opts)
    local win = { buf = buf, opts = opts, config = opts, config_calls = {}, closed = false }
    function win:set_config(patch)
      self.config_calls[#self.config_calls + 1] = patch
      for key, value in pairs(patch) do
        self.config[key] = value
      end
    end
    function win:recv()
      local event = table.remove(EVENTS, 1)
      while type(event) == "function" do
        event()
        event = table.remove(EVENTS, 1)
      end
      return event
    end
    function win:close()
      self.closed = true
    end
    return win
  end
  function _ENV.width(text)
    local n, i = 0, 1
    while i <= #text do
      local b = text:byte(i)
      local bytes = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
      if b < 224 or (b == 226 and (text:byte(i + 1) == 148 or text:sub(i, i + 2) == "▸")) then
        n = n + 1
      else
        n = n + 2
      end
      i = i + bytes
    end
    return n
  end
  function _ENV.truncate(text, max)
    local out, used, i = "", 0, 1
    while i <= #text do
      local b = text:byte(i)
      local bytes = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
      local chars = b < 128 and 1
        or b < 224 and 1
        or (b == 226 and (text:byte(i + 1) == 148 or text:sub(i, i + 2) == "▸")) and 1
        or 2
      if used + chars > max then
        break
      end
      out, used, i = out .. text:sub(i, i + bytes - 1), used + chars, i + bytes
    end
    return { head = out, tail = text:sub(i) }
  end
  _ENV.editor = { files = {}, writes = {}, reads = {}, removes = {}, exit_code = 0 }
  function _ENV.editor_write(path, value)
    editor.writes[#editor.writes + 1] = path
    editor.files[path] = value
    if editor.write_error then
      return nil, editor.write_error
    end
    return true
  end
  function _ENV.editor_read(path)
    editor.reads[#editor.reads + 1] = path
    if editor.read_error then
      return nil, editor.read_error
    end
    return editor.files[path]
  end
  function _ENV.editor_rm(path)
    editor.removes[#editor.removes + 1] = path
    editor.files[path] = nil
    return true
  end

  _ENV.maki = {
    env = {
      state_dir = function()
        return "/tmp"
      end,
    },
    fs = {
      write = editor_write,
      read = editor_read,
      rm = editor_rm,
      joinpath = function(dir, file)
        return dir .. "/" .. file
      end,
      metadata = function(path)
        return editor.files[path] and { is_file = true } or nil
      end,
    },
    ui = {
      terminal_size = function()
        return { cols = TERM.cols, rows = TERM.rows }
      end,
      display_width = width,
      truncate_text = truncate,
      theme_color = function(name)
        return ({ background = "#101010", foreground = "#eeeeee" })[name]
      end,
      theme_style = function(name)
        if name == "item_selected" then
          return { bg = "#7799ff", fg = "#101010" }
        end
        local color = ({
          accent = "#7799ff",
          warning = "#ffaa00",
          success = "#00cc66",
          error = "#ff4444",
          foreground = "#eeeeee",
        })[name]
        if color then
          return { fg = color }
        end
      end,
      buf = function()
        return make_buf()
      end,
      open_editor = function(path)
        editor.editor_path = path
        return editor.exit_code
      end,
      input = function()
        return input_snapshot
      end,
      input_edit = function(opts)
        _ENV.input_edit_closed = last_win and last_win.closed
        _ENV.input_edit_opts = opts
        return input_edit_result, input_edit_error
      end,
      open_win = function(buf, opts)
        _ENV.last_buf, _ENV.last_opts, _ENV.last_win = buf, opts, make_win(buf, opts)
        return last_win
      end,
    },
    notify = function(message, level, opts)
      notifications[#notifications + 1] = { message = message, level = level, opts = opts }
    end,
  }

  _ENV.text_input = {}
  text_input.Result = { IGNORED = "ignored", CHANGED = "changed" }
  function text_input.new()
    local input = { chars = {}, cursor = 1 }
    function input:value()
      return table.concat(self.chars)
    end
    function input:insert_text(value)
      value = tostring(value or "")
      for char in value:gmatch(".[\128-\191]*") do
        table.insert(self.chars, self.cursor, char)
        self.cursor = self.cursor + 1
      end
      return text_input.Result.CHANGED
    end
    function input:render(prefix, prefix_width, render_width)
      assert(prefix == "" and prefix_width == 0 and render_width == nil, "title render must not use codepoint wrapping")
      return {
        lines = {
          {
            { prefix, "dim" },
            { table.concat(self.chars, "", 1, self.cursor - 1), "" },
            { self.chars[self.cursor] or " ", "cursor" },
            { table.concat(self.chars, "", self.cursor + 1), "" },
          },
        },
        cursor_row = 1,
      }
    end
    function input:handle_key(key)
      if key == "<Left>" then
        self.cursor = math.max(1, self.cursor - 1)
        return text_input.Result.CHANGED
      end
      if key == "<Right>" then
        self.cursor = math.min(#self.chars + 1, self.cursor + 1)
        return text_input.Result.CHANGED
      end
      if key == "<Home>" then
        self.cursor = 1
        return text_input.Result.CHANGED
      end
      if key == "<End>" then
        self.cursor = #self.chars + 1
        return text_input.Result.CHANGED
      end
      if key == "<BS>" or key == "<Backspace>" then
        if self.cursor > 1 then
          table.remove(self.chars, self.cursor - 1)
          self.cursor = self.cursor - 1
          return text_input.Result.CHANGED
        end
        return text_input.Result.IGNORED
      end
      if key == "<Del>" or key == "<Delete>" then
        if self.cursor <= #self.chars then
          table.remove(self.chars, self.cursor)
          return text_input.Result.CHANGED
        end
        return text_input.Result.IGNORED
      end
      if type(key) == "string" and key:match("^.[\128-\191]*$") and key:byte() >= 32 then
        return self:insert_text(key)
      end
      return text_input.Result.IGNORED
    end
    return input
  end
  package.loaded["maki.text_input"] = text_input
end
