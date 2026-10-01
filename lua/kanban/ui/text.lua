local Text = {}

local function split_lines(text)
  local lines = {}
  text = tostring(text or "")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function chunk_end(text, start, limit)
  local last = math.min(#text, start + limit - 1)
  while last < #text do
    local byte = text:byte(last + 1)
    if byte < 128 or byte >= 192 then
      break
    end
    last = last + 1
  end
  return last
end

function Text.wrap(text, width)
  local lines = {}
  if width <= 0 then
    return lines
  end
  local limit = math.max(256, width * 4 + 16)
  for _, source in ipairs(split_lines(text)) do
    if source == "" then
      lines[#lines + 1] = ""
    else
      local start = 1
      while start <= #source do
        local last = chunk_end(source, start, limit)
        local chunk = source:sub(start, last)
        local chunk_width = maki.ui.display_width(chunk)
        while last < #source and chunk_width <= width do
          last = chunk_end(source, start, (last - start + 1) * 2)
          chunk = source:sub(start, last)
          chunk_width = maki.ui.display_width(chunk)
        end
        if chunk_width <= width then
          lines[#lines + 1] = chunk
          start = last + 1
        else
          local part = maki.ui.truncate_text(chunk, width).head
          if part == "" then
            lines[#lines + 1] = source:sub(start)
            break
          end
          lines[#lines + 1] = part
          start = start + #part
        end
      end
    end
  end
  return lines
end

function Text.wrap_input(input, width)
  local lines, cursor_row = { {} }, 1
  if width <= 0 then
    return lines, cursor_row
  end
  local used = 0
  for _, source in ipairs(input:render("", 0).lines) do
    for _, span in ipairs(source) do
      local text, start = span[1], 1
      while start <= #text do
        local last = chunk_end(text, start, math.max(256, width * 4 + 16))
        local remaining = text:sub(start, last)
        local part = maki.ui.truncate_text(remaining, width - used)
        if part.head ~= "" then
          local line = lines[#lines]
          line[#line + 1] = { part.head, span[2] }
          if span[2] == "cursor" then
            cursor_row = #lines
          end
          used = used + maki.ui.display_width(part.head)
          start = start + #part.head
        elseif used > 0 then
          lines[#lines + 1], used = {}, 0
        else
          local char = remaining:match("^.[\128-\191]*")
          if span[2] == "cursor" then
            local line = lines[#lines]
            line[#line + 1] = { " ", "cursor" }
            cursor_row, used = #lines, 1
          end
          start = start + #char
        end
      end
    end
  end
  return lines, cursor_row
end

return Text
