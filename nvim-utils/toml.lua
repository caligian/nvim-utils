local list = require 'lua-utils.list'
local types = require 'lua-utils.types'
local dict = require 'lua-utils.dict'
local toml = {}

function toml.list(xs)
  local res = {}
  res = list.map(xs, function (x)
    return '"' .. x .. '"'
  end)
  return '[' .. table.concat(res, ", ") .. ']'
end

function toml.dict(x, ks)
  local res = {}
  ks = ks or dict.keys(x)
  list.sort(ks)

  for i=1, #ks do
    local key = ks[i]
    local value = x[key]
    res[#res+1] = string.format('%s = "%s"', key, value)
  end

  return '{' .. table.concat(res, ", ") .. '}'
end

function toml.dicts(xs)
  local res = {}

  for i=1, #xs do
    if #xs[i] == 2 then
      res[#res+1] = toml.dict(unpack(xs[i]))
    else
      res[#res+1] = toml.dict(xs[i])
    end
  end

  return '[' .. table.concat(res, ", ") .. ']'
end

function toml.lists(xs)
  local res = {}

  for i=1, #xs do
    res[#res+1] = toml.list(xs[i])
  end

  return '[' .. table.concat(res, ", ") .. ']'
end


function toml.entry(key, value)
  if type(value) == 'string' then
    value = string.format('"%s"', value)
  elseif types.pure_dict(value) then
    value = toml.dict(value)
  elseif types.pure_list(value) then
    if types.pure_dict(value[1]) then
      value = toml.dicts(value)
    elseif types.pure_list(value[1]) then
      value = toml.lists(value)
    else
      value = toml.list(value)
    end
  end

  return string.format('%s = %s', key, value)
end

--[[

toml.section("build-system", {
  {'requires', {'setuptools >= 77.0.3'}, 'list'},
  {'build-backend', 'setuptools.build_meta'},
})

--]]
function toml.section(name, values)
  local res = {string.format('[%s]', name)}
  for i=1, #values do
    res[#res+1] = toml.entry(values[i][1], values[i][2])
  end

  return table.concat(res, "\n")
end

function toml.sections(...)
  local res = {}
  local args = {...}

  for i=1, #args do
    res[#res+1] = toml.section(unpack(args[i]))
    res[#res+1] = ""
  end

  return table.concat(res, "\n")
end

return toml
