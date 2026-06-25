local lutils = require('lua-utils')
local list = lutils.list
local validate = lutils.validate
local path_utils = lutils.path
local is = lutils.is
local copy = lutils.copy

nvim = { __module = true, __name = 'nvim' }

function nvim.replace_termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, false, true)
end

---Run ex string with `normal!`
---@param ... string
---@return boolean, string?
function nvim.normal(...)
  for _, cmd in ipairs({ ... }) do
    local ok, msg = pcall(vim.cmd, 'normal! ' .. nvim.termcode(cmd))
    if not ok then return false, msg end
  end

  return true, nil
end

function nvim.noh()
  vim.cmd ':noh'
end

function nvim.goto_next_search()
  nvim.normal 'n'
end

function nvim.goto_prev_search()
  nvim.normal 'N'
end

function nvim.region(as_list)
  as_list = when_nil(as_list, L(false))
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", false)
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  local ok, _region = pcall(vim.fn.getregion, vstart, vend, vim.empty_dict())

  if ok and _region then
    if as_list then
      return _region
    else
      return list.concat(_region, "\n")
    end
  end
end

--- Add the above to buffer API

function nvim.mode()
  return vim.fn.mode()
end

function nvim.in_visual_mode()
  local mode = nvim.mode()
  return mode == 'v' or mode == 'V' or mode == ''
end

function nvim.in_normal_mode()
  return nvim.mode() == 'n'
end

function nvim.ls(dirname, fullname)
  local res = {}
  local abspath = fullname and vim.fs.abspath(dirname)

  for f in vim.fs.dir(dirname) do
    if fullname then
      res[#res + 1] = abspath .. '/' .. f
    else
      res[#res + 1] = f
    end
  end

  return res
end

---@param s string
---@return boolean, any
function nvim.loadstring(s)
  local ok, msg = loadstring(s)
  if ok then
    return true, ok()
  else
    return false, msg
  end
end

function nvim.loadfile(f)
  local fh = io.open(f, 'r')
  if not fh then return end
  local lines = fh:read('*a')
  return nvim.loadstring(lines)
end

function nvim.require2path(require_string, dir)
  validate.require_string(require_string, 'string')
  validate.opt_runtimepath(dir, 'string')

  dir = when_nil(dir, partial(false, vim.fn.stdpath, 'config')) .. '/lua'
  require_string = vim.split(require_string, '[.]')
  local path = list.join(list(dir, require_string), '/')

  return path
end

function nvim.path2require(path)
  validate.path(path, 'string')

  local config_path = vim.fn.stdpath('config')
  if not path:match(config_path) then
    return false
  elseif not path:match('.lua$') then
    return false
  else
    path = path:gsub(config_path .. '/lua/', '')
    path = vim.split(path, '/')
    local len = #path
    path[len] = path[len]:gsub('[.]lua', '')
    path = list.join(path, '.')
  end

  return path
end

function nvim.is_file(file)
  return vim.fn.filereadable(file) == 1
end

function nvim.is_dir(file)
  return vim.fn.isdirectory(file) == 1
end

function nvim.require(require_path, callback)
  local path = nvim.require2path(require_path)
  local luafile = paste0(path, '.lua')
  local dirfile = paste0(path, '/init.lua')
  local mod

  if nvim.file_exists(luafile) then
    mod = require(require_path)
  elseif nvim.dir_exists(dirfile) then
    mod = require(require_path)
  end

  if mod then
    return defined(callback) and callback(mod) or mod
  else
    return false
  end
end

---@param prompt string?
---@param on_input function
---@param on_nothing? function
function nvim.input(prompt, on_input, on_nothing)
  vim.ui.input({ prompt = prompt or '% ' }, function(input)
    if not input then
      return false
    elseif #input > 0 then
      on_input(input)
    elseif on_nothing then
      on_nothing()
    end
  end)
end

function nvim.select(choices, prompt, on_choice, formatter)
  vim.ui.select(
    choices,
    { prompt = prompt, format_item = formatter },
    on_choice
  )
end

---@param str_or_fmt string
---@param ... string
---@return boolean, any
function nvim.exec(str_or_fmt, ...)
  return pcall(vim.nvim_exec, string.format(str_or_fmt, ...))
end

---@param str_or_fmt string
---@param ... string
---@return boolean, string?
function nvim.cmd(str_or_fmt, ...)
  return pcall(vim.cmd, string.format(str_or_fmt, ...))
end

---@param linenum number
---@return boolean, string?
function nvim.goto_linenum(linenum)
  local ok, msg = nvim.cmd('normal! %dG', linenum)
  if ok then
    return true, nil
  else
    return false, msg
  end
end

---Analogue to vim.fn.stdpath
---@param which string
---@param ... string any other path to append to create a new path
---@return string?
function nvim.stdpath(which, ...)
  local args = { ... }
  if #args == 0 then
    ---@diagnostic disable-next-line
    return vim.fn.stdpath(which)
  else
    return path_utils(vim.fn.stdpath(which), ...)
  end
end

---Add the error message to user_config.error and buffer 'user_config.error'
---@param msg string|string[]
---@return string[]
function nvim.push_err_msg(msg)
  local err_buf = vim.fn.bufnr("user_config.error", true)
  local curtime = strftime("%c")
  local fullmsg = string.format("[%s]: %s", curtime, msg)
  user_config.error[#user_config.error + 1] = fullmsg
  fullmsg = string.split(fullmsg, "\n")
  vim.api.nvim_buf_set_lines(err_buf, -1, -1, false, fullmsg)

  return fullmsg
end

---Call a function with pcall but append the errors to a separate buffer like emacs
---@param f function
---@param args any[]
---@return boolean, string?
function nvim.pcall(f, args)
  args = not is.pure_table(args) and { args } or args
  local ok, msg = pcall(f, unpack(args))

  if not ok then
    nvim.push_err_msg(msg)
    return false, msg
  else
    return true, msg
  end
end

---Require stuff from ~/.config/nvim/lua/
---@param path string Must be a require-compatible string
---@return boolean, any
function nvim.require(path)
  local require_path = path
  local config_dir = vim.fn.stdpath('config') .. '/lua'
  path = path_utils(config_dir, (path:gsub("%.", "/")))

  if path_utils.is_dir(path) then
    return nvim.pcall(require, require_path)
  end

  local file = path .. '.lua'
  if path_utils.is_file(file) then
    return nvim.pcall(require, require_path)
  end

  local msg = sprintf("require('%s') failed", path)
  nvim.push_err_msg(msg)

  return false, msg
end

strftime = vim.fn.strftime
strptime = vim.fn.strptime

---Messages buffer
---@type number?
user_config.buffer.messages = user_config.buffer.messages or vim.api.nvim_create_buf(true, false)

---Valid types of messages
---@typ  etable<string,boolean>
user_config.message_type = user_config.message_type or {
  'ok',
  'fatal',
  'warn',
  ok = true,
  fatal = true,
  warn = true
}

---Handle messaging module for debugging purposes
---@overload fun(msg: string, msg_type: string)
message = bless {}
local set_lines = vim.api.nvim_buf_set_lines
local msg_buf = message.buffer

function message:__call(msg, msg_type)
  if vim.fn.bufexists(msg_buf) ~= 1 then
    message.make_buf()
  end

  msg_type = msg_type or 'ok'
  if not user_config.message_type[msg_type] then
    errorf("msg_type: expected any of ok, fatal, warn, got %s", msg_type)
  end

  local _msg = msg
  msg = is.string(msg) and string.split(msg, "\n") or msg
  msg = copy.copy(msg)
  msg[1] = sprintf('[%s] <%s> %s', string.upper(msg_type), os.date(), msg[1])

  if is.string(_msg) then
    print(_msg)
  else
    print(table.concat(msg, "\n"))
  end

  local lc = vim.api.nvim_buf_line_count(msg_buf)
  if lc == 0 then
    set_lines(msg_buf, 0, -1, false, msg)
  else
    set_lines(msg_buf, -1, -1, false, msg)
  end
end

function message.make_buf()
  if vim.fn.bufexists(msg_buf) == 1 then
    return msg_buf
  else
    user_config.buffer.messages = vim.api.nvim_create_buf(true, false)
    msg_buf = user_config.buffer.messages
    return msg_buf
  end
end

function message.warn(msg)
  message(msg, 'warn')
end

function message.ok(msg)
  message(msg, 'ok')
end

function message.fatal(msg)
  message(msg, 'fatal')
end

function message.error(msg, ...)
  message(msg, 'fatal')
  errorf(...)
end

--- Is message buffer valid?
function message.is_buf_valid()
  local buf = user_config.buffer.messages
  if buf and vim.fn.bufexists(buf) == 1 then
    return true
  end

  return false
end

---Is message buffer visible?
function message.is_buf_visible()
  return message.is_buf_valid() and vim.fn.bufwinid(msg_buf) ~= -1
end

---Show message before
---@param split? string (valid: v, s, vsplit, split)
function message.show(split)
  if message.is_buf_visible() then
    return
  end

  local right
  split = split or 's'

  if split:match 'v' or split:match 'right' then
    right = true
  end

  if right then
    nvim.cmd("vsplit | wincmd l | b %s", msg_buf)
  else
    nvim.cmd('split | wincmd j | b %s', msg_buf)
  end
end

nvim.message = nvim.message or message
nvim.msg = nvim.message
nvim.warn = nvim.msg.warn
nvim.fatal = nvim.msg.fatal
nvim.ok = nvim.msg.ok

return nvim
