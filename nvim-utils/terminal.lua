local path_utils = require 'lua-utils.path_utils'
local validate = require 'lua-utils.validate'

require('lua-utils.class')
require('nvim-utils.buffer')
require('nvim-utils.nvim')

---@class terminal
---@field command? string
---@field cmd? string
---@field cwd? string
---@field root_dir? string
---@field id? number
---@field pid? number
---@field buffer? number
terminal = class 'terminal'

---Contains terminal instances
---@type table<string,terminal>
user_config.terminal = user_config.terminal or {}
user_config.terminal_pid = user_config.terminal_pid or {}

local chansend = vim.api.nvim_chan_send
local jobstop = vim.fn.jobstop

function terminal:initialize(cmd, cwd)
  local cmd_is_fn = callable(cmd)

  assert(
    type(cmd) == 'string' or cmd_is_fn,
    'cmd: Expected string|fun(cwd: string): string, got ' .. tostring(cwd)
  )

  cwd = not cwd and vim.fn.getcwd() or cwd
  cmd = cmd_is_fn and cmd(cwd) or cmd

  assert(path_utils.is_dir(cwd), 'Invalid directory provided: ' .. cwd)

  self.command = cmd
  self.cmd = cmd
  self.cwd = cwd
  self.root_dir = cwd
  self.id = nil
  self.pid = nil
  self.buffer = nil
end

function terminal:send(s)
  return self:is_running(function(it)
    if it:is_invalid() then return false end
    if type(s) == 'table' then s = table.concat(s, "\n") end
    s = s .. "\r\n"
    chansend(it.id, s)

    return true
  end)
end

function terminal:send_region(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(_)
      local region = nvim.region(false)
      if region then
        return self:send(region)
      end
    end,
    err = function(msg)
      errorf(msg)
    end
  })
end

function terminal:send_buffer(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = buffer.string(buf)
      if not ok then
        error(msg)
      end

      local entire_buffer = msg
      self:send(entire_buffer)

      return entire_buffer
    end,
    err = function(msg)
      error(msg)
    end
  })
end

function terminal:send_current_line(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = buffer.get_current_line(buf)
      if not ok then
        error(msg)
      end

      local line = msg
      self:send(line)

      return line
    end,
    err = function(msg)
      error(msg)
    end
  })
end

function terminal:send_ctrl_c()
  return self:send('')
end

function terminal:send_ctrl_z()
  return self:send('')
end

function terminal:send_ctrl_d()
  return self:send('')
end

---@return boolean
function terminal:stop()
  return self:is_running(function(it)
    jobstop(it.id)
    buffer.wipeout(it.buffer)

    it.id = nil
    it.pid = nil
    it.buffer = nil

    printf(
      'Stopped REPL with command %s @ %s',
      self.cmd,
      self.cwd:gsub(os.getenv('HOME'), '~')
    )

    return true
  end)
end

function terminal:status(timeout)
  timeout = timeout or 0
  if self.id then
    return vim.fn.jobwait({ self.id }, timeout)[1]
  else
    return false
  end
end

terminal.get_status = terminal.status

function terminal:is_running(callback)
  local ok = self:status(0) == -1
  if ok then
    if callback then
      return callback(self)
    else
      return true
    end
  else
    return false
  end
end

function terminal:is_invalid()
  if not self.id then
    return true
  else
    return self:status(0) == -3
  end
end

function terminal:is_valid()
  if not self.id then
    return false
  else
    return not self:is_invalid()
  end
end

function terminal:exit_status()
  if not self.id then
    return false
  else
    local status = self:status()
    if status < 0 then return false end
    return status
  end
end

terminal.get_exit_status = terminal.exit_status

---Returns job id
---@return boolean, number|string
local function open_term(self)
  local bufnr = vim.api.nvim_create_buf(false, true)
  return buffer.call(bufnr, function()
    local is_nix_dir = path_utils.is_file(self.cwd .. '/shell.nix')
    local cmd = self.cmd
    local job_id
    local in_nix_shell = false

    if is_nix_dir then
      job_id = vim.fn.termopen('nix-shell', {cwd = self.cwd})
      in_nix_shell = true
    else
      job_id = vim.fn.termopen(cmd, {cwd = self.cwd})
    end

    if job_id == 0 or job_id == -1 then
      errorf("Could not start terminal with cmd `%s' in directory %s", self.cmd, self.cwd)
    else
      if in_nix_shell then
        if not cmd:match('/?(bash|zsh|csh|sh|fish|tcsh)$') then
          chansend(job_id, cmd .. "\r")
        end
      end

      self.id = job_id
      self.buffer = bufnr
      self.pid = vim.fn.jobpid(self.id)
    end

    return self.id
  end)
end

---@return boolean
function terminal:start()
  if self:is_running() then
    return true
  end

  local cmd, cwd = self.cmd, self.cwd
  local ok, msg = open_term(self)

  if not ok then
    return false, msg
  end

  ok = self:is_running(function(it)
    printf(
      'Started terminal with command `%s` @ buffer %d @ directory %s',
      cmd,
      it.buffer,
      cwd:gsub(os.getenv('HOME'), '~')
    )

    autocmd.set(
      'TermClose',
      function(args)
        local ok, msg = pcall(buffer.rm, args.buf)
        if not ok then
          printf('Could not delete terminal for %s', it.cmd)
        end
      end,
      {
        buffer = it.buffer,
        desc = sprintf('Delete terminal buffer for %s', it.cmd)
      }
    )

    keymap.set({ 'n' }, 'q', ':call HideWindowIfPossible()<CR>', {
      buffer = it.buffer,
      desc = 'Hide buffer'
    })

    keymap.set({ 'n' }, 'Q', ':call WipeoutWindowIfPossible()<CR>', {
      buffer = it.buffer,
      desc = 'Wipeout buffer'
    })

    user_config.terminal[self.id] = it
    user_config.terminal_pid[self.pid] = it

    return true
  end)

  if not ok then
    return false, sprintf('Could not start terminal with `%s` @ buffer %d', cmd, self.buffer)
  end

  return true, nil
end

function terminal:is_visible()
  return self:is_running(function(it)
    return buffer.is_visible(it.buffer)
  end)
end

function terminal:split(direction, resize)
  return self:is_running(function(it)
    if not it:is_visible() then
      buffer.split(buffer.get_current(), direction, resize)
      buffer.set_current(it.buffer)
      return true
    else
      return false
    end
  end)
end

function terminal:split_right(resize)
  return self:split('right', resize)
end

function terminal:split_below(resize)
  return self:split('split', resize or -5)
end

function terminal:hide()
  return self:is_running(function(it)
    if buffer.is_visible(it.buffer) then
      buffer.hide(it.buffer, true)
    end
  end)
end

-- term = terminal('python', '/home/Kerambit')
-- term:start()
-- print(term:is_running())
-- term:split()


return terminal
