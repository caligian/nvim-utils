require('lua-utils')

local list = require 'lua-utils.list'
local validate = require 'lua-utils.validate'
local path = require 'lua-utils.path_utils'
local dict = require 'lua-utils.dict'

local au = vim.api.nvim_create_autocmd
local setopt = vim.api.nvim_set_option_value
local defkey = vim.keymap.set
local setlines = vim.api.nvim_buf_setlines

---@class user_config.messages
---@field setup_done boolean
---@field file string
---@field buffer? number
user_config.messages = user_config.messages or {
  setup_done = false,
  file = user_config.path.messages_file,
  types = {
    'info',
    'ok',
    'fatal',
    'warn',
    info = true,
    ok = true,
    fatal = true,
    warn = true
  },
  buffer = nil,
}

local messages = user_config.messages
local msgs = user_config.messages
local nvim = {}

nvim.format_path = vim.fn.fnamemodify
nvim.formatp = nvim.format_path

local function append(msg, ...)
  msg = sprintf(msg, ...)
  msgs[#msgs + 1] = msg
  return msg
end

---@return number
function messages:make_buffer()
  if self.buffer and vim.fn.bufexists(self.buffer) == 1 then
    return self.buffer
  end

  au({ 'BufNew', 'BufNewFile' }, {
    pattern = self.file,
    callback = function(args)
      setopt('swapfile', false, { buf = args.buf })
    end,
    desc = 'Disable swapfile for messages'
  })

  au('BufEnter', {
    pattern = self.file,
    callback = function(args)
      defkey({ 'n' }, 'q', ':call HideWindowIfPossible()<CR>', { buffer = args.buf })
      defkey({ 'n' }, 'Q', ':call DeleteBufferWindowIfPossible()<CR>', { buffer = args.buf })
    end,
    desc = 'Hide messages buffer',
  })

  au({ "VimLeave" }, {
    pattern = messages.file,
    callback = function(args)
      vim.api.nvim_buf_call(args.buf, function()
        nvim.cmd(":wq!")
      end)
    end
  })

  au('BufDelete', {
    pattern = messages.file,
    callback = function(_)
      self.setup_done = false
      self.buffer = nil
    end
  })

  local buf = vim.fn.bufadd(user_config.path.messages_file)
  pcall(vim.fn.bufload, buf)
  self.buffer = buf
  user_config.buffer.messages = buf

  setopt('bufhidden', 'delete', { buf = buf })
  setopt('buflisted', false, { buf = buf })

  self.setup_done = true
  return self.buffer
end

function messages:exists()
  if not self.buffer then
    return false
  elseif self.buffer == -1 then
    return false
  else
    return vim.fn.bufexists(self.buffer) == 1
  end
end

---@param callback fun(bufnr: number, bufname: string): any
---@return any
function messages:if_exists(callback)
  if self:exists() then
    return callback(self.buffer, self.file)
  end
end

---@return number?
function messages:is_visible()
  local winid = vim.fn.bufwinid(self.buffer)
  if winid == -1 then
    return
  else
    return winid
  end
end

---@param callback fun(winid: number, bufnr: number, bufname: string): any
---@return any
function messages:if_visible(callback)
  return self:if_exists(function(bufnr, file)
    local winid = vim.fn.bufwinid(bufnr)
    if winid == -1 then
      return
    else
      return callback(winid, bufnr, file)
    end
  end)
end

---@param callback fun(winid: number, bufnr: number, bufname: string): any
---@return any
function messages:unless_visible(callback)
  return self:if_exists(function(bufnr, file)
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      return
    else
      return callback(winid, bufnr, file)
    end
  end)
end

---@return boolean?
function messages:hide(force)
  return self:if_visible(function(winid, _, _)
    vim.api.nvim_win_close(winid, force)
    return true
  end)
end

---@return boolean?
function messages:split_below()
  return self:unless_visible(function(_, bufnr, _)
    vim.cmd('split | wincmd j | b ' .. tostring(bufnr))
    return true
  end)
end

---@return boolean
function messages:split_right()
  return self:unless_visible(function(_, bufnr, _)
    vim.cmd('vsplit | wincmd l | b ' .. tostring(bufnr))
    return true
  end)
end

---@return number
function messages:setup()
  if not self.setup_done then
    self:make_buffer()
  elseif not self:exists() then
    self:make_buffer()
  end

  defkey(
    'n', '<leader>hm',
    function() messages:split_below() end,
    { desc = 'Split messages buffer' }
  )

  defkey(
    'n', '<leader>hM',
    function() messages:split_right() end,
    { desc = 'Vertically split messages buffer' }
  )

  return self.buffer
end

---@param msg string
---@param ... any
function messages:error(msg, ...)
  msg = sprintf(msg, ...)
  self:append('fatal', msg)
  error(msg)
end

---@param msg_type string (default: 'ok') any of ok, warn, fatal
---@param msg string string.format string
---@param ... any Objects to send to printf for stringification
---@return string
function messages:message(msg_type, msg, ...)
  msg = self:append(msg_type, msg, ...)
  print(msg)
  return msg
end

---Append message
---@param msg_type string
---@param msg string
---@param ... any
function messages:__call(msg_type, msg, ...)
  return self:message(msg_type, msg, ...)
end

---Append message
---@param msg_type string
---@param msg string
---@param ... any
function messages:append(msg_type, msg, ...)
  self:make_buffer()
  msg = sprintf(msg, ...)
  msg = sprintf('[%s] <%s> %s', string.upper(msg_type), os.date(), msg)
  local msg_buf = self:make_buffer()
  local lc = vim.api.nvim_buf_line_count(msg_buf)
  local lines = msg

  if is.string(msg) and msg:match("\n") then
    lines = string.split(msg, "\n")
  elseif is.string(msg) then
    lines = { msg }
  end

  if lc == 0 then
    setlines(msg_buf, 0, 0, false, lines)
  else
    setlines(msg_buf, 1, -1, false, lines)
  end

  append(msg)
  return msg
end

---@param msg string
---@param ... any
function messages:warn(msg, ...)
  self:message('warn', msg, ...)
end

---@param msg string
---@param ... any
function messages:ok(msg, ...)
  self:message('ok', msg, ...)
end

---@param msg string
---@param ... any
function messages:fatal(msg, ...)
  self:message('fatal', msg, ...)
end

---@param msg string
---@param ... any
function messages:info(msg, ...)
  self:message('info', msg, ...)
end

---Call any function and record any errors if thrown
---@param f function
---@param ... any
---@return boolean, any?
function messages:pcall(f, ...)
  local ok, msg = pcall(f, ...)
  if not ok then
    msg = msg or ('Error thrown by ' .. tostring(f))
    self:warn(msg)
    return false, msg
  else
    return true, msg
  end
end

---@param path string
---@return boolean, any
function messages:require(p)
  local ok, msg = pcall(require, p)
  if not ok then
    msg = msg or ('Could not require ' .. p)
    self:warn(msg)
  end

  return true, msg
end

---@param msg string
---@param ... any
function nvim.error(msg, ...)
  messages:error(msg, ...)
end

---@param msg_type string Refer to user_config.messages.types
---@param msg string
---@param ... any
---@return string
function nvim.msg(msg_type, msg, ...)
  msg = sprintf(msg, ...)
  messages:message(msg_type, msg)
  return msg
end

---@param msg string
---@param ... any
function nvim.msg_info(msg, ...)
  messages:message('info', msg, ...)
end

---@param msg string
---@param ... any
function nvim.msg_ok(msg, ...)
  messages:message('ok', msg, ...)
end

---@param msg string
---@param ... any
function nvim.msg_fatal(msg, ...)
  messages:message('fatal', msg, ...)
end

---@param msg string
---@param ... any
function nvim.msg_warn(msg, ...)
  messages:message('warn', msg, ...)
end

---@param p string
---@return boolean, any
function nvim.require(p)
  return messages:require(p)
end

---@param f function
---@param ... any
---@return boolean, any
function nvim.pcall(f, ...)
  return messages:pcall(f, ...)
end

---@param f function
---@param args any[]
---@param on_ok fun(result: any): any
---@param on_err fun(msg: string, args: any[]): any
---@return boolean, any
function nvim.xpcall(f, args, on_ok, on_err)
  local ok, msg = nvim.pcall(f, unpack(args))
  if ok then
    return true, ((on_ok and on_ok(msg)) or msg)
  end

  return false, ((on_err and on_err(msg, args)) or msg)
end

messages:setup()


---@param keys string
---@param mode? string
---@param replace_termcodes? boolean
function nvim.feedkeys(keys, mode, replace_termcodes)
  mode = mode or 'm'
  replace_termcodes = (replace_termcodes == nil and true) or replace_termcodes
  vim.api.nvim_feedkeys(keys, mode, replace_termcodes)
end

function nvim.replace_termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, false, true)
end

---Run ex string with `normal!`
---@param ... string
---@return boolean, string?
function nvim.normal(...)
  for _, cmd in ipairs({ ... }) do
    local ok, msg = pcall(vim.cmd, 'normal! ' .. nvim.replace_termcodes(cmd))
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

---@param as_list? boolean
---@return (string|string[])?
function nvim.region(as_list)
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

---@param file string
---@return boolean, any
function nvim.loadfile(file)
  local ok, msg, fh
  ok, msg = io.open(file, 'r')

  if not ok then
    return false, msg
  end

  fh = msg
  local lines = io.read(fh, '*a')
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

function nvim.path2require(p)
  validate.path(p, 'string')

  local config_path = vim.fn.stdpath('config')
  if not p:match(config_path) then
    return false
  elseif not p:match('.lua$') then
    return false
  else
    p = p:gsub(config_path .. '/lua/', '')
    p = vim.split(p, '/')
    local len = #p
    p[len] = p[len]:gsub('[.]lua', '')
    p = list.join(p, '.')
  end

  return p
end

function nvim.is_file(file)
  return vim.fn.filereadable(file) == 1
end

function nvim.is_dir(file)
  return vim.fn.isdirectory(file) == 1
end

function nvim.require(require_path, callback)
  local p = nvim.require2path(require_path)
  local luafile = paste0(p, '.lua')
  local dirfile = paste0(p, '/init.lua')
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
    return path(vim.fn.stdpath(which), ...)
  end
end

---@param cmd string
---@param ... any
function nvim.system(cmd, ...)
  cmd = sprintf(cmd, ...)
  vim.cmd(sprintf(":! %s", cmd))
end

---@class nvim.get_workspace.opts
---@field buffer? number
---@field buf? number
---@field buffer? number
---@field file? string
---@field dir?  string
---@field directory? string
---@field filename? string
---@field depth? number
---@field check_depth? number
---@field cache? boolean (default: true)

---@param opts nvim.get_workspace.opts
---@return string?
function nvim.get_workspace(opts)
  opts = opts or { buf = vim.fn.bufnr() }

  local buf = opts.buffer or opts.buf
  local given_file = opts.file or opts.filename
  local given_dir = opts.dir or opts.directory
  local depth = opts.depth or opts.check_depth or 4
  local file_and_dir_given = given_file and given_dir
  local use_cache = (opts.cache == nil and true) or opts.cache

  assert(not file_and_dir_given, "Cannot use opts.file and opts.dir together")
  assert(not (buf and file_and_dir_given), "opts.buffer and opts.file and opts.buffer are mutually exclusive")

  if buf and use_cache then
    local exists = user_config.workspace[buf]
    if exists then
      return exists
    end
  end

  local start_dir
  if buf then
    start_dir = path.dirname(vim.api.nvim_buf_get_name(buf))
  elseif given_file then
    start_dir = path.dirname(given_file)
  elseif given_dir then
    start_dir = given_dir
  end

  local i = depth
  local home = os.getenv("HOME")
  local found = nil

  while i >= 0 do
    if path.is_git_dir(start_dir) then
      found = start_dir
      break
    elseif start_dir == '/' or start_dir == home then
      found = home
      break
    else
      start_dir = path.dirname(start_dir)
    end

    i = i - 1
  end

  if found then
    if buf then
      dict.put(user_config, { 'workspace', found, buf }, found)
      dict.put(user_config, { 'workspace', buf }, found)
    end
    return found
  end
end

strftime = vim.fn.strftime
strptime = vim.fn.strptime

return nvim
