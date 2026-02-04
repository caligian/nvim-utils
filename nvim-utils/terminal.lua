local buffer = require('nvim-utils.buffer')
local types = require('lua-utils.types')
local class = require('lua-utils.class')
local nvim = require('nvim-utils.nvim')
local validate = require 'lua-utils.validate'
local terminal = class 'terminal'

function terminal:initialize(cmd, cwd)
  cwd = not cwd and vim.fn.getcwd() or cwd
  self.command = cmd
  self.cmd = cmd
  self.cwd = cwd
  self.root_dir = cwd
  self.id = false
  self.pid = false
  self.buffer = false

  if types.callable(cmd) then
    cmd = cmd(cwd)
    validate.cmd(cmd, 'string')
    self.command = cmd
    self.cmd = cmd
  end
end

function terminal:send(s)
  return self:running(function (me)
    if me:invalid() then return false end
    if type(s) == 'table' then s = table.concat(s, "\n") end
    s = s .. "\r\n"
    vim.api.nvim_chan_send(me.id, s)
    return true
  end)
end

function terminal:send_region(bufnr)
  bufnr = ifnil(bufnr, buffer.current())
  local region = buffer.call(bufnr, nvim.region)
  if region then return self:send(region) end
end

function terminal:send_current_line(bufnr)
  bufnr = ifnil(bufnr, buffer.current())
  local line = buffer.current_line(bufnr)
  if line then return self:send(line) end
end

function terminal:send_buffer(bufnr)
  bufnr = ifnil(bufnr, buffer.current())
  local s = buffer.call(bufnr, function ()
    return buffer.as_string(bufnr)
  end)
  if s then return self:send(s) end
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

function terminal:stop()
  if self.id and self:running() then
    vim.fn.jobstop(self.id)
    self.id = false
    self.pid = false
    self.buffer = false

    printf(
      'Stopped REPL with command %s @ %s',
      self.cmd,
      self.cwd:gsub(os.getenv('HOME'), '~')
    )

    return true
  else
    return false
  end
end

function terminal:status(timeout)
  timeout = timeout or 0
  if self.id then
    return vim.fn.jobwait({self.id}, timeout)[1]
  else
    return false
  end
end

function terminal:running(callback)
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

function terminal:invalid()
  if not self.id then
    return true
  else
    return self:status(0) == -3
  end
end

function terminal:valid()
  if not self.id then
    return false
  else
    return not self:invalid()
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

function terminal:start()
  if self:invalid() then
    local bufnr, id = buffer.open_term(self.cmd, self.cwd)
    self.pid = buffer.get_var(bufnr, 'terminal_job_pid')
    self.buffer = bufnr
    self.id = id
    user_config.terminals[id] = self
    return self.id
  else
    return self.id
  end
end

function terminal:visible()
  if self.buffer and buffer.visible(self.buffer) then
    return true
  else
    return false
  end
end

function terminal:split(direction, resize)
  return self:running(function (me)
    if not me:visible() then
      buffer.split(buffer.current(), direction, resize)
      buffer.set_current(me.buffer)
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
  return self:running(function (me)
    if buffer.visible(me.buffer) then
      buffer.hide(me.buffer, true)
    end
  end)
end

return terminal
