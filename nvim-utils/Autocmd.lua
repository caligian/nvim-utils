require "nvim-utils.state"

local enable = vim.api.nvim_create_autocmd
local disable = vim.api.nvim_del_autocmd
local getinfo = vim.api.nvim_get_autocmds
local create_augroup = vim.api.nvim_create_augroup

Autocmd = class("Autocmd", {
  static = { "loadfile", "load_configs", "main", "from_dict", "map", "find", "buffer" },
})

Autocmd.buffer = ns()

function Autocmd:init(event, opts)
  local pattern = opts.pattern
  local callback = opts.callback
  local group = opts.group or "MyGroup"
  local buffers = {}
  local name = opts.name
  local cb = opts.callback
  local once = opts.once
  local nested = opts.nested
  local command = opts.command
  local desc = opts.desc
  local buf = opts.buffer
  local callback

  if name then
    if group then
      name = group .. "." .. name
    end

    user.autocmds[name] = self
  end

  assert(cb or command, "expected command or callback")

  if not command then
    callback = function(au_opts)
      cb(au_opts)

      self.buffers[au_opts.buf] = true

      if name then
        dict.set(user.buffers, { au_opts.buf, "autocmds", au_opts.id }, self)
      end
    end
  end

  self.buffers = buffers
  self.event = event
  self.pattern = pattern
  self.group = group
  self.name = name
  self.callback = callback
  self.command = command
  self.buffer = buf

  opts = {
    pattern = pattern,
    command = command,
    callback = callback,
    nested = nested,
    once = once,
    group = group,
    desc = desc,
    buffer = buf,
  }

  if buf then
    assert(vim.api.nvim_buf_is_valid(buf), "expected valid buffer, got " .. tostring(buf))
  end

  if group then
    create_augroup(group, { clear = false })
  end

  self.id = enable(event, opts)
  user.autocmds[self.id] = self

  if name then
    user.autocmds[name] = self
  end

  return self
end

function Autocmd:unref(bufnr)
  local id = self:disable()

  if self.name then
    user.autocmds[self.name] = nil
  end

  if not id then
    return
  end

  if is_number(bufnr) then
    dict.unset(user.buffers, { bufnr, "autocmds", id })
    return
  end

  dict.each(user.buffers, function(bufnr, state)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      user.buffers[bufnr] = nil
    else
      dict.unset(state, { "autocmds", id })
    end
  end)
end

Autocmd.delete = Autocmd.unref

function Autocmd.buffer:__call(bufnr, event, opts)
  opts = copy(opts or {})
  opts.buffer = bufnr
  opts.pattern = nil

  return Autocmd(event, opts)
end

function Autocmd:exists()
  local found, msg = pcall(get, {
    group = self.group,
    event = self.event,
    buffer = self.buffers,
  })

  if not found then
    if msg and msg:match "Invalid .group." then
      create_augroup(self.group, {})
    end

    return
  end

  found = msg
  found = list.each(found, function(x)
    return self.id and x.id == self.id
  end)

  if #found > 0 then
    return self
  end
end

function Autocmd:disable()
  if not self:exists() then
    return
  end

  local id = self.id
  disable(id)

  self.id = nil

  return id
end

function Autocmd.find(spec)
  return getinfo(spec)
end

function Autocmd.from_dict(specs)
  assert_is_a(specs, function(x)
    return dict.is_a(x, function(arg)
      return is_list(arg) and #arg == 2 and is_dict(arg[2]) and arg[2].callback and arg[2].pattern
    end)
  end)

  local out = {}
  for key, value in pairs(specs) do
    value[2] = is_string(value[2]) and { desc = value[2] } or value[2]
    value[2].name = key
    value[2].desc = value[2].desc or key

    out[key] = Autocmd(unpack(value))
  end

  return out
end

function Autocmd.load_configs()
  return Autocmd.from_dict(require_config "autocmds" or {})
end

Autocmd.main = vim.schedule_wrap(function()
  return Autocmd.load_configs()
end)

return Autocmd
