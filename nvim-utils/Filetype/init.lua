require "nvim-utils.nvim"
require "nvim-utils.Autocmd"
require "nvim-utils.Job"
require "nvim-utils.Buffer"
require "nvim-utils.Buffer.Win"
require "nvim-utils.Kbd"

local utils = require "nvim-utils.Filetype.utils"
local cmds = require "nvim-utils.Filetype.commands"
local lsp = require "nvim-utils.Filetype.lsp"
local kbds = require "nvim-utils.Filetype.kbds"
local M = class("Filetype", {
  "buffer",
  "from_dict",
  "jobs",
  "list",
  "main",
})

M.buffer = namespace "Filetype.buffer"

function M:init(name)
  local already = utils.resolve(name)
  if already then
    return already
  end

  local luafile = name .. ".lua"

  self.name = name
  self.requires = {
    config = "core.filetype." .. name,
    user_config = "user.filetype." .. name,
  }
  self.paths = {
    config_path = Path.join(vim.fn.stdpath "config", "lua", "core", "filetype", luafile),
    user_config = Path.join(user.user_dir, "user", "filetype", luafile),
  }

  self.enabled = {
    mappings = {},
    autocmds = {},
  }

  self.jobs = {}
  self.trigger = false
  self.mappings = false
  self.autocmds = false
  self.buf_opts = false
  self.win_opts = false
  self.on = false
  self.augroup = "UserFiletype" .. name:gsub("^[a-z]", string.upper)

  nvim.create.autocmd("FileType", {
    pattern = name,
    callback = function(_)
      self:require()
    end,
  })

  user.filetypes[self.name] = self

  return self
end

function M.buffer:__call(bufnr)
  if not Buffer.exists(bufnr) then
    return
  end

  local ft = Buffer.filetype(bufnr)
  if #ft == 0 then
    return
  end

  return M(ft)
end

function M:require(use_loadfile)
  local use = use_loadfile and reqloadfilex or requirex
  local core_config = use(self.requires.config) or {}
  local user_config = Path.exists(self.paths.user_config) and use(self.requires.user_config) or {}

  return dict.merge(self, { core_config, user_config })
end

function M:loadfile()
  return self:require(true)
end

function M:map(mode, ks, cb, opts)
  local mapping = Kbd(mode, ks, cb, opts)
  mapping.event = "Filetype"
  mapping.pattern = self.name

  if mapping.name then
    self.enabled.mappings[mapping.name] = mapping
  end

  return mapping:enable()
end

function M:create_autocmd(callback, opts)
  opts = copy(opts or {})
  opts = is_string(opts) and { name = opts } or opts
  opts.pattern = self.name
  opts.group = self.augroup
  opts.callback = callback
  local name = opts.name
  local au = Autocmd("FileType", opts)
  if name then
    self.enabled.autocmds[name] = au
  end

  return au
end

function M:set_autocmds(mappings)
  mappings = mappings or {}
  dict.each(mappings, function(name, au) end)
end

function M:set_mappings(mappings)
  mappings = mappings or self.mappings or {}
  dict.each(mappings, function(key, value)
    value[4] = value[4] or {}
    value[4].event = "Filetype"
    value[4].pattern = self.name
    value[4].name = key
    value[4].desc = value[4].desc or key

    self.enabled.mappings[key] = Kbd.map(unpack(value))
  end)
end

function M:set_buf_opts(buf_opts)
  buf_opts = buf_opts or self.buf_opts
  if not buf_opts then
    return
  end

  self:create_autocmd(function(opts)
    Buffer.set_options(opts.buf, buf_opts)
    self.enabled.mappings[key] = kbd
  end)
end

function M:enable_triggers(trigger)
  trigger = trigger or self.trigger
  if not self.trigger then
    return
  end

  vim.filetype.add(self.trigger)
  return true
end

M.list_configs = utils.list_configs
M.find_workspace = utils.find_workspace
M.resolve = utils.resolve
M.get_workspace = utils.get_workspace
M.query = utils.query

function M:get_command(bufnr, cmd_type, cmd_for)
  if not Buffer.exists(bufnr) then
    return
  end

  return cmds.get_command_and_opts(bufnr, cmd_type, self:query(cmd_type), cmd_for)
end

function M:format_buffer_dir(bufnr)
  return self:format_buffer(bufnr, "dir")
end

function M:format_buffer_workspace(bufnr)
  return self:format_buffer(bufnr, "workspace")
end

function M:format_buffer(bufnr, cmd_for)
  local cmd, opts = self:get_command(bufnr, "formatter", cmd_for)

  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname

  cmd = template(cmd[2], { path = bufname }) or cmd[2]
  self.jobs[name] = Job.format_buffer(bufnr, cmd, opts)
  self.jobs[name]:start()

  return self.jobs[name]
end

function M:compile_buffer_workspace(bufnr, action)
  return self:compile_buffer(bufnr, action, "workspace")
end

function M:compile_buffer_dir(bufnr, action)
  return self:compile_buffer(bufnr, action, "dir")
end

function M:compile_buffer(bufnr, action, cmd_for)
  cmd_for = cmd_for or "workspace"
  local cmd, opts = self:get_command(bufnr, action, cmd_for)
  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname
  if #cmd == 2 then
    cmd = template(cmd[2], { path = cmd[1] }) or cmd[2]
    opts.show = true
    self.jobs[name] = Job(cmd, opts)

    if self.jobs[name] then
      self.jobs[name]:start()
      return self.jobs[name]
    end
  else
    pp(cmd)
  end
end

function M:setup_lsp(specs)
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

function M:set_commands(commands)
  commands = commands or self.commands
  if not commands then
    return
  end

  nvim.create.autocmd("FileType", {
    pattern = self.name,
    callback = function(opts)
      pcall_warn(function()
        dict.each(commands, function(name, cmd)
          cmd[2] = copy(cmd[2] or {})
          cmd[2].buffer = opts.buf
          mkcommand(name, cmd[1], cmd[2])
        end)
      end)
    end,
  })
end

function M:setup()
  self:require()
  self:set_buf_opts()
  self:set_commands()
  self:set_autocmds()
  self:set_mappings()
  self:set_mappings(kbds)
  self:setup_lsp()
end

function M.main()
  list.each(M.list_configs(), function(ft)
    M(ft):setup()
  end)
end

Filetype = M
