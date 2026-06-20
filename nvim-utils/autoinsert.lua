#!/usr/bin/env luajit

require 'nvim-utils.state'
require 'nvim-utils.autocmd'
require 'nvim-utils.buffer'

local is = require 'lua-utils.is'

---@alias autoinsert.expand string|string[]|(fun(file: string): string|string[])
---@alias autoinsert.pattern string|string[]|(fun(file: string): boolean)
---@alias autoinsert.template string[]|(fun(file: string): string|string[])

---@type autocmd?
user_config.autoinsert = user_config.autoinsert or nil

---Enable/disable autoinsert autocmd
autoinsert = {}

local function check(bufname, pattern)
  if is.callable(pattern) then
    return pattern(bufname)
  elseif is.string(pattern) then
    return bufname:match(pattern) ~= nil
  else
    return false
  end
end

---@param bufnr (number|string)?
---@return boolean
function autoinsert.check(bufnr, pattern)
  bufnr = bufnr or vim.fn.bufnr() or -1
  if bufnr == '' then
    return false
  elseif is.string(bufnr) then
    return check(bufnr, pattern)
  elseif buffer.exists(bufnr) then
    return autoinsert.check(buffer.get_name(bufnr), pattern)
  else
    return false
  end
end

---Returns true at insertion in the buffer
---@param bufnr? number
---@return boolean
function autoinsert.insert(bufnr)
  local ok, ft, lc, line

  bufnr = bufnr or vim.fn.bufnr() or -1
  if not buffer.exists(bufnr) then
    return false
  end

  ok, ft = buffer.get_filetype(bufnr)
  if not ok or not user_config.template[ft] then
    return false
  end

  local bufname = buffer.get_name(bufnr)
  for _, spec in ipairs(user_config.template[ft]) do
    local pattern, expansion = unpack(spec)
    if autoinsert.check(bufname, pattern) then
      if is.string(expansion) then
        expansion = string.split(expansion, "\n")
      elseif callable(expansion) then
        expansion = expansion(bufname)
        if is.string(expansion) then
          expansion = string.split(expansion, "\n")
        end
      elseif not is.table(expansion) then
        errorf(
          '%s: expected string|string[]|function, got %s [%s]',
          pattern, expansion, typeof(expansion)
        )
      end

      vim.api.nvim_buf_call(bufnr, function ()
        vim.api.nvim_put(expansion, "c", true, true)
      end)

      return true
    end
  end

  return false
end

---@param force? boolean
---@return boolean
function autoinsert.enable(force)
  local current = user_config.autoinsert
  if current and current:exists() and not force then
    return true
  end

  user_config.autoinsert = autocmd.set(
    {'BufNewFile'}, function(args)
      autoinsert.insert(args.buf)
    end, {
      pattern = '*.*',
      name = 'autoinsert',
      group = 'user_config'
    }
  )

  return true
end
