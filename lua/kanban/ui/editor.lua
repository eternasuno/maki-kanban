local Editor = {}

function Editor.edit(original)
  local path
  local ok, text, err = pcall(function()
    if os and type(os.tmpname) == "function" then
      local allocated, result = pcall(os.tmpname)
      if allocated then
        path = result
      end
    end
    if not path then
      local dir = maki.env.state_dir()
      for _ = 1, 10 do
        local candidate = maki.fs.joinpath(
          dir,
          string.format("kanban-description-%08x-%08x.md", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
        )
        local meta, metadata_err = maki.fs.metadata(candidate)
        if not meta and not metadata_err then
          path = candidate
          break
        end
      end
    end
    if not path then
      return nil, "temporary file path unavailable"
    end
    local written, write_err = maki.fs.write(path, original)
    if not written then
      return nil, tostring(write_err or "could not write temporary file")
    end
    local exit_code = maki.ui.open_editor(path)
    if exit_code ~= 0 then
      return nil, "editor exited with status " .. tostring(exit_code)
    end
    local edited, read_err = maki.fs.read(path)
    if edited == nil then
      return nil, tostring(read_err or "could not read temporary file")
    end
    return edited
  end)
  if not ok then
    text, err = nil, tostring(text)
  end
  local cleanup_err
  if path then
    local cleaned, removed, remove_err = pcall(maki.fs.rm, path)
    if not cleaned then
      remove_err = removed
    end
    if not cleaned or not removed then
      cleanup_err = tostring(remove_err or "could not remove temporary file")
    end
  end
  return text, err, cleanup_err
end

return Editor
