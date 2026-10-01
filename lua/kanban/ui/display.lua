local Display = {}

function Display.styled(text, color, bold, background)
  return { text, { fg = color, bg = background, bold = bold } }
end

function Display.fit(text, width)
  if width <= 0 then
    return ""
  end
  if maki.ui.display_width(text) > width then
    text = maki.ui.truncate_text(text, width).head
  end
  return text .. string.rep(" ", math.max(0, width - maki.ui.display_width(text)))
end

local function slice_line(line, start, length)
  local result, position = {}, 0
  if type(line) == "string" then
    line = { Display.styled(line) }
  end
  for _, span in ipairs(line) do
    local text, style = span[1], span[2]
    local width = maki.ui.display_width(text)
    local left, right = math.max(start, position), math.min(start + length, position + width)
    if right > left then
      local prefix = maki.ui.truncate_text(text, left - position)
      local leading = left - position - maki.ui.display_width(prefix.head)
      local tail = prefix.tail
      if leading > 0 then
        local first = maki.ui.truncate_text(tail, 2)
        tail = first.tail
      end
      local part = maki.ui.truncate_text(tail, math.max(0, right - left - leading)).head
      result[#result + 1] = { Display.fit(string.rep(" ", leading) .. part, right - left), style }
    end
    position = position + width
  end
  return result
end

function Display.help_overlay(state, lines, help)
  if state.width <= 0 or state.height <= 0 then
    return
  end
  local width, height = math.min(36, state.width), math.min(#help + 2, state.height)
  if width < 2 or height < 2 then
    lines[math.floor((state.height + 1) / 2)] =
      { Display.styled(Display.fit("? Help: ? / Esc close", state.width), (maki.ui.theme_style("accent") or {}).fg) }
    return
  end
  local x, y = math.floor((state.width - width) / 2), math.floor((state.height - height) / 2)
  local color = maki.ui.theme_color("foreground")
  for row = 1, height do
    local text
    if row == 1 then
      local title = maki.ui.truncate_text("─ Keybindings ", width - 2).head
      text = "┌" .. title .. string.rep("─", width - 2 - maki.ui.display_width(title)) .. "┐"
    elseif row == height then
      text = "└" .. string.rep("─", width - 2) .. "┘"
    else
      text = "│" .. Display.fit(help[row - 1] or "", width - 2) .. "│"
    end
    local line = slice_line(lines[y + row], 0, x)
    line[#line + 1] = Display.styled(text, row == 1 and (maki.ui.theme_style("accent") or {}).fg or color)
    for _, span in ipairs(slice_line(lines[y + row], x + width, state.width - x - width)) do
      line[#line + 1] = span
    end
    lines[y + row] = line
  end
end

return Display
