require "nvim-utils.Autocmd"
require "nvim-utils.Async"
require "nvim-utils.Buffer.Buffer"
require "nvim-utils.Kbd"
require "nvim-utils.Template"

local lsp = require "nvim-utils.lsp"

Filetype = class("Filetype", {
  static = {
    "setup_lsp_all",
    "from_dict",
    "load_configs",
    "jobs",
    "list",
    "main",
    "list_configs",
    "_resolve",
    "get_workspace",
    "_find_workspace",
    "_get_command",
    "_get_command_and_opts",
  },
})

function Filetype._resolve(name)
  assert_is_a(name, union("Filetype", "string", "number"))
  if typeof(name) == "Filetype" then
    return name
  elseif is_number(name) then
    if Buffer.exists(name) then
      name = Buffer.get_option(name, "filetype")
    else
      return
    end
  end

  return user.filetypes[name]
end

function Filetype.query(ft, attrib, f)
  local obj = Filetype._resolve(ft)

  if not obj then
    return "invalid filetype " .. dump(ft)
  end

  obj = dict.get(obj, totable(attrib))

  if not obj then
    return false,
      string.format(
        "%s: invalid attribute: %s",
        dump(ft),
        dump(attrib)
      )
  end

  if f then
    return f(obj)
  end

  return obj
end

function Filetype._find_workspace(
  start_dir,
  pats,
  maxdepth,
  _depth
)
  maxdepth = maxdepth or 5
  _depth = _depth or 0
  pats = totable(pats or "%.git/$")

  if maxdepth == _depth then
    return false
  end

  if not Path.is_dir(start_dir) then
    return false
  end

  local children = Path.ls(start_dir, true)
  for i = 1, #pats do
    local pat = pats[i]
    for j = 1, #children do
      ---@diagnostic disable-next-line: need-check-nil
      if children[j]:match(pat) then
        return start_dir
      end
    end
  end

  return Filetype._find_workspace(
    Path.dirname(start_dir),
    pats,
    maxdepth,
    _depth + 1
  )
end

function Filetype.get_workspace(
  bufnr,
  pats,
  maxdepth,
  _depth
)
  if not Buffer.exists(bufnr) then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local ws = Filetype._find_workspace(
    Path.dirname(bufname),
    pats,
    maxdepth,
    _depth
  )
  if ws then
    return ws
  end

  local server =
    Filetype.query(Buffer.filetype(bufnr), "server")
  if not server then
    return
  end

  local lspconfig = require "lspconfig"
  server = totable(server)
  local config = is_string(server) and lspconfig[server]
    or lspconfig[server[1]]
  local root_dir_checker = server.get_root_dir
    or config.document_config.default_config.root_dir
    or config.get_root_dir

  if root_dir_checker then
    return root_dir_checker(bufname)
  else
    return find_workspace(bufname, pats, maxdepth, _depth)
  end
end

local function get_name(x)
  return Path.basename(x):gsub("%.lua", "")
end

function Filetype.list_configs()
  return list.map(
    Path.ls(user.config_dir .. "/lua/core/ft"),
    get_name
  )
end

function Filetype.load_configs()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):load_config()
  end)
end

--------------------------------------------------
local function create_command(spec)
  if is_string(spec) then
    return { buffer = spec }
  else
    return spec
  end
end

--------------------------------------------------
--[[
-- Same case for workspace and dir
-- form1:
{
  buffer = {
    --- such tables can be nested
    [function (x) return x:match 'nvim' end] = function (x) return 'luajit ' .. x end,
    [os.getenv('HOME')] = 'luajit'
  },
}

-- form2:
{
  buffer = 'luajit'
}
--]]

local match_command = ns()

function match_command:match_path(spec, path)
  local function add_path(s)
    return template(s, { path = path })
  end

  local function process(value)
    if is_string(value) then
      return add_path(value)
    elseif is_method(value) then
      local cmd, _ = value(path)
      if cmd then
        return add_path(cmd)
      end
    elseif is_table(value) then
      for key_1, value_1 in pairs(value) do
        local ok = (is_string(key_1) and path:match(key_1))
          or (is_method(key_1) and key_1(path))

        if ok then
          return process(value_1)
        end
      end
    end
  end

  return process(spec)
end

function match_command:match(bufnr, spec, cmd_for)
  local ok, msg = is_number(bufnr)
  if ok then
    ok, msg = Buffer.exists(bufnr)
  end
  if not ok then
    error(msg)
  end

  local bufname = Buffer.get_name(bufnr)
  local path
  if
    not (
      cmd_for == "workspace"
      or cmd_for == "buffer"
      or cmd_for == "dir"
    )
  then
    error(
      "expected any of workspace, dir, buffer, got "
        .. dump(cmd_for)
    )
  elseif cmd_for == "workspace" then
    path = Filetype.get_workspace(bufnr, spec.root_dir, 4)
    if not path then
      error("not in workspace: " .. bufname)
    end
  elseif cmd_for == "dir" then
    path = Path.dirname(bufname)
  else
    path = bufname
  end

  local ok = self:match_path(spec[cmd_for], path)
  if not ok then
    error("could not get any command for " .. path)
  end
  local opts = dict.filter(spec, function(key, _)
    return not (
      key == "buffer"
      or key == "workspace"
      or key == "dir"
      or key == "root_dir"
    )
  end)

  return ok, opts, path
end

function match_command:__call(spec)
  local function get_fn(fn_type)
    return function(bufnr)
      return self:match(bufnr, spec, fn_type)
    end
  end

  return {
    buffer = get_fn "buffer",
    workspace = get_fn "workspace",
    dir = get_fn "dir",
  }
end

function Filetype:get_command(bufnr, cmd_type, cmd_for)
  assert(is_string(cmd_type))
  assert(is_string(cmd_for))

  local spec = self[cmd_type]
  spec = is_string(spec) and { buffer = spec } or spec
  if not is_table(spec) then
    error("invalid spec given " .. dump(cmd_type))
  end
  local cmd_maker = match_command(spec)
  assert(
    cmd_maker[cmd_for],
    "cmd_for should be workspace, dir or buffer"
  )

  return cmd_maker[cmd_for](bufnr)
end

function Filetype:init(name)
  local already = Filetype._resolve(name)
  if already then
    return already
  end

  local luafile = name .. ".lua"

  self.name = name
  self.config_path =
    Path.join(user.config_dir, "lua", "core", "ft", luafile)
  self.config_require_path = "core.ft." .. name
  self.enabled = {
    mappings = {},
    autocmds = {},
  }
  self.jobs = {}
  self.trigger = false
  self.mappings = false
  self.autocmds = false
  self.buf_opts = false
  self.augroup = "UserFiletype"
    .. name:gsub("^[a-z]", string.upper)

  nvim.create.autocmd("FileType", {
    pattern = name,
    callback = function(_)
      pcall(function()
        self:load_config()
      end)
    end,
    desc = "load config for " .. self.name,
  })

  user.filetypes[self.name] = self

  --- @type Filetype
  return self
end

function Filetype:load_config()
  return dict.merge(self, require_ftconfig(self.name) or {})
end

function Filetype:map(mode, ks, cb, opts)
  local mapping = Kbd(mode, ks, cb, opts)
  mapping.event = "Filetype"
  mapping.pattern = self.name

  if mapping.name then
    self.enabled.mappings[mapping.name] = mapping
  end

  return mapping:enable()
end

function Filetype:create_autocmd(callback, opts)
  opts = copy(opts or {})
  opts = is_string(opts) and { name = opts } or opts
  opts.pattern = self.name
  opts.group = self.augroup
  opts.callback = function(au_opts)
    pcall_warn(callback, au_opts)
  end
  local name = opts.name
  local au = Autocmd("FileType", opts)

  if name then
    self.enabled.autocmds[name] = au
  end

  return au
end

function Filetype:set_autocmds(mappings)
  mappings = mappings or {}

  dict.each(mappings, function(name, value)
    local fun = value
    local opts = {}

    if is_table(value) then
      fun = value[1]
      opts = value[2] or opts
    end

    opts.name = name
    opts.desc = opts.desc or name

    self:create_autocmd(fun, opts)
  end)
end

function Filetype:set_mappings(mappings)
  mappings = mappings or self.mappings or {}

  dict.each(mappings, function(key, value)
    value[4] = copy(value[4] or {})
    value[4].event = "Filetype"
    value[4].pattern = self.name
    value[4].name = key
    value[4].desc = value[4].desc or key
    self.enabled.mappings[key] = Kbd.map(unpack(value))
  end)
end

function Filetype:set_buf_opts(buf_opts)
  buf_opts = buf_opts or self.buf_opts

  if not buf_opts then
    return
  end

  self:create_autocmd(function(opts)
    Buffer.set_options(opts.buf, buf_opts)
  end)
end

function Filetype:enable_triggers(trigger)
  trigger = trigger or self.trigger
  if not self.trigger then
    return
  end

  vim.filetype.add(self.trigger)
  return true
end

--function Filetype:get_command(bufnr, cmd_type, cmd_for)
--  if not Buffer.exists(bufnr) then
--    return
--  end

--  ---@diagnostic disable-next-line: param-type-mismatch
--  return Filetype._get_command_and_opts(bufnr, cmd_type, self:query(cmd_type), cmd_for)
--end

function Filetype:format_buffer_dir(bufnr)
  return self:format_buffer(bufnr, "dir")
end

function Filetype:format_buffer_workspace(bufnr)
  return self:format_buffer(bufnr, "workspace")
end

function Filetype:format_buffer(bufnr, cmd_for)
  local cmd, opts = self:get_command(
    bufnr,
    "formatter",
    cmd_for or "buffer"
  )
  if not cmd then
    return
  end
  local bufname = Buffer.get_name(bufnr)
  local name = self.name
    .. ".formatter."
    .. cmd_for
    .. "."
    .. bufname
  self.jobs[name] = Async.format_buffer(bufnr, cmd, opts)
  self.jobs[name]:start()

  return self.jobs[name]
end

function Filetype:compile_buffer_workspace(bufnr, action)
  return self:compile_buffer(bufnr, action, "workspace")
end

function Filetype:compile_buffer_dir(bufnr, action)
  return self:compile_buffer(bufnr, action, "dir")
end

function Filetype:compile_buffer(bufnr, action, cmd_for)
  cmd_for = cmd_for or "workspace"
  local cmd, opts, p =
    self:get_command(bufnr, action, cmd_for)
  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname
  opts.split = true
  opts.shell = true

  if cmd_for ~= "buffer" then
    cmd = "cd " .. p .. " && " .. cmd
  end

  local j = Async(cmd, opts)

  Buffer.save(bufnr)
  j:start()

  self.jobs[name] = j
  return j
end

function Filetype:setup_lsp(specs)
  specs = specs or self.server
  if not specs then
    return
  end

  specs = is_string(specs) and { specs } or specs
  if not specs then
    return
  end

  lsp.setup_server(specs[1], specs.config)

  return self
end

function Filetype:set_commands(commands)
  commands = commands or self.commands
  if not commands then
    return
  end

  nvim.create.autocmd("FileType", {
    pattern = self.name,
    callback = function(opts)
      dict.each(commands, function(name, cmd)
        cmd[2] = copy(cmd[2] or {})
        cmd[2].buffer = opts.buf
        nvim_command(name, cmd[1], cmd[2])
      end)
    end,
  })
end

function Filetype:setup()
  xpcall(function()
    self:load_config()
    self:set_buf_opts()
    self:set_commands()
    self:set_autocmds()
    self:set_mappings()
    self:set_templates()
  end, function(msg)
    logger:warn(msg .. "\n" .. dump(self:get_attribs()))
  end)
end

function Filetype.setup_lsp_all()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):load_config():setup_lsp()
  end)
end

function Filetype.main()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):setup()
  end)
end

function Filetype:set_templates()
  if
    not self.templates
    or (size(self.templates) == 0)
    or self.template
  then
    return
  end

  self.template = Template(self.name, "Filetype")
  self.template:add_template(self.templates)
  self.template:enable()

  return self.template
end
