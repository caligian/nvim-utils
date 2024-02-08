require "nvim-utils.Autocmd"
require "nvim-utils.Kbd"
require "nvim-utils.logger"

Plugin = class("Plugin", { static = {
  "setup_lazy",
  "list",
  "lazy_spec",
  "main",
} })

function Plugin:init(name, opts)
  if user.plugins.exclude[name] then
    return
  end

  if is_string(name) and user.plugins[name] then
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
      config_require_path = "core.plugins." .. name,
      setup = function() end,
      spec = {},
    }

  opts = copy(opts)
  opts.name = name
  dict.merge(self, opts)

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

function Plugin:load_config()
  return dict.merge(self, require_plugin(self.name) or {})
end

function Plugin:configure()
  local function setup()
    self:load_config()
    self:set_autocmds()
    self:set_mappings()

    if self.setup then
      self:setup()
    end
  end

  xpcall(function()
    if self.name == "colorscheme" or self.name == "statusline" then
      setup()
    else
      vim.schedule(setup)
    end
  end, function(msg)
    logger:warn(msg)
    logger:debug(dump(items(self)))
  end)
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
    spec[2].desc = spec[2].desc or name

    Autocmd(unpack(spec))
  end)
end

function Plugin:set_autocmds(autocmds)
  _set_autocmds(self, autocmds or self.autocmds or {})
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
    spec[4].name = key

    dict.merge(spec[4], opts)

    spec[4].name = name

    Kbd.map(unpack(spec))
  end)
end

function Plugin:set_mappings(mappings)
  mappings = mappings or self.mappings or {}
  _set_mappings(self, mappings)
end

function Plugin.lazy_spec()
  local core = require "core.plugins"
  assert_is_a(core, "table")

  local specs = {}
  dict.each(core, function(name, spec)
    assert_is_a(spec[1], "string")

    local conf = spec.config

    function spec.config()
      local plug = Plugin(name)

      plug:configure()

      if conf and is_function(conf) then
        pcall(conf)
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
