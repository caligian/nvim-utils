local lutils = require 'lua-utils'
local types = lutils.types
local validate = lutils.validate
keymap = {define = {}}
setmetatable(keymap, keymap)
setmetatable(keymap.define, keymap.define)

function keymap.opts(opts)
  local name = opts.name
  local au_opts = {group = opts.group or 'user_config.keymaps'}
  local kbd_opts = {}
  local res = {
    autocmd = au_opts,
    keymap = kbd_opts,
    name = name
  }

  if name then
    validate.name(name, types.string)
  end

  if opts.event or opts.pattern then
    au_opts[1] = opts.event or 'BufRead'
    au_opts[2] = { pattern = opts.pattern or '*' }
    if name then au_opts[2].desc = name end
  elseif opts.filetype or opts.ft then
    local ft = opts.filetype or opts.ft
    validate.filetype(ft, types.string)

    au_opts[1] = 'FileType'
    au_opts[2] = {pattern = ft}

    if name then
      au_opts[4].desc = sprintf('filetype.%s.%s', ft, name)
    end
  end

  if name and not opts.desc then
    kbd_opts.desc = name
  end

  for key, value in pairs(opts) do
    if key ~= 'filetype'  and
      key ~= 'event' and
      key ~= 'pattern' and
      key ~= 'name'
    then
      kbd_opts[key] = value
    end
  end

  if #au_opts == 0 then
    res.autocmd = nil
  end

  res.name = name

  return res
end

function keymap.set(modes, lhs, rhs, opts)
  opts = keymap.opts(opts or {})
  local au_opts = opts.autocmd
  local kbd_opts = opts.keymap
  local name = opts.name

  if name then
    user_config.keymaps[name] = {
      args = {modes, lhs, rhs, kbd_opts},
      autocmd = opts.autocmd
    }
  else
    user_config.keymaps[#user_config.keymaps+1] = {
      args = {modes, lhs, rhs, kbd_opts},
      autocmd = opts.autocmd
    }
  end

  if au_opts then
    au_opts[2].callback = function (args)
      local _opts = vim.deepcopy(kbd_opts)
      _opts.desc = _opts.desc or name
      _opts.buffer = args.buf
      vim.keymap.set(modes, lhs, rhs, _opts)
    end
    vim.api.nvim_create_autocmd(au_opts[1], au_opts[2])
  else
    vim.keymap.set(modes, lhs, rhs, kbd_opts)
  end

  return {args = {modes, lhs, rhs, kbd_opts}, autocmd = au_opts}
end

function keymap:__call(modes, lhs, rhs, opts)
  if not lhs then
    validate.args(modes, types.table)
    lhs = modes[2] or modes.lhs
    rhs = modes[3] or modes.rhs
    opts = modes[4] or modes.opts or {}
    modes = modes[1] or modes.mode
  end

  return keymap.set(modes, lhs, rhs, opts)
end

function keymap.define:__index(name)
  return function (modes, lhs, rhs, opts)
    opts = vim.deepcopy(opts)
    opts.name = name
    return keymap(modes, lhs, rhs, opts)
  end
end

function keymap.define:__call(args)
  for key, value in pairs(args) do
    if type(key) == 'number' then
      keymap.set(unpack(value))
    else
      keymap.define[key](unpack(value))
    end
  end
end

return keymap
