require "nvim-utils.Autocmd"

--- @class kbd
Kbd = class("Kbd", { static = {
  "main",
  "from_dict",
  "buffer",
  "map",
  "noremap",
} })

Kbd.buffer = ns()

local enable = vim.keymap.set
local delete = vim.keymap.del
local del = delete

function Kbd:opts()
  return dict.filter(self, function(key, _)
    return strmatch(
      key,
      "^buffer$",
      "^nowait$",
      "^silent$",
      "^script$",
      "^expr$",
      "^unique$",
      "^noremap$",
      "^desc$",
      "^callback$",
      "^replace_keycodes$"
    )
  end)
end

function Kbd:init(mode, ks, callback, rest)
  rest = rest or {}
  mode = mode or "n"
  local _rest = rest
  rest = is_string(_rest) and { desc = _rest } or _rest
  mode = is_string(mode) and strsplit(mode, "") or mode
  local command = is_string(callback) and callback
  callback = is_callable(callback) and callback
  local prefix = rest.prefix
  local noremap = rest.noremap
  local event = rest.event
  local pattern = rest.pattern
  local once = rest.once
  local buffer = rest.buffer
  local cond = rest.cond
  local localleader = rest.localleader
  local leader = rest.leader
  local name = rest.name
  local desc = rest.desc

  if prefix and (localleader or leader) then
    if localleader then
      ks = "<localleader>" .. prefix .. ks
    else
      ks = "<leader>" .. prefix .. ks
    end
  elseif localleader then
    ks = "<localleader>" .. ks
  elseif leader then
    ks = "<leader>" .. ks
  end

  self.mode = mode
  self.keys = ks
  self.command = command
  self.prefix = prefix
  self.noremap = noremap
  self.event = event
  self.pattern = pattern
  self.once = once
  self.buffer = buffer
  self.cond = cond
  self.localleader = localleader
  self.leader = leader
  self.name = name
  self.desc = desc
  self.enabled = false
  self.autocmd = false
  self.callback = callback

  if name then
    user.kbds[name] = self
  end

  return self
end

function Kbd:enable()
  if self.autocmd and Autocmd.exists(self.autocmd) then
    return self
  end

  local opts = self:opts()
  local cond = self.cond
  local callback

  if self.command then
    callback = self.command
  else
    callback = ""
    opts.callback = self.callback
  end

  if self.event and self.pattern then
    self.autocmd = Autocmd(self.event, {
      pattern = self.pattern,
      group = self.group,
      once = self.once,
      callback = function(au_opts)
        if cond and not cond() then
          return
        end

        opts = copy(opts)
        opts.buffer = au_opts.buf

        enable(self.mode, self.keys, callback, opts)
        self.enabled = true

        dict.set(user.buffers, { au_opts.buf, "kbds", au_opts.id }, self)
      end,
    })
  else
    enable(self.mode, self.keys, callback, opts)

    if opts.buffer and name then
      dict.set(user.buffers, { opts.buffer, "kbds", name }, self)
    end

    self.enabled = true
  end

  if name then
    dict.set(user.kbds, { name }, self)
  end

  return self
end

--- needs work
function Kbd:disable()
  if self.buffer then
    del(self.mode, self.keys, { buffer = self.buffer })
  elseif self.autocmd then
    dict.each(self.autocmd.buffers, function(bufnr, _)
      del(self.mode, self.keys, { buffer = bufnr })
    end)

    self.autocmd:disable()
  else
    del(self.mode, self.keys, {})
  end

  self.enabled = false

  return self
end

function Kbd.buffer:__call(buf, mode, ks, callback, opts)
  assert_is_a.number(buf)
  assert(vim.api.nvim_buf_is_valid(buf), "invalid buffer: " .. tostring(buf))

  opts = is_string(opts) and { desc = opts } or opts
  opts = copy(opts or {})
  opts.buffer = buf

  return Kbd(mode, ks, callback, opts)
end

function Kbd.buffer.map(buf, mode, ks, callback, opts)
  return Kbd.buffer(buf, mode, ks, callback, opts):enable()
end

function Kbd.buffer.noremap(buf, mode, ks, callback, opts)
  opts = is_string(opts) and { desc = opts } or opts
  opts = opts or {}
  opts.noremap = true

  return Kbd.buffer(buf, mode, ks, callback, opts):enable()
end

function Kbd.map(mode, ks, callback, opts)
  return Kbd(mode, ks, callback, opts):enable()
end

function Kbd.noremap(mode, ks, callback, opts)
  opts = is_string(opts) and { desc = opts } or opts
  opts = opts or {}
  opts.noremap = true

  return Kbd.map(mode, ks, callback, opts)
end

function Kbd.from_dict(specs)
  local out = {}

  for key, value in pairs(specs) do
    local opts = copy(value[4])

    if is_string(opts) then
      opts = { desc = opts }
    elseif not opts then
      opts = {}
    end

    if not opts.desc then
      opts.desc = key
    end

    opts.name = key

    value[4] = opts
    out[key] = Kbd.map(unpack(value))
  end

  return out
end

function Kbd.load_configs()
  return Kbd.from_dict(require_config "kbds" or {})
end

Kbd.main = vim.schedule_wrap(Kbd.load_configs)
