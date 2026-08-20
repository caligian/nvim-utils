#!/usr/bin/env luajit

require 'lua-utils'

local list = require 'lua-utils.list'
local dict = require 'lua-utils.dict'
local path = require 'lua-utils.path_utils'
local nvim = require 'nvim-utils.nvim'

---@param bufnr? number
---@param fmt string
---@param ... any Throw error
---@return string
local function buf_msg(bufnr, fmt, ...)
  bufnr = bufnr or vim.fn.bufnr(bufnr)
  return sprintf('buffer[%d]: %s', bufnr, sprintf(fmt, ...))
end

---@param winid number
---@param fmt string
---@param ... any
---@return string
local function win_msg(winid, fmt, ...)
  local bufnr = vim.fn.winbufnr(winid)
  return sprintf('buffer[%d].winid[%d]: %s', bufnr, winid, sprintf(fmt, ...))
end

---@param bufnr number
---@param fmt string
---@param ... any
function err_buf_msg(bufnr, fmt, ...)
  error(buf_msg(bufnr, fmt, ...))
end

---@param winid number
---@param fmt string
---@param ... any
function err_win_msg(winid, fmt, ...)
  error(win_msg(winid, fmt, ...))
end

---@param bufnr number
---@return boolean
local function is_valid_bufnr(bufnr)
  return
      type(bufnr) == 'number' and
      bufnr ~= 0 and
      vim.api.nvim_buf_is_valid(bufnr)
end

---@param bufnr? number
---@return boolean, number|string
local function fix_bufnr(bufnr)
  if bufnr == nil then
    bufnr = vim.api.nvim_get_current_buf()
  elseif bufnr == 0 then
    error('bufnr: cannot 0 to refer to current buffer')
  end

  if is_valid_bufnr(bufnr) then
    return true, bufnr
  else
    return false, buf_msg(bufnr, 'invalid buffer')
  end
end

---Buffer utilities
buffer = {}

--- Disambiguating return values
---@class buffer_returns
---@field [1] table<string,function> Returns one value
---@field [2] table<string,function> Returns two values
buffer.returns = { {}, {} }

---@class buffer_result
---@field ok table<string, any> | table<string, table<string, any>>
---@field err table<string, string> | table<string, table<string, any>>

local function get_opts(opts, should_deepcopy, assert_keys)
  if opts == nil then
    opts = {}
  elseif should_deepcopy then
    opts = vim.deepcopy(opts)
  end

  if assert_keys then
    for i = 1, #assert_keys do
      local k = assert_keys[i]
      assert(opts[k], sprintf("opts.%s: Missing keys", k))
    end
  end

  return opts
end

---@param bufnr? number|buffer.id.opts
---@param ok? buffer.id.opts|(fun(buf: number): boolean, any)
---@param err? (fun(msg?: string): boolean, any)
---@return boolean, any
function buffer.id(bufnr, ok, err)
  if is.pure_table(bufnr) then
    return buffer.id(buffer.get_current_id(), bufnr)
  elseif is.pure_table(ok) then
    return buffer.id(bufnr, ok.ok, ok.err)
  end

  ok = ok or function(buf) return true, buf end
  err = err or function(msg) return false, msg end
  bufnr = bufnr or vim.fn.bufnr()
  assert_is.number(bufnr, 'bufnr')

  if bufnr < 0 then
    errorf("bufnr: expected natural number, got %d", bufnr)
  elseif not buffer.exists(bufnr) then
    return err(sprintf('expected extant buffer, got %d', bufnr))
  else
    return ok(bufnr)
  end
end

buffer.get_id = buffer.id

---@param bufnr? number
---@return string?
function buffer.get_name(bufnr)
  bufnr = bufnr == nil and buffer.current() or bufnr or -1
  if vim.fn.bufnr(bufnr) == -1 then
    return nil
  else
    return vim.api.nvim_buf_get_name(bufnr)
  end
end

---@param bufnr number
---@param name string
---@return boolean, string?
function buffer.set_name(bufnr, name)
  local ok, buf = fix_bufnr(bufnr)
  if not ok then return false, buf end

  ok, _ = pcall(vim.api.nvim_buf_set_name, buf, name)
  if not ok then
    return false, sprintf('buffer[%d]: Could not set buffer name `%s`', buf, name)
  else
    return true, name
  end
end

---@param bufnr number
---@param return_msg? boolean Return error message
---@param throw? boolean Throw error on non-existence
---@return boolean,string?
function buffer.exists(bufnr, return_msg, throw)
  bufnr = bufnr or -1
  if vim.api.nvim_buf_is_valid(bufnr) then
    return true, nil
  end

  if return_msg or throw then
    local msg = sprintf('bufnr: Invalid buffer provided %d', bufnr)
    if throw then
      error(msg)
    else
      return false, msg
    end
  end

  return false, nil
end

---@param bufnr number
function buffer.assert_exists(bufnr)
  buffer.exists(bufnr, true, true)
end

---@param bufnr number
---@param start_row number
---@param end_row   number
---@param lines string[]|string
---@return boolean, string?
function buffer.set_lines(bufnr, start_row, end_row, lines)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      lines = type(lines) == 'string' and vim.split(lines, "\n") or lines
      local ok, msg = pcall(vim.api.nvim_buf_set_lines, buf, start_row, end_row, false, lines)
      if ok then
        return true, nil
      else
        return false, msg
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@class buffer.call.signature
---@field buf string
---@field file? string
---@field winnr? number
---@field winid? number

---@param bufnr number
---@param f fun(args: buffer.call.signature): any
---@return boolean, any
function buffer.call(bufnr, f)
  local ok, msg = fix_bufnr(bufnr)
  if not ok then
    return false, msg
  end

  local function use_fun()
    local args = { buf = bufnr, file = buffer.get_name(bufnr) }
    local success, winid, winnr

    success, winid = buffer.get_winid(bufnr)
    if success then
      args.winid = winid
    end

    success, winnr = buffer.get_winnr(bufnr)
    if success then
      args.winnr = winnr
    end

    return f(args)
  end

  return buffer.get_id(bufnr, {
    ok = function(buf)
      return pcall(vim.api.nvim_buf_call, buf, use_fun)
    end,
    err = function(err_msg)
      return false, err_msg
    end
  })
end

---@param bufnr number
---@return boolean
function buffer.is_valid(bufnr)
  assert(type(bufnr) == 'number', 'bufnr: Must be a number')
  assert(bufnr ~= 0, 'bufnr: Cannot use 0 as a buffer number')
  return vim.api.nvim_buf_is_valid(bufnr)
end

---@param bufnr number
---@return boolean
function buffer.is_invalid(bufnr)
  assert(type(bufnr) == 'number', 'bufnr: Must be a number')
  assert(bufnr ~= 0, 'bufnr: Cannot use 0 as a buffer number')
  return not vim.api.nvim_buf_is_valid(bufnr)
end

buffer.defined = buffer.is_valid
buffer.undefined = buffer.is_invalid
buffer.get_id = buffer.id


---@param bufnr number
---@return number?
function buffer.get_line_count(bufnr)
  return buffer.id(bufnr, {
    ok = function(buf)
      return true, vim.api.nvim_buf_line_count(buf)
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@class buffer_rm_opts
---@field force? boolean (default: true)
---@field unload? boolean (default: false)

---@param bufnr number
---@param opts? buffer_rm_opts
---@return boolean
function buffer.rm(bufnr, opts)
  opts = opts or {}
  return buffer.id(bufnr, {
    ok = function(buf)
      local force = when_nil(opts.force, L(true), L(false))
      local unload = opts.unload
      return (pcall(
        vim.api.nvim_buf_delete,
        buf, { force = force, unload = unload }
      ))
    end,
    err = function()
      return false, nil
    end
  })
end

buffer.delete = buffer.rm

---@param bufnr number
---@return boolean
function buffer.exists(bufnr)
  return vim.fn.bufexists(bufnr) == 1
end

---@param bufnr number
---@return boolean
function buffer.is_loaded(bufnr)
  return vim.fn.bufloaded(bufnr) == 1
end

---@param bufnr number
---@param var string
---@return boolean, string?
function buffer.del_var(bufnr, var)
  local ok, buf = fix_bufnr(bufnr)
  if not ok then return false, buf end

  ok, value = buffer.get_var(buf, var)
  if not ok then
    return false, value
  end

  local msg
  ok, msg = pcall(vim.api.nvim_buf_del_var, buf, var)

  if ok then
    return true, value
  else
    return false, msg
  end
end

---@param bufnr number
---@param var string
---@return boolean, string?
function buffer.get_var(bufnr, var)
  return buffer.id(bufnr, {
    ok = function(buf)
      local ok, msg_or_value = pcall(vim.api.nvim_buf_get_var, buf, var)
      if ok then
        return true, msg_or_value
      else
        return false, msg_or_value
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@param vars []string
---@return boolean, buffer_result|string
function buffer.get_vars(bufnr, vars)
  return buffer.id(bufnr, {
    ok = function(buf)
      local result = { ok = {}, err = {} }
      for var in ipairs(vars) do
        local ok, msg_or_value = buffer.get_var(buf, var)
        if ok then
          result.ok[var] = msg_or_value
        else
          result.err[var] = msg_or_value
        end
      end
      return true, result
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@param var string
---@param value any
---@return boolean, any
function buffer.set_var(bufnr, var, value)
  return buffer.id(bufnr, {
    ok = function(buf)
      local ok, msg = pcall(vim.api.nvim_buf_set_var, buf, var, value)
      if ok then
        return true, value
      else
        return false, msg
      end
    end,
    err = function(msg)
      return false, msg
    end,
  })
end

---@param bufnr number
---@param values table<string,any>
---@return boolean, buffer_result|string
function buffer.set_vars(bufnr, values)
  return buffer.id(bufnr, {
    ok = function(buf)
      res = { ok = {}, err = {} }
      local res_ok = res.ok
      local res_err = res.err
      for var, value in ipairs(values) do
        local ok, value_or_msg = buffer.set_var(buf, var, value)
        if ok then
          res_ok[var] = value_or_msg
        else
          res_err[var] = value_or_msg
        end
      end
      return true, res
    end,
    err = function(msg) return false, msg end
  })
end

---@param bufnr? number
---@param name string
---@return boolean, any
function buffer.get_opt(bufnr, name)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg_or_value = pcall(vim.api.nvim_get_option_value, name, { buf = buf })
      if ok then
        return true, msg_or_value
      else
        return false, msg_or_value
      end
    end,
    err = function(msg) return false, msg end
  })
end

---@param bufnr number
---@param names []string
---@return boolean, buffer_result|string
function buffer.get_opts(bufnr, names)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      res = { ok = {}, err = {} }
      local res_ok = res.ok
      local res_err = res.err
      for _, name in ipairs(names) do
        local ok, value_or_msg = buffer.get_opt(buf, name)
        if ok then
          res_ok[name] = value_or_msg
        else
          res_err[name] = value_or_msg
        end
      end
      return true, res
    end,
    err = function(msg) return false, msg end
  })
end

---@param bufnr? number
---@param name string
---@param value any
---@return boolean, string?
function buffer.set_opt(bufnr, name, value)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = pcall(vim.api.nvim_set_option_value, name, value, { buf = buf })
      if ok then
        return ok, value
      else
        return false, msg
      end
    end,
    err = function(msg) return false, msg end
  })
end

---@param bufnr number
---@param values table<string, any>
---@return boolean, buffer_result|string
function buffer.set_opts(bufnr, values)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      res = { ok = {}, err = {} }
      for k, v in pairs(values) do
        local ok, msg = buffer.set_opt(buf, k, v)
        if ok then
          res.ok[k] = msg
        else
          res.err[k] = msg
        end
      end
      return true, res
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@class buffer_new_autocmd
---@field [1] string|[]string events
---@field [2] string|function command|callback()
---@field [3] table
---
---@class buffer_new_keymap
---@field [1] string|[]string modes
---@field [2] string keys
---@field [3] string|function command|callback()
---@field [4] table table<string,any>

---@class buffer_new_opts
---@field config? fun(buf: number)
---@field opts? table<string,any>
---@field vars? table<string,any>
---@field autocmd? []buffer_new_autocmd
---@field keymap? []buffer_new_keymap

---@param name? string
---@param opts? buffer_new_opts
---@return number?
function buffer.new(name, opts)
  opts = opts or {}
  name = name or vim.fn.tempname()
  local bufnr = vim.fn.bufnr(name, true)

  if bufnr == -1 then
    return nil
  end

  local vars = opts.vars
  local options = opts.opts
  local config = opts.config
  local autocmds = opts.autocmd or opts.hooks
  local keymaps = opts.keymap or opts.mappings

  if options then
    for k, v in pairs(options) do
      vim.api.nvim_set_option_value(k, v, { buf = bufnr })
    end
  end

  if vars then
    for k, v in pairs(vars) do
      vim.api.nvim_buf_set_var(bufnr, k, v)
    end
  end

  if config then
    vim.api.nvim_buf_call(bufnr, function() config(bufnr) end)
  end

  vim.api.nvim_buf_call(bufnr, function()
    vim.keymap.set('n', 'q', ':call HideWindowIfPossible()', { desc = 'Hide window', buffer = vim.fn.bufnr() })
    vim.keymap.set('n', 'Q', ':call WipeoutBufferWindowIfPossible()', { desc = 'Hide window', buffer = vim.fn.bufnr() })
  end)

  if keymaps then
    for i, spec in ipairs(keymaps) do
      assert(
        type(spec) == 'table' and #spec >= 3,
        sprintf('%s', 'specs[%d]: Expected at least 3 arguments, got %s', i, spec)
      )
      local modes, keys, command, o = unpack(spec)
      o = vim.deepcopy(o or {})
      o.buffer = bufnr
      vim.keymap.set(modes, keys, command, o)
    end
  end

  if autocmds then
    for i, au in ipairs(autocmds) do
      assert(
        type(au) == 'table' and #au >= 2,
        sprintf('%s', 'autocmds[%d]: Expected at least 2 arguments, got %s', i, au)
      )

      local event, command, o = unpack(au)
      o = vim.deepcopy(o or {})
      o.buffer = bufnr

      if type(command) == 'string' then
        o.command = command
      else
        o.callback = command
      end

      vim.api.nvim_create_autocmd(event, o)
    end
  end

  return bufnr
end

---@param bufnr
---@return boolean, table<string|number, number>
function buffer.get_word_count(bufnr)
  return buffer.call(bufnr, function()
    return vim.fn.wordcount()
  end)
end

---@param bufnr number
---@param linenum number
---@return boolean, string?
function buffer.get_line(bufnr, linenum, strict_indexing)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = pcall(vim.api.nvim_buf_get_lines, buf, linenum, linenum + 1, strict_indexing)
      if ok then
        if #msg == 1 and msg[1] == "" then
          return true, nil
        else
          return true, msg[1]
        end
      else
        return false, msg
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@param start_row number
---@param end_row number
---@param strict_indexing? boolean
---@return boolean, ([]string)?
function buffer.get_lines(bufnr, start_row, end_row, strict_indexing)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = pcall(vim.api.nvim_buf_get_lines, buf, start_row, end_row, strict_indexing)
      if ok then
        if #msg == 1 and msg[1] == "" then
          return true, nil
        else
          return true, msg
        end
      else
        return false, msg
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@return boolean, number?
function buffer.get_current_linenum(bufnr)
  return buffer.call(bufnr, function()
    return vim.fn.getpos(".")[2] - 1
  end)
end

---@param bufnr number
---@return boolean, number?
function buffer.get_current_line(bufnr)
  return buffer.call(bufnr, function()
    return vim.fn.getline('.')
  end)
end

---@param bufnr number
---@return boolean, boolean
---@return boolean, string?
function buffer.is_listed(bufnr)
  local ok, value = buffer.get_opt(bufnr, 'buflisted')
  if ok then
    return true, value
  else
    return false, value
  end
end

---@param bufnr number
---@return boolean, boolean
---@return boolean, string?
function buffer.is_unlisted(bufnr)
  local ok, value = buffer.get_opt(bufnr, 'buflisted')
  if ok then
    return true, not value
  else
    return false, value
  end
end

---@param bufnr number?
---@return boolean, []string?
function buffer.list(bufnr)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      return buffer.get_lines(buf, 0, -1, false)
    end,
    err = function(msg)
      return false, msg
    end,
  })
end

---@param bufnr number?
---@param sep? string (default: \\n)
---@return boolean, string?
function buffer.string(bufnr, sep)
  local ok, msg = buffer.list(bufnr)
  if ok then
    sep = sep or "\n"
    return true, table.concat(msg, sep)
  else
    return ok, msg
  end
end

---@class buffer_get_curpos_result
---@field [1] number
---@field [2] number
---@field [3] number
---@field [4] number
---@field lnum number
---@field col number
---@field off number
---@field curswant number

---This cannot be used with vim.fn.winrestview!
---@param bufnr number
---@return boolean, buffer_get_curpos_result?
function buffer.get_curpos(bufnr)
  return buffer.id(bufnr, {
    ok = function(buf)
      local ok, msg_or_winid = buffer.get_winid(bufnr)
      local winid

      if not ok then
        return false, msg_or_winid
      else
        winid = msg_or_winid
      end

      local out = vim.fn.getcurpos(winid)
      out[2] = out[2] - 1
      out.lnum = out[2]
      out.col = out[3]
      out.off = out[4]
      out.curswant = out[5]
      out.buf = buf
      out.winid = winid

      return true, out
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@return boolean, (number|string)?
function buffer.get_winnr(bufnr)
  return buffer.id(bufnr, {
    ok = function(buf)
      local winnr = vim.fn.bufwinnr(buf)
      local ok = winnr ~= -1

      if ok then
        return true, winnr
      else
        return false, sprintf("buffer[%d]: invalid winnr", buf)
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@return boolean, (number|string)?
function buffer.get_winid(bufnr)
  return buffer.id(bufnr, {
    ok = function(buf)
      local winid = vim.fn.bufwinid(buf)
      local ok = winid ~= -1
      if ok then
        return true, winid
      else
        return false, sprintf("buffer[%d]: invalid winid", buf)
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@return number?
function buffer.get_current_id()
  local bufnr = vim.fn.bufnr()
  if bufnr == -1 then
    return nil
  else
    return bufnr
  end
end

---@param bufnr number
---@return boolean, nil|string  (true, nil) or (false, error)
function buffer.set_current_id(bufnr)
  local ok, buf = fix_bufnr(bufnr)
  if not ok then return false, buf end
  return pcall(vim.api.nvim_set_current_buf, buf)
end

buffer.get_current = buffer.get_current_id
buffer.set_current = buffer.set_current_id

---@return boolean, (number|string)?
function buffer.get_current_winid()
  local exists = buffer.get_current_id()
  if exists ~= nil then
    return buffer.get_winid(exists)
  else
    return false, "Current buffer is not set"
  end
end

---@return boolean, number|string
function buffer.get_current_winnr()
  local exists = buffer.get_current_id()
  if exists ~= nil then
    return buffer.get_winnr(exists)
  else
    return false, "Current buffer is not set"
  end
end

---@param bufnr
---@return boolean, string|number
function buffer.is_visible(bufnr)
  return buffer.get_winid(bufnr)
end

---@param bufnr number
---@param patterns_or_pred []string|(fun(line: string): boolean)
---@return boolean, []string
function buffer.grep(bufnr, patterns_or_pred)
  local function matches(line)
    for i = 1, #patterns do
      if line:match(patterns[i]) then
        return true
      end
    end
  end

  return buffer.id(bufnr, {
    ok = function(buf)
      local ok, msg = buffer.list(buf)
      if not ok then
        return false, msg
      end

      local lines = msg
      if type(patterns_or_pred) == 'function' then
        local res = {}
        for i = 1, #lines do
          if patterns_or_pred(lines[i]) then
            res[#res + 1] = lines[i]
          end
        end
        if #res == 0 then
          return false, sprintf('buffer[%d]: No lines matched', buf)
        else
          return true, res
        end
      else
        local res = list.filter(lines, matches)
        if #res == 0 then
          return false, sprintf('buffer[%d]: No lines matched', buf)
        else
          return true, res
        end
      end
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@return boolean, buffer_get_curpos_result|string
function buffer.get_current_curpos()
  local id = buffer.get_current_id()
  if defined(id) then
    return buffer.get_curpos(id)
  else
    return false, "No current buffer"
  end
end

---@param bufnr number
---@param lines []string|string
---@param linenum number
---@return boolean, string?
function buffer.append_lines(bufnr, lines, linenum)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      lines = type(lines) == 'string' and vim.split(lines, "\n") or lines
      linenum = linenum + 1
      return buffer.set_lines(buf, linenum, linenum, lines)
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@param lines []string | string
---@param linenum number
---@return boolean, string?
function buffer.prepend_lines(bufnr, lines, linenum)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      lines = type(lines) == 'string' and vim.split(lines, "\n") or lines
      return buffer.set_lines(buf, linenum, linenum, lines)
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@return boolean, string?
function buffer.write(bufnr)
  return buffer.get_id(bufnr, {
    ok = function(buf)
      return buffer.call(buf, function(_buf)
        vim.cmd(':w!')
      end)
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@param bufnr number
---@return boolean, number|string
function buffer.wipeout(bufnr)
  return buffer.call(bufnr, function()
    vim.cmd('bwipeout! %')
    return bufnr
  end)
end

---@param bufnr number
---@param force? boolean
---@return boolean, number Return deleted winid
function buffer.hide(bufnr, force)
  return buffer.id(bufnr, {
    ok = function(buf)
      local ok, winid_or_msg = buffer.get_winid(bufnr)
      if not ok then
        return winid_or_msg
      end

      local winid = winid_or_msg
      vim.api.nvim_win_close(winid, force)
      return true, winid
    end,
    err = function(msg)
      return false, msg
    end
  })
end

function buffer.split_current(direction, resize)
  if direction == 'right' or direction == 'vsplit' or direction == 'v' then
    vim.cmd 'vsplit | wincmd l'
    if resize then
      vim.cmd(sprintf('vert resize %s', tostring(resize)))
    end
  else
    vim.cmd 'split | wincmd j'
    if resize then
      vim.cmd(sprintf('resize %s', tostring(resize)))
    end
  end
end

function buffer.split(bufnr, direction, resize)
  buffer.call(bufnr, function()
    if direction == 'right' or direction == 'vsplit' or direction == 'v' then
      vim.cmd 'vsplit | wincmd l'
      if resize then
        vim.cmd(sprintf('vert resize %s', tostring(resize)))
      end
    else
      vim.cmd 'split | wincmd j'
      if resize then
        vim.cmd(sprintf('resize %s', tostring(resize)))
      end
    end
  end)
end

function buffer.split_current_right(resize)
  return buffer.split_current('right', resize)
end

function buffer.split_current_below(resize)
  return buffer.split_current('s', resize)
end

function buffer.split_below(bufnr, resize)
  return buffer.split(bufnr, 's', resize)
end

function buffer.split_right(bufnr, resize)
  return buffer.split(bufnr, 'right', resize)
end

function buffer.find_next(bufnr, pattern, start_line)
  bufnr = bufnr or buffer.get_current()
  start_line = start_line or buffer.get_current_linenum(bufnr)
  local buffer_lc = buffer.get_line_count(bufnr)

  for i = start_line, buffer_lc do
    local line = buffer.get_line(bufnr, i)
    if line and line:match(pattern) then
      return i
    end
  end
end

function buffer.new_temp(name, opts)
  opts = opts or {}
  name = name or vim.fn.tempname()
  local on_input = opts.on_input
  local contents = opts.contents or opts.text or opts.string
  local bufnr = buffer.new(name, { opts = { buflisted = false } })
  local split = opts.split
  local resize = opts.resize
  local write = opts.write
  local delete_after = opts.delete_after or opts.rm_after
  local comment = opts.comment

  if on_input then
    comment = true
  end

  contents = defined(contents) and is.string(contents) and vim.split(contents, "\n") or contents
  contents = defined(contents) and comment and list.map(contents, function(x)
    return '# ' .. x
  end) or contents

  buffer.set_lines(bufnr, 0, -1, false, {})

  if contents then
    if on_input then list.push(contents, "") end
    buffer.set_lines(bufnr, 0, -1, true, contents)
  end

  if split then
    vim.keymap.set('n', 'q', '<cmd>bwipeout! %<CR>', { buffer = bufnr })
    buffer.split(buffer.get_current(), split, resize)
    buffer.set_current(bufnr)
    buffer.call(bufnr, function() vim.cmd 'normal! G' end)
  end

  if on_input then
    vim.keymap.set(
      'n', '<C-c><C-c>',
      function()
        local lines = buffer.list(bufnr)
        lines = list.filter(lines, function(x)
          if not x:match('^%s*#') then return x end
        end)

        if not (#lines == 0 or (#lines == 1 and lines[1] == '')) then
          on_input(lines)
        else
          on_input(false)
        end

        vim.cmd('bwipeout! %')
      end,
      { buffer = bufnr }
    )
  end

  if write then
    buffer.write(bufnr)
    if delete_after then
      local timer = vim.uv.new_timer()
      timer:start(delete_after, 0, vim.schedule_wrap(function()
        pcall(vim.fs.rm, name)
        buffer.wipeout(bufnr)
        timer:stop()
        timer:close()
      end))
    end
  end

  return bufnr
end

function buffer.get_dirname(bufnr)
  return vim.fs.dirname(buffer.get_name(bufnr))
end

---@param bufnr number
---@return boolean, string?
function buffer.get_filetype(bufnr)
  return buffer.get_opt(bufnr, 'filetype')
end

---@param bufnr number
---@param pat? []string|string (default: {'.git'})
---@param depth? number (default: 4)
---@return string?
function buffer.get_root_dir(bufnr, pat, depth)
  bufnr = bufnr or vim.fn.bufnr()
  pat = pat or { '.git' }

  if buffer.is_invalid(bufnr) then
    return nil
  end

  local bufname = buffer.get_name(bufnr)
  local ws = vim.fs.find(pat, { upward = true, limit = depth or 4 })
  pat = pat or { '.git' }
  depth = depth or 4

  if #ws == 0 then
    return vim.fs.dirname(bufname)
  else
    ws = vim.fs.dirname(ws[1])
    user_config.workspace[bufnr] = ws
    user_config.workspace[bufname] = ws
    dict.set(user_config.workspace, { ws, bufnr }, true)
    dict.set(user_config.workspace, { ws, bufname }, true)

    return ws
  end
end

---@param bufnr number
---@param opts? nvim.get_workspace.opts
---@return string?
function buffer.get_workspace(bufnr, opts)
  local final_opts = { buf = bufnr or buffer.current() }
  dict.merge(final_opts, opts)
  return nvim.get_workspace(final_opts)
end

---@class buffer_find_below_opts
---@field all? boolean (default: false)
---@field times? number (default: 1)
---@field jump? boolean
---@field strict? boolean

---@class buffer_find_return
---@field [1] number
---@field [2] string

---@param bufnr number
---@param start_row? number (default: <current linenum>)
---@param patterns []string|string|(fun(line): boolean)
---@param opts buffer_find_below_opts
---@return boolean, buffer_find_return|string?
function buffer.find_below(bufnr, start_row, patterns, opts)
  local _
  local ok, msg = fix_bufnr(bufnr)

  if not ok then
    return false, msg
  end

  opts = opts or {}
  local times = opts.times
  local jump = opts.jump
  local findall = opts.all
  local strict = opts.strict

  if times <= 0 then
    return false, buf_msg("No matches found")
  elseif (times > 1 or findall) and jump then
    err_buf_msg(bufnr, 'opts.times should be above 1, got %d', times)
  end

  local is_pred = type(patterns) == 'function'
  patterns = not is_pred and type(patterns) == 'string' and { patterns } or patterns
  local function matches(line)
    if is_pred then
      return patterns(line)
    end

    for i = 1, #patterns do
      if line:match(patterns[i]) then
        return true
      end
    end
  end

  local lc = vim.api.nvim_buf_line_count(bufnr)
  local lc0 = lc - 1

  if lc == 0 then
    return false, buf_msg(bufnr, "Empty buffer")
  end

  _, msg = buffer.get_current_linenum(bufnr)
  start_row = msg
  start_row = start_row < 0 and start_row + lc or start_row
  start_row = start_row + 1

  if start_row >= lc0 or start_row < 0 then
    if strict then
      return false, buf_msg(bufnr, 'start_row: 0 <= linenum < %d', lc)
    elseif start_row >= lc0 then
      start_row = lc0
    elseif start_row < 0 then
      start_row = 0
    end
  end

  if start_row == lc0 then
    return false, buf_msg(bufnr, "No matches found")
  end

  local results = {}
  local results_len = 0

  for i = start_row, lc0, 1 do
    if times == results_len then
      if jump then nvim_cmd('normal! %dG', i + 1) end
      return true, results
    end

    local linenum = i
    local _, line = buffer.get_line(bufnr, linenum)

    if line and matches(line) then
      results[results_len + 1] = { linenum, line }
      results_len = results_len + 1
    end
  end

  if results_len == 0 then
    return false, buf_msg(bufnr, "No matches found")
  end

  if jump then
    nvim_cmd('normal! %dG', results[1][1])
  end

  return true, results
end

---@class buffer_find_above_opts
---@field all? boolean (default: false)
---@field times? number (default: 1)
---@field jump? boolean
---@field strict? boolean

---@param bufnr number
---@param start_row? number (default: <current linenum>)
---@param patterns []string|string|(fun(line): boolean)
---@param opts buffer_find_above_opts
---@return boolean, buffer_find_return|string?
function buffer.find_above(bufnr, start_row, patterns, opts)
  local _
  local ok, msg = fix_bufnr(bufnr)

  if not ok then
    return false, msg
  end

  opts = opts or {}
  local times = opts.times or 1
  local jump = opts.jump
  local findall = opts.all
  local strict = opts.strict

  if times <= 0 then
    return false, buf_msg("No matches found")
  elseif (times > 1 or findall) and jump then
    err_buf_msg(bufnr, 'opts.times should be above 1, got %d', times)
  end

  local is_pred = type(patterns) == 'function'
  patterns = not is_pred and type(patterns) == 'string' and { patterns } or patterns
  local function matches(line)
    if is_pred then
      return patterns(line)
    end

    for i = 1, #patterns do
      if line:match(patterns[i]) then
        return true
      end
    end
  end

  local lc = vim.api.nvim_buf_line_count(bufnr)
  local lc0 = lc - 1

  if lc == 0 then
    return false, buf_msg(bufnr, "Empty buffer")
  end

  _, msg = buffer.get_current_linenum(bufnr)
  start_row = msg
  start_row = start_row < 0 and start_row + lc or start_row
  start_row = start_row + 1

  if start_row >= lc0 or start_row < 0 then
    if strict then
      return false, buf_msg(bufnr, 'start_row: 0 <= linenum < %d', lc)
    elseif start_row >= lc0 then
      start_row = lc0
    elseif start_row < 0 then
      start_row = 0
    end
  end

  if start_row == lc0 then
    return false, buf_msg(bufnr, "No matches found")
  end

  local results = {}
  local results_len = 0

  for i = lc0, start_row, -1 do
    if times == results_len then
      if jump then nvim_cmd('normal! %dG', i + 1) end
      return true, results
    end

    local linenum = i
    local _, line = buffer.get_line(bufnr, linenum)

    if line and matches(line) then
      results[results_len + 1] = { linenum, line }
      results_len = results_len + 1
    end
  end

  if results_len == 0 then return false, buf_msg(bufnr, "No matches found") end
  if jump then nvim_cmd('normal! %dG', results[1][1]) end

  return true, results
end

---@class buffer.find.opts
---@field after? number|boolean
---@field below? number|boolean
---@field before? number|boolean
---@field above? number|boolean
---@field jump? boolean
---@field strict? boolean

---@param bufnr number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return boolean, number?
function buffer.find(bufnr, start_row, pattern, opts)
end

---@param buf number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_below_cursor(buf, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.below = true
  opts.after = nil

  return buffer.find(buf, pattern, opts)
end

---@param buf number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_above_cursor(buf, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.above = true
  opts.below = nil

  return buffer.find(buf, pattern, opts)
end

---@param buf number
---@param linenum boolean | number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_below_and_goto(buf, linenum, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.below = linenum
  opts.above = nil
  opts.jump = true

  return buffer.find(buf, pattern, opts)
end

---@param buf number
---@param linenum boolean | number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_above_and_goto(buf, linenum, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.above = linenum
  opts.below = nil
  opts.jump = true

  return buffer.find(buf, pattern, opts)
end

---@param buf number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_below_cursor_and_goto(buf, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.below = true
  opts.after = nil
  opts.jump = true

  return buffer.find(buf, pattern, opts)
end

---@param buf number
---@param pattern string | string[]
---@param opts? buffer.find.opts
---@return number?
function buffer.find_above_cursor_and_goto(buf, pattern, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.above = true
  opts.below = nil
  opts.jump = true

  return buffer.find(buf, pattern, opts)
end

function buffer.if_valid_winnr(bufnr, opts)
  opts = opts or {}
  local ok = opts.ok or function(args) return args end
  local err_buf = opts.err_buf or function(...) end
  local err_winnr = opts.err_winnr or function(...) end

  bufnr = buffer.id(bufnr)
  if undefined(bufnr) then
    return err_buf { buf = bufnr }
  end

  local winnr = vim.fn.bufwinnr(bufnr)
  if winnr ~= -1 then
    return ok { buf = bufnr, winnr = winnr }
  else
    return err_winnr { buf = bufnr }
  end
end

function buffer.if_valid_winid(bufnr, opts)
  opts = opts or {}
  local ok = opts.ok or function(args) return args end
  local err_buf = opts.err_buf or function(_args) end
  local err_winid = opts.err_winid or function(_args) end

  bufnr = buffer.id(bufnr)
  if undefined(bufnr) then
    return err_buf {}
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    return ok { buf = bufnr, winid = winid }
  else
    return err_winid { buf = bufnr }
  end
end

---@class buffer.put.opts
---@field type? string (default: 'c')
---@field after? boolean (default: true)
---@field follow? boolean (default: true)

---@param bufnr? number
---@param lines string|string[]
---@param opts buffer.put.opts
---@return boolean, string?
function buffer.put(bufnr, lines, opts)
  opts = opts or {}
  lines_type, after, follow = opts.type, opts.after, opts.follow

  if is.string(lines) then
    if lines:match '\n' then
      lines = string.split(lines, "\n")
    else
      lines = { lines }
    end
  end

  lines = is.string(lines) and { lines } or lines
  lines_type = lines_type or 'c'
  after = (undefined(after) and true) or after
  follow = (undefined(follow) and true) or follow

  return buffer.call(bufnr, function(buf)
    vim.api.nvim_put(lines, lines_type, after, follow)
  end)
end

---@param bufnr number
---@param lines string|string[]
---@param follow? boolean
---@return boolean, string?
function buffer.put_after_cursor(bufnr, lines, follow)
  return buffer.put(bufnr, lines, { follow = follow })
end

---@param bufnr number
---@param lines string|string[]
---@param follow? boolean
---@return boolean, string?
function buffer.put_before_cursor(bufnr, lines, follow)
  return buffer.put(bufnr, lines, { follow = follow })
end

---Get dirname of buffer/path
---@param buf number|string? (default: 0)
---@return string?
function dirname(buf)
  if type(buf) == 'string' then
    if buf == '/' then
      return
    else
      return path.dirname(buf)
    end
  elseif not buffer.exists(buf) then
    return
  else
    return path.dirname(buffer.get_name(buf))
  end
end

---@param bufnr? number
---@param markers string|string[]
---@param depth? number (depth 4)
---@return boolean, string
function buffer.in_dir(bufnr, markers, depth)
  local ok, msg = fix_bufnr(bufnr or vim.fn.bufnr())
  assert(ok, msg)

  local function check_file(dir)
    for i = 1, #markers do
      local marker = dir .. '/' .. markers[i]
      if path.is_file(marker) or path.is_dir(marker) then
        return dir
      else
        return false
      end
    end
  end

  bufnr = msg
  depth = depth or 3
  local currentdir = dirname(buffer.get_name(bufnr))
  markers = as_list(markers)

  for _ = 1, depth do
    if check_file(currentdir) then
      return true, currentdir --[[@as string]]
    else
      currentdir = dirname(currentdir)
    end
  end

  return false, sprintf('buffer[%d]: Could not find marker path: %s', bufnr, markers)
end

---@param bufnr? number
---@param depth? number (default: 3)
---@return boolean, string?
function buffer.in_git_dir(bufnr, depth)
  return buffer.in_dir(bufnr, ".git", depth)
end

---@param bufnr? number
---@param depth? number (default: 3)
---@return boolean, string?
function buffer.in_nix_dir(bufnr, depth)
  return buffer.in_dir(bufnr, { "shell.nix", "default.nix" }, depth)
end

buffer.current = buffer.get_current
buffer.get_current = buffer.get_current_id
buffer.set_current = buffer.set_current_id
buffer.dirname = dirname
buffer.filename = buffer.get_name
buffer.root_dir = buffer.get_root_dir
buffer.git_dir = buffer.root_dir

-- Remove these shitty aliases
buffer.filetype = buffer.get_filetype
buffer.name = buffer.get_name
buffer.workspace = buffer.get_workspace
buffer.word_count = buffer.get_word_count
buffer.current_line = buffer.get_current_line
buffer.winid = buffer.get_winid
buffer.winnr = buffer.get_winnr
buffer.dirname = buffer.get_dirname
buffer.lines = buffer.get_lines
buffer.text = buffer.get_text
buffer.opt = buffer.get_opt
buffer.var = buffer.get_var

--- Fix these shitheads
local TODO = {
  'find family of functions',
}

local MISSING = {
  'del_keymap', 'set_keymap', 'get_keymap',
  'set_current',
}

buffer.returns[1].exists = buffer.exists
buffer.returns[1].defined = buffer.defined
buffer.returns[1].undefined = buffer.undefined
buffer.returns[1].is_loaded = buffer.is_loaded
buffer.returns[1].is_valid = buffer.is_valid
buffer.returns[1].is_invalid = buffer.is_invalid

buffer.returns[2].list = buffer.list
buffer.returns[2].string = buffer.string
buffer.returns[2].grep = buffer.grep
buffer.returns[2].append_lines = buffer.append_lines
buffer.returns[2].prepend_lines = buffer.prepend_lines
buffer.returns[2].set_lines = buffer.set_lines
buffer.returns[2].set_opt = buffer.set_opt
buffer.returns[2].get_opt = buffer.get_opt
buffer.returns[2].get_line = buffer.get_line
buffer.returns[2].get_lines = buffer.get_lines
buffer.returns[2].get_curpos = buffer.get_curpos
buffer.returns[2].is_listed = buffer.is_listed
buffer.returns[2].is_unlisted = buffer.is_unlisted
buffer.returns[2].is_visible = buffer.is_visible
buffer.returns[2].get_opts = buffer.get_opts
buffer.returns[2].get_vars = buffer.get_vars
buffer.returns[2].set_opts = buffer.set_opts
buffer.returns[2].set_vars = buffer.set_vars

return buffer
