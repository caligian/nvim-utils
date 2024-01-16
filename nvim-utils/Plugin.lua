require "nvim-utils.Autocmd"
require "nvim-utils.Kbd"
require "nvim-utils.logger"

Plugin = class("Plugin", {
  "setup_lazy",
  "loadfile_all",
  "require_all",
  "list",
  "configure_all",
  "lazy_spec",
})

function Plugin:init(name, opts)
  if user.plugins.exclude[name] then
    return
  end

  if is_string(name) and user.plugins[name] and Plugin.is_a(user.plugins[name]) then
    return user.plugins[name]
  elseif is_table(name) then
    local given_opts = copy(name)
    local name = given_opts.name or given_opts[1]
    given_opts.name = nil

    if given_opts[1] then
      table.remove(given_opts, 1)
    end

    assert_is_a.string(name)

    return Plugin(name, given_opts)
  end

  opts = opts
    or {
      autocmds = false,
      mappings = false,
      user_config_require_path = "user.plugins." .. name,
      config_require_path = "core.plugins." .. name,
      setup = function() end,
      spec = {},
    }

  self.configureall = nil
  self.loadfile_all = nil
  self.lazy_spec = nil
  self.main = nil
  self.setup_lazy = nil
  self.require_all = nil
  opts = copy(opts)
  opts.name = name
  dict.merge(self, { opts })

  user.plugins[self.name] = self

  return self
end

function Plugin.list()
  local p = Path.join(vim.fn.stdpath "config", "lua", "core", "plugins")

  local fs = glob(p, "*")
  fs = list.filter(fs, function(x)
    if Path.is_dir(x) then
      local xp = Path.join(p, "init.lua")
      if Path.is_file(xp) then
        return true
      end
    elseif Path.is_file(x) and x:match "%.lua$" then
      return true
    end
  end, function(x)
    return (Path.basename(x):gsub("%.lua", ""))
  end)

  return fs
end

function Plugin:loadfile()
  local name = self.name
  local luapath = req2path("core.plugins." .. name)
  local userluapath = req2path("user.plugins." .. name)
  local builtin, userconfig

  if not luapath and not userluapath then
    return
  end

  builtin = luapath and loadfile(luapath)
  userconfig = userluapath and loadfile(userluapath)

  local plug = Plugin(name)
  local _, okuserconfig

  if is_function(userconfig) then
    _, userconfig = pcall(userconfig)
  end

  if is_function(builtin) then
    _, builtin = pcall(builtin)
  end

  if is_table(builtin) and is_table(userconfig) then
    dict.merge(plug, { builtin, userconfig })
  elseif not builtin and not userconfig then
    return plug
  elseif is_table(builtin) then
    dict.merge(plug, { builtin })
  elseif is_table(userconfig) then
    dict.merge(plug, { userconfig })
  end

  return plug
end

function Plugin:require()
  local name = self.name
  local luapath = req2path("core.plugins." .. name)
  local userluapath = req2path("user.plugins." .. name)
  local builtin, userconfig

  builtin = luapath and requirex("core.plugins." .. name)
  userconfig = userluapath and requirex("user.plugins." .. name)
  local plug = Plugin(name)

  if is_table(builtin) and is_table(userconfig) then
    dict.merge(plug, { builtin, userconfig })
  elseif not builtin and not userconfig then
    return plug
  elseif is_table(builtin) then
    dict.merge(plug, { builtin })
  elseif is_table(userconfig) then
    dict.merge(plug, { userconfig })
  end

  return plug
end

function Plugin:configure()
  if self.setup then
    vim.schedule(function()
      self:setup()
    end)
  end

  vim.schedule(function()
    self:set_autocmds()
    self:set_mappings()
  end)

  return self
end

function Plugin.loadfile_all()
  local out = {}

  list.each(Plugin.list(), function(x)
    local m = requirem("core.plugins." .. x)
    if is_table(m) then
      out[x] = Plugin(x, m)
      out[x]:loadfile()
    end
  end)

  return out
end

function Plugin.require_all()
  local out = {}

  list.each(Plugin.list(), function(x)
    local m = requirem("core.plugins." .. x)

    if is_table(m) then
      out[x] = Plugin(x, m)
      out[x]:require()
    end
  end)

  return out
end

local function _set_autocmds(self, autocmds)
  autocmds = autocmds or self.autocmds
  if not autocmds or size(self.autocmds) == 0 then
    return
  end

  dict.each(autocmds, function(name, spec)
    name = "plugin." .. self.name .. "." .. name
    spec[2] = spec[2] or {}
    spec[2].name = name
    Autocmd(unpack(spec))
  end)
end

function Plugin:set_autocmds(autocmds)
  return pcall_warn(_set_autocmds, self, autocmds)
end

local function _set_mappings(self, mappings)
  mappings = mappings or self.mappings
  if not mappings or size(self.mappings) == 0 then
    return
  end

  local opts = mappings.opts or {}
  local mode = opts.mode or "n"

  dict.each(mappings, function(key, spec)
    assert(#spec == 4, "expected at least 4 arguments, got " .. dump(spec))

    local name = "plugin." .. self.name .. "." .. key

    spec[4] = not spec[4] and { desc = key }
      or is_string(spec[4]) and { desc = spec[4] }
      or is_table(spec[4]) and spec[4]
      or { desc = key }

    spec[4] = copy(spec[4])
    spec[4].desc = spec[4].desc or key

    dict.merge(spec[4], { opts })

    spec[4].name = name

    Kbd.map(unpack(spec))
  end)
end

function Plugin:set_mappings(mappings)
  return pcall_warn(_set_mappings, self, mappings)
end

local function _configure_all()
  list.each(Plugin.list(), function(x)
    local plug = Plugin(x)
    plug:require()
    plug:configure()
  end)
end

function Plugin.configure_all()
  return pcall_warn(_configure_all)
end

function Plugin.lazy_spec()
  local core = requirex "core.plugins"
  assert_is_a(core, "table")

  local specs = {}
  dict.each(core, function(name, spec)
    assert_is_a(spec[1], "string")

    local conf = spec.config
    function spec.config()
      local ok, msg = pcall(function()
        local plug = Plugin(name)

        plug:require()
        plug:configure()

        if conf and is_function(conf) then
          conf()
        end
      end)

      if not ok then
        print(msg)
      end
    end

    specs[#specs + 1] = spec
  end)

  return specs
end

function Plugin.setup_lazy()
  require("lazy").setup(Plugin.lazy_spec())
end

function Plugin.main()
  Plugin.setup_lazy()
end
