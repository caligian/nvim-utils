require 'lua-utils'

local dict = require 'lua-utils.dict'
local terminal = require 'nvim-utils.terminal'
local buffer = require 'nvim-utils.buffer_utils'
local utils = require 'nvim-utils.repl.utils'
local nvim = require 'nvim-utils.nvim'

---@class repl.opts.root
---@field check_depth? number
---@field depth? number

---@class repl.opts.file
---@field format? string
---@field use? boolean

---@class repl.opts.input
---@field file? repl.opts.file
---@field apply? (fun(str: string): string)
---@field cd? string|(fun(buf: number, bufname: string): string)

---@class repl.opts
---@field root?  repl.opts.root
---@field input? repl.opts.input
---@field filetype? string
---@field workspace? string
---@field buffer? number
---@field cmd? repl.cmd
---@field command? repl.cmd

---@class repl.terminal
---@field shell terminal
---@field filetype? terminal

---@class repl.class : class
---@field terminal? repl.terminal
---@field input? repl.opts.input
---@field root? repl.opts.root
---@field filetype? string
---@field cmd? repl.cmd
---@field workspace? string

---@class repl : repl.class : instance

---@type repl.class
---@overload fun(opts: repl.opts): repl
local repl = class 'repl'

function repl:initialize(opts)
  bufnr = bufnr or vim.fn.bufnr()
  if not buffer.exists(bufnr) then
    errorf('buffer[%d] does not exist', bufnr)
  end

  opts               = opts or {}
  local config_input = opts.input
  local config_root  = opts.root
  local cmd          = opts.cmd or opts.cmd
  local given_buf    = opts.buffer
  local given_ft     = opts.filetype
  local workspace    = opts.workspace
  local ftconfig, terminals

  if not given_buf and not given_ft then
    errorf("opts: Expected opts.buffer or opts.filetype, got %s", opts)
  elseif not given_ft then
    local ok
    ok, given_ft = buffer.get_filetype(given_buf)

    if not ok then
      error(given_ft)
    end
  elseif not given_buf then
    given_buf = vim.fn.bufnr()
  end

  ftconfig       = utils.get_config(given_buf)
  replconfig     = ftconfig and ftconfig.repl
  workspace      = workspace or utils.get_workspace(given_buf, ftconfig)
  cmd            = cmd or utils.get_cmd(given_buf, ftconfig)
  terminals      = {
    filetype = cmd and terminal(workspace, cmd),
    shell = terminal(workspace)
  }
  self.terminal  = terminals
  self.workspace = workspace
  self.input     = config_input or replconfig and replconfig.input
  self.root      = config_root or ftconfig.root
  self.cmd       = cmd
  self.command   = cmd
  self.filetype  = given_ft

  utils.put(self)
end

function repl:has_filetype()
  return self.terminal.filetype ~= nil
end

---@param repl_type string
---@param terminal_fn string
---@param fn? (fun(x: terminal): any)
function repl:on(repl_type, terminal_fn, fn)
  local term = self.terminal[repl_type]
  local termfn = term and term[terminal_fn]

  if term == nil then
    return
  elseif fn then
    return fn(termfn(term))
  else
    return termfn(term)
  end
end

---@param repl_type string
---@return boolean?
function repl:is_running(repl_type)
  if not self.terminal[repl_type] then
    return
  end

  ---@type terminal
  local term = self.terminal[repl_type]
  return term:is_running(term)
end

---If terminal is running, then call this function
---@generic T
---@param repl_type string
---@param fn (fun(x: repl): T)
---@return T?
function repl:if_running(repl_type, fn)
  if self:is_running(repl_type) then
    return fn(self.terminal[repl_type])
  end
end

---@param repl_type string
---@param s string
function repl:send(repl_type, s)
  ---@type terminal
  local ft_term = self.terminal.filetype
  ---@type terminal
  local sh_term = self.terminal.shell

  if repl_type == 'shell' then
    return sh_term:send(s)
  end

  local use_file = self.input and self.input.file and self.input.file.use
  local file_string = use_file and self.input.file.format
  local apply = self.input and self.input.apply

  if not use_file then
    if apply then
      ft_term:send(apply(s))
    else
      ft_term:send(s)
    end
  else
    local filename = vim.fn.tempname()
    local fh = io.open(filename, 'w')

    if apply then
      fh:write(apply(s))
    else
      fh:write(s)
    end

    fh:close()
    s = file_string:format(filename)
    local timer = vim.uv.new_timer()

    timer:start(10000, 0, vim.schedule_wrap(function()
      pcall(vim.fs.rm, filename)
      timer:stop()
      timer:close()
    end))

    return terminal.send(ft_term, s)
  end
end

function repl:send_region(repl_type, bufnr)
  bufnr = bufnr or buffer.current()
  return buffer.call(bufnr, function()
    local region = nvim.region(false)
    if region then
      self:send(repl_type, region)
    end
  end)
end

function repl:send_buffer(repl_type, bufnr)
  bufnr = bufnr or buffer.current()
  self:send(repl_type, buffer.as_string(bufnr))
end

function repl:send_current_line(repl_type, bufnr)
  bufnr = bufnr or buffer.current()
  self:send(repl_type, buffer.get_current_line(bufnr))
end

function repl:send_ctrl_c(repl_type)
  return self:send(repl_type, '')
end

function repl:send_ctrl_z(repl_type)
  return self:send(repl_type, '')
end

function repl:send_ctrl_d(repl_type)
  return self:send(repl_type, '')
end

function repl:split(repl_type, direction, resize)
  local term = self.terminal[repl_type]
  if term == nil then
    return
  else
    return term:split(direction, resize)
  end
end

function repl:show(repl_type, direction, resize)
  local term = self.terminal[repl_type]
  if term == nil then
    return
  else
    return term:split(direction, resize)
  end
end

---@return boolean
function repl:start_filetype()
  local term = self.terminal.filetype
  if term and term:is_running() then
    return true
  end

  term = terminal(self.workspace, self.cmd)
  term:start()
  self.terminal.filetype = term

  return true
end

---@return boolean
function repl:start_shell()
  local term = self.terminal.shell
  if term and terminal.is_running(term) then
    return true
  end

  term = terminal(self.workspace)
  term:start()
  self.terminal.shell = term

  return true
end

---@param repl_type string
---@return terminal?
function repl:start(repl_type)
  if repl_type == 'shell' then
    self:start_shell()
  else
    self:start_filetype()
  end

  return self.terminal[repl_type]
end

function repl:stop(repl_type)
  local term = self.terminal[repl_type]
  if term == nil then
    return
  else
    return terminal.stop(term)
  end
end

function repl:split_right(repl_type, resize)
  local term = self.terminal[repl_type]
  if term == nil then
    return
  else
    return term:split_right(resize)
  end
end

function repl:split_below(repl_type, resize)
  local term = self.terminal[repl_type]
  if term == nil then
    return
  else
    return term:split_below(resize)
  end
end

function repl:cd_cwd(repl_type, bufnr)
  bufnr = bufnr or buffer.current()
  if repl_type == 'shell' then
    return self:send('shell', 'cd ' .. buffer.dirname(bufnr))
  end

  local cd_str = self.input and self.input.cd
  if not cd_str then
    printf("REPL.%s: Cannot cd into current buffer's directory", repl_type)
    return
  end

  local filename = buffer.filename(bufnr)
  if callable(cd_str) then
    self:send('filetype', cd_str(bufnr, filename))
  else
    assertf(is.string(cd_str), 'Expected string, got [%s] %s', type(cd_str), cd_str)
    self:send('filetype', string.format(cd_str, buffer.dirname(filename)))
  end
end

---@param repl_type string
function repl:hide(repl_type)
  if self.terminal[repl_type] then
    ---@type terminal
    local term = self.terminal[repl_type]
    term:hide()
  end
end

---@param bufnr? number
---@return repl?
function utils.get(bufnr)
  bufnr = bufnr or buffer.current()
  local ws = utils.get_workspace(bufnr)
  local ft = buffer.get_filetype(bufnr)
  local REPL = dict.get(user_config.state, { 'repl', ws, ft })

  if REPL then
    return REPL
  else
    return repl { workspace = ws, filetype = ft, buffer = bufnr }
  end
end

---@param x repl
function utils.put(x)
  dict.put(user_config.state, { 'repl', x.workspace, x.filetype }, x)
end

function utils.make_keymap_cmd(repl_type, fn)
  return function(...)
    local buf = buffer.current()
    local exists = utils.get(buf)
    return exists and exists[fn](exists, repl_type, ...)
  end
end

function utils.make_keymap(repl_type, modes, lhs, rhs, opts)
  rhs = utils.make_keymap_cmd(repl_type, rhs)
  vim.keymap.set(modes, lhs, rhs, opts)
end

function utils.make_keymaps(repl_type)
  return function(specs)
    for key, value in pairs(specs) do
      key = repl_type .. '.' .. key
      value = vim.deepcopy(value)
      local opts = value[4]
      opts.desc = opts.desc or key
      value[4] = opts
      utils.make_keymap(repl_type, unpack(value))
    end
  end
end

function utils.make_default_keymaps()
  utils.make_keymaps 'filetype' {
    start             = { "n", "<leader>rr", "start", {} },
    hide              = { "n", "<leader>rk", "hide", {} },
    send_current_line = { "n", "<leader>re", "send_current_line", {} },
    send_region       = { "v", "<leader>re", "send_region", {} },
    send_buffer       = { "n", "<leader>rb", "send_buffer", {} },
    split_right       = { "n", "<leader>rv", "split_right", {} },
    split_below       = { "n", "<leader>rs", "split_below", {} },
    stop              = { "n", "<leader>rq", "stop", {} },
    cd                = { "n", "<leader>r.", "cd_cwd", {} },
  }

  utils.make_keymaps 'shell' {
    start             = { "n", "<leader><enter><enter>", "start", {} },
    hide              = { "n", "<leader><enter>k", "hide", {} },
    send_current_line = { "n", "<leader><enter>e", "send_current_line", {} },
    send_region       = { "v", "<leader><enter>e", "send_region", {} },
    send_buffer       = { "n", "<leader><enter>b", "send_buffer", {} },
    split_right       = { "n", "<leader><enter>v", "split_right", {} },
    split_below       = { "n", "<leader><enter>s", "split_below", {} },
    stop              = { "n", "<leader><enter>q", "stop", {} },
    cd                = { "n", "<leader><enter>.", "cd_cwd", {} },
  }

  local function make_shell()
    user_config.repl.system = user_config.repl.system or terminal(os.getenv("HOME"))
    return user_config.repl.system
  end

  local function on_shell(fn, ...)
    local sh = make_shell()
    sh[fn](sh, ...)
  end

  local function make_shell_keymap(modes, lhs, fn, opts)
    vim.keymap.set(modes, lhs, function()
      on_shell(fn)
    end, opts)
  end

  local function make_shell_keymaps(specs)
    for key, value in pairs(specs) do
      key = 'shell.' .. key
      value = vim.deepcopy(value)
      local opts = value[4]
      opts.desc = opts.desc or key
      value[4] = opts
      make_shell_keymap(unpack(value))
    end
  end

  make_shell_keymaps {
    start             = { "n", "<leader>xx", "start", {} },
    hide              = { "n", "<leader>xk", "hide", {} },
    send_current_line = { "n", "<leader>xe", "send_current_line", {} },
    send_region       = { "v", "<leader>xe", "send_region", {} },
    send_buffer       = { "n", "<leader>xb", "send_buffer", {} },
    split_right       = { "n", "<leader>xv", "split_right", {} },
    split_below       = { "n", "<leader>xs", "split_below", {} },
    stop              = { "n", "<leader>xq", "stop", {} },
    cd_cwd            = { "n", "<leader>x.", "cd_cwd", {} },
  }
end

return repl
