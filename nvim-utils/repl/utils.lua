local list = require 'lua-utils.list'
local dict = require 'lua-utils.dict'
local buffer = require 'nvim-utils.buffer_utils'
local nvim = require 'nvim-utils.nvim'
local terminal = require 'nvim-utils.terminal'
local utils = {}


---@class filetype.root
---@field check_depth? number
---@field depth? number

---@class repl.config.get_config.return
---@field root filetype.root
---@field repl? repl.opts

---@class repl.cmd.pattern.args
---@field buf number
---@field file string
---@field workspace string
---@field dir string

---@class repl.cmd.maker.args : repl.cmd.pattern.args

---@alias repl.cmd.maker string|string[]|(fun(args: repl.cmd.maker.args): string)
---@alias repl.cmd.pattern string|string[]|(fun(args: repl.cmd.maker.args): boolean)
---@alias repl.cmd repl.cmd.maker|table<repl.cmd.pattern,repl.cmd.maker>

---@param bufnr number
---@return filetype?
function utils.get_ft_config(bufnr)
  bufnr = bufnr or buffer.current()
  local ft = buffer.get_filetype(bufnr)

  if ft ~= nil then
    ---@type filetype
    return user_config.filetype[ft]
  end
end

---@param args repl.cmd.pattern.args
---@param maker repl.cmd.maker
---@return string?
function utils.make_cmd_from_maker(args, maker)
  if is.string(maker) then
    ---@diagnostic disable-next-line
    return maker
  elseif is.callable(maker) then
    return maker(args)
  elseif is.pure_list(maker) then
    ---@diagnostic disable-next-line
    return maker
  end

  return nil
end

---@param args repl.cmd.pattern.args
---@param pattern repl.cmd.pattern
---@param maker repl.cmd.maker
---@return string?
function utils.make_cmd_from_pattern(args, pattern, maker)
  if is.callable(pattern) and pattern(args) then
    return utils.make_cmd_from_maker(args, maker)
  elseif is.string(pattern) and string.match(args.file, pattern) then
    return utils.make_cmd_from_maker(args, maker)
  elseif is.pure_list(pattern) then
    for i = 1, #pattern do
      if string.match(args.file, pattern[i]) then
        return utils.make_cmd_from_maker(args, maker)
      end
    end
  end
end

---@param args repl.cmd.maker.args
---@param specs table<repl.cmd.pattern,repl.cmd.maker>
---@return string?
function utils.make_cmd_from_dict(args, specs)
  for pattern, maker in pairs(specs) do
    local cmd = utils.make_cmd_from_pattern(args, pattern, maker)
    if cmd then
      return cmd
    end
  end
end

---@param bufnr? number
---@return repl.config.get_config.return?
function utils.get_config(bufnr)
  bufnr = bufnr or buffer.current()
  local ft = buffer.get_filetype(bufnr)

  if not ft then
    return
  end

  local ft_config = utils.get_ft_config(bufnr)
  if not ft_config or not ft_config.repl then
    printf("No REPL configuration exists for filetype %s", ft)
    return { root = { depth = 4 } }
  end

  return {
    root = { depth = 4 },
    repl = ft_config.repl,
  }
end

---@param bufnr? number
---@param config? table
function utils.get_cmd(bufnr, config)
  bufnr = bufnr or buffer.current()
  local ft = buffer.get_filetype(bufnr)
  local ftconfig = config or utils.get_config(bufnr)
  config = config or ftconfig

  if not config or not config.repl then
    printf('No command found for %s', ft)
    return
  else
    config = config.repl
  end

  local cmd = config.cmd or config.command
  if not cmd then
    return
  end

  local workspace = utils.get_workspace(bufnr, ftconfig)
  local args = {
    buf = bufnr,
    file = buffer.filename(bufnr),
    workspace = workspace
  }

  if is.callable(cmd) then
    return cmd(args)
  elseif is.dict(cmd) then
    return utils.make_cmd_from_dict(args, cmd)
  elseif is.string(cmd) or is.pure_list(cmd) then
    return cmd
  end
end

---@param bufnr? number
---@param config filetype
---@return number
function utils.get_depth(bufnr, config)
  config = config or utils.get_config(bufnr)
  config = config.root --[[@as repl.opts.root]]
  return config and (config.check_depth or config.depth) or 4
end

---@param bufnr? number
---@param config? filetype
---@return string?
function utils.get_workspace(bufnr, config)
  local depth = utils.get_depth(bufnr, config)
  return nvim.get_workspace { buf = bufnr, depth = depth }
end

return utils
