#!/usr/bin/env luajit

require 'nvim-utils.state'
require 'nvim-utils.autocmd'
require 'nvim-utils.buffer'

local is = require 'lua-utils.is'

---@alias autoinsert.expand string|string[]|(fun(file: string): string|string[])
---@alias autoinsert.pattern string|string[]|(fun(file: string): boolean)|(fun(file: string): boolean)[]
---@alias autoinsert.template string[]|(fun(file: string): string|string[])
---@alias autoinsert.config.shape { [1]: autoinsert.pattern, [2]: autoinsert.expand }
---@alias autoinsert.config table<string,autoinsert.config.spec>


---@type autocmd?
user_config.autoinsert = user_config.autoinsert or nil

---Enable/disable autoinsert autocmd
autoinsert = class 'autoinsert'
local filetypes = user_config.filetype
local templates = user_config.template

---@param bufname string
---@param pattern (string|function)[]
---@return boolean
local function check(bufname, pattern)
  pattern = not is.pure_list(pattern) and { pattern } or pattern
  for i = 1, #pattern do
    local pat = pattern[i]
    local ok

    if is.callable(pat) then
      ok = pat(bufname)
    elseif is.string(pat) then
      ok = bufname:match(pat) ~= nil
    end

    if ok then
      return true
    end
  end

  return false
end

---Check if the pattern matches with the buffer
---@param bufnr (number|string)?
---@param pattern string|string[]|function|function[]
---@return boolean
function autoinsert.check(bufnr, pattern)
  bufnr = bufnr or vim.fn.bufnr() or -1
  if bufnr == '' then
    return false
  end

  if is.string(bufnr) then
    return check(bufnr, pattern)
  elseif buffer.exists(bufnr) then
    return autoinsert.check(buffer.get_name(bufnr), pattern)
  else
    return false
  end
end

---@param bufnr string|number Number for buffer number, string for filetype
---@return (string|string[]|(fun(file: string): string|string[]))?
function autoinsert.expand(bufnr)
  bufnr = bufnr or vim.fn.bufnr() or -1
  if not buffer.exists(bufnr) then
    return
  end

  local ok, msg, config, ft
  ok, msg = buffer.get_filetype(bufnr)

  if not ok then
    return
  else
    ft = msg
  end

  if ft == '' then
    return
  elseif filetypes[ft] then
    local ft_config = filetypes[ft]
    if defined(ft_config) and ft_config.template then
      config = ft_config.template
    end
  end

  if undefined(config) then
    config = templates[ft]
    if undefined(config) then
      return nil
    end
  end

  config = vim.deepcopy(config)
  table.sort(config, function (a, b)
    a.priority = a.priority or 0
    b.priority = b.priority or 0
    return a.priority > b.priority
  end)

  local filename = buffer.filename(bufnr)
  for _, spec in ipairs(config) do
    if autoinsert.check(filename, spec[1]) then
      return spec[2]
    end
  end
end

---Returns true at insertion in the buffer
---@param bufnr? number
---@return boolean? status When return value is nil, consider the buffer invalid
function autoinsert.insert(bufnr)
  bufnr = bufnr or vim.fn.bufnr() or -1
  if not buffer.exists(bufnr) then
    return
  end

  local expansion = autoinsert.expand(bufnr)
  if not expansion then
    return false
  end

  vim.api.nvim_buf_call(bufnr, function()
    expansion = is.string(expansion) and string.split(expansion, "\n") or expansion
    vim.api.nvim_put(expansion, "c", true, true)
  end)

  return true
end

---@param force? boolean
---@return boolean
function autoinsert.enable(force)
  local current = user_config.autoinsert
  if current and current:exists() and not force then
    return true
  end

  user_config.autoinsert = autocmd.set(
    { 'BufNewFile' }, function(args)
      autoinsert.insert(args.buf)
    end, {
      pattern = '*.*',
      name = 'autoinsert',
      group = 'user_config'
    }
  )

  return true
end

function autoinsert.load_config()
  local ok, msg = nvim.pcall(require, 'config.template')
  if not ok then
    return false, msg
  end

  for key, value in pairs(msg) do
    user_config.template[key] = value
  end
end


return autoinsert
