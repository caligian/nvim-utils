require 'nvim-utils.keymap'
require 'nvim-utils.repl.repl'

local is = require 'lua-utils.is'
local dict = require 'lua-utils.dict'

repl.utils = {}
local utils = repl.utils

dict.set_unless(user_config.repl, { 'shell' }, {})
dict.set_unless(user_config.repl, { 'repl' }, {})

local shells = user_config.repl.shell
local repls = user_config.repl.repl

---@param repl_type string
---@param bufnr number
---@param start? boolean
---@return repl?
function utils.get(repl_type, bufnr, start)
  bufnr = bufnr or vim.fn.bufnr() or -1
  if not buffer.exists(bufnr) then
    printf("No such buffer exists %d", bufnr)
    return
  end

  local _, ft = buffer.get_filetype(bufnr)
  local ftobj = user_config.filetype[ft]

  if ftobj == nil then
    printf("No specification for filetype %s", ft)
    return
  end

  local wd = ftobj and ftobj:get_root_dir(bufnr)
  wd = wd or buffer.get_root_dir(bufnr) or buffer.dirname(bufnr)
  local x

  if repl_type == 'repl' then
    x = dict.get(repls, { ft, wd })
  else
    x = dict.get(shells, { wd })
  end

  if x then
    if start then
      x:start()
    else
      return x
    end
  elseif start then
    ---@diagnostic disable-next-line
    x = repl(bufnr, { shell = repl_type == 'shell' })
    x:start()
  end

  return x
end

function utils.make_keymap_command(repl_type, name, start)
  return function()
    start = (name == 'start' and true) or start
    local x = utils.get(repl_type, buffer.current(), start)

    if not is.table(x) then
      return
    elseif name == 'start' then
      return x:start()
    elseif x:is_running() and x[name] then
      x[name](x)
    end

    return x
  end
end

local function repl_fn(name, start)
  return utils.make_keymap_command('repl', name, start)
end

local function shell_fn(name, start)
  return utils.make_keymap_command('shell', name, start)
end

keymap.define {
  shell_start = { 'n', '<space><enter><enter>', shell_fn('start'), { desc = 'Start REPL' } },
  shell_stop = { 'n', '<space><enter>q', shell_fn('stop'), { desc = 'Stop REPL' } },
  shell_hide = { 'n', '<space><enter>k', shell_fn('hide'), { desc = 'Hide REPL' } },
  shell_split_below = { 'n', '<space><enter>s', shell_fn('split'), { desc = 'Split below' } },
  shell_split_right = { 'n', '<space><enter>v', shell_fn('split_right'), { desc = 'Split on right' } },
  shell_send_buffer = { 'n', '<space><enter>b', shell_fn('send_buffer'), { desc = 'Send buffer' } },
  shell_send_line = { 'n', '<space><enter>e', shell_fn('send_current_line'), { desc = 'Send current line' } },
  shell_send_region = { 'v', '<space><enter>e', shell_fn('send_region'), { desc = 'Send region' } },
  shell_send_C_c = { 'n', '<space>rc', shell_fn('send_ctrl_c'), { desc = 'Send Ctrl-c' } },
  shell_send_C_d = { 'n', '<space>rd', shell_fn('send_ctrl_d'), { desc = 'Send Ctrl-d' } },

  repl_start = { 'n', '<space>rr', repl_fn('start'), { desc = 'Start' } },
  repl_stop = { 'n', '<space>rq', repl_fn('stop'), { desc = 'Stop' } },
  repl_split_below = { 'n', '<space>rs', repl_fn('split'), { desc = 'Split below' } },
  repl_split_right = { 'n', '<space>rv', repl_fn('split_right'), { desc = 'Split on right' } },
  repl_send_buffer = { 'n', '<space>rb', repl_fn('send_buffer'), { desc = 'Send buffer' } },
  repl_send_line = { 'n', '<space>re', repl_fn('send_current_line'), { desc = 'Send current line' } },
  repl_send_region = { 'v', '<space>re', repl_fn('send_region'), { desc = 'Send region' } },
  repl_send_C_c = { 'n', '<space>rc', repl_fn('send_ctrl_c'), { desc = 'Send Ctrl-c' } },
  repl_send_C_d = { 'n', '<space>rd', repl_fn('send_ctrl_d'), { desc = 'Send Ctrl-d' } },
  repl_hide = { 'n', '<space>rk', repl_fn('hide'), { desc = 'Hide REPL' } },
}
