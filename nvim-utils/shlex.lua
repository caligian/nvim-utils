shlex = namespace "shlex"

---
-- @tparam string cmd
-- @treturn list[string] quoted contents
local function get_quoted(cmd)
  local first_quote = string.find(cmd, "'") or string.find(cmd, '"')

  if not first_quote then
    return list.map(split(cmd, " "), function(x)
      return { false, x }
    end)
  end

  local quote = string.sub(cmd, first_quote, first_quote)
  local cache = { true }
  local res = { { false, substr(cmd, 1, first_quote - 1) or "" } }
  local lim = #cmd
  local i = first_quote + 1
  local other_quote = quote == "'" and '"' or "'"

  while i <= lim do
    local c = cmd:sub(i, i)
    local prev = cmd:sub(i - 1, i - 1)
    local isquote = c == quote
    local backslash = prev and prev == "\\"
    local escaped = backslash and isquote

    if escaped or not isquote then
      list.append(cache, { c })
    elseif isquote and not escaped then
      list.append(res, { { true, join(list.sub(cache, 2), "") } })

      cache = { true }

      local new_i = string.find(cmd, quote, i + 1) or string.find(cmd, other_quote, i + 1)

      if not new_i then
        break
      else
        local remaining = string.sub(cmd, i + 1, new_i - 1)
        list.append(res, { { false, remaining } })
        i = new_i
        quote = substr(cmd, new_i, new_i) or ""
      end
    end

    i = i + 1
  end

  if i <= lim then
    list.append(res, { { false, substr(cmd, i + 1, lim) or "" } })
  end

  return res
end

--- parse a command string split by whitespace and quotes
-- @tparam cmd string command to parse
-- @treturn list[string]
function shlex.parse(cmd)
  local parsed = get_quoted(cmd)
  local res = {}

  list.eachi(parsed, function(i, status)
    local isquoted, s = unpack(status)
    local prev_status = parsed[i - 1]
    prev_status = prev_status and prev_status[2]
    local prev_status_len = prev_status and #prev_status
    local last_char = prev_status and substr(prev_status, prev_status_len, prev_status_len)
    local ends_with_dollar = last_char == "$" and isquoted

    if ends_with_dollar then
      res[#res] = substr(res[#res], 1, #res[#res] - 1)
      s = "$" .. "'" .. s .. "'"
    end

    if isquoted then
      list.append(res, { s })
    else
      list.extend(res, { strsplit(s, "%s+") })
    end
  end)

  return list.filter(res, function(x)
    return #x > 0
  end)
end

function shlex:__call(cmd)
  return shlex.parse(cmd)
end

return shlex
