local Harness = {}
function Harness.run(root, name)
  for module in pairs(package.loaded) do
    if module:match("^kanban%.") or module == "maki.text_input" then
      package.loaded[module] = nil
    end
  end
  local original_tmpname = os.tmpname
  -- selene: allow(incorrect_standard_library_use)
  os.tmpname = function()
    return "/tmp/kanban-ui-test"
  end
  local env = setmetatable({}, { __index = _G })
  for _, facility in ipairs({ "host", "store", "helpers" }) do
    assert(loadfile(root .. "/tests/ui/" .. facility .. ".lua"))()(env)
    if facility == "host" then
      _G.maki = env.maki
    end
  end
  -- selene: allow(incorrect_standard_library_use)
  local ok, err = pcall(assert(loadfile(root .. "/tests/ui/" .. name .. ".lua", "t", env)))
  -- selene: allow(incorrect_standard_library_use)
  os.tmpname = original_tmpname
  if not ok then
    env.failed = env.failed + 1
    print("FAIL: " .. name .. ": " .. tostring(err))
  end
  print(string.format("%s: %d passed, %d failed", name, env.passed, env.failed))
  return env.passed, env.failed
end
return Harness
