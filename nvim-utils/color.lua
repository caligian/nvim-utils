require "nvim-utils.state"

local RED = 0.2126
local GREEN = 0.7152
local BLUE = 0.0722
local GAMMA = 2.4

function highlight(hi)
  hi = hi or "Normal"
  local out = nvim_exec(":hi " .. hi, true)
  if not out or #out == 0 then
    return
  end

  hi = {}

  out = vim.split(out, " +")
  out = list.filter(out, function(c)
    if strmatch(c, "xxx", "cleared") then
      return false
    else
      return true
    end
  end)

  out = list.sub(out, 1, #out)
  list.each(out, function(i)
    local attrib, value = unpack(vim.split(i, "="))
    if value then
      hi[attrib] = value
    end
  end)

  return hi
end

function hex2rgb(hex)
  hex = hex:gsub("#", "")

  return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
end

-- Taken from https://github.com/iskolbin/lhsx/blob/master/hsx.lua
function rgb2hsv(r, g, b)
  local M, m = math.max(r, g, b), math.min(r, g, b)
  local C = M - m
  local K = 1.0 / (6.0 * C)
  local h = 0.0
  if C ~= 0.0 then
    if M == r then
      h = ((g - b) * K) % 1.0
    elseif M == g then
      h = (b - r) * K + 1.0 / 3.0
    else
      h = (r - g) * K + 2.0 / 3.0
    end
  end
  return h, M == 0.0 and 0.0 or C / M, M
end

function hsv2rgb(h, s, v)
  local C = v * s
  local m = v - C
  local r, g, b = m, m, m
  if h == h then
    local h_ = (h % 1.0) * 6
    local X = C * (1 - math.abs(h_ % 2 - 1))
    C, X = C + m, X + m
    if h_ < 1 then
      r, g, b = C, X, m
    elseif h_ < 2 then
      r, g, b = X, C, m
    elseif h_ < 3 then
      r, g, b = m, C, X
    elseif h_ < 4 then
      r, g, b = m, X, C
    elseif h_ < 5 then
      r, g, b = X, m, C
    else
      r, g, b = C, m, X
    end
  end
  return r, g, b
end

function darken(hex, darker_n)
  local result = "#"

  for s in hex:gmatch "[a-fA-F0-9][a-fA-F0-9]" do
    local bg_numeric_value = tonumber("0x" .. s) - darker_n

    if bg_numeric_value < 0 then
      bg_numeric_value = 0
    end

    if bg_numeric_value > 255 then
      bg_numeric_value = 255
    end

    result = result .. string.format("%2.2x", bg_numeric_value)
  end

  return result
end

function lighten(hex, lighten_n)
  return darken(hex, lighten_n * -1)
end

function highlightset(hi, set, defaults)
  local group = hi
  hi = highlight(hi)

  if not hi then
    return
  end

  if is_empty(hi) then
    if defaults then
      hi = defaults
    else
      return
    end
  end

  dict.each(set, function(attrib, transformer)
    if not hi[attrib] then
      return
    end

    if is_a.callable(transformer) then
      hi[attrib] = transformer(hi[attrib])
      vim.cmd(sprintf("hi %s %s=%s", group, attrib, hi[attrib]))
    else
      hi[attrib] = transformer
      vim.cmd(sprintf("hi %s %s=%s", group, attrib, transformer))
    end
  end)

  return hi
end

--- ttps://stackoverflow.com/questions/22603510/is-this-possible-to-detect-a-colour-is-a-light-or-dark-colour
function is_light(hex_or_r, g, b)
  local r

  if g then
    r = hex_or_r
    local hsp = (0.299 * (r * r)) + (0.587 * (g * g)) + (0.114 * (b * b))
    local C = math.pow(127.5, 2)

    if hsp > C then
      return true
    end

    return false
  end

  return is_light(hex2rgb(hex_or_r))
end

function is_dark(...)
  return not is_light(...)
end

function luminance(red_or_hex, green, blue)
  if is_a.string(red_or_hex) then
    return luminance(hex2rgb(red_or_hex))
  end

  local function lum(c)
    c = c / 255
    if c <= 0.03928 then
      return c / 12.92
    else
      return math.pow((c + 0.055) / 1.055, GAMMA)
    end
  end

  local r = lum(red_or_hex)
  local g = lum(green)
  local b = lum(blue)

  return (r * RED) + (g * GREEN) + (b * BLUE)
end

function contrast(hex_or_rgb1, hex_or_rgb2)
  local lum1 = luminance(hex_or_rgb1)
  local lum2 = luminance(hex_or_rgb2)
  local brightest = math.max(lum1, lum2)
  local darkest = math.min(lum1, lum2)
  return (brightest + 0.05) / (darkest + 0.05)
end
