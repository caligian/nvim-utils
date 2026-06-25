require 'nvim-utils.repl.repl'
require 'nvim-utils.repl.utils'
require 'nvim-utils.keymap'

local dict = require 'lua-utils.dict'

local function make_sh()
  return terminal('', os.getenv("HOME"))
end

user_config.repl.sh = user_config.repl.sh or make_sh()
local sh = user_config.repl.sh

local function get_sh()
  if sh and sh:is_running() then
    return sh
  else
    user_config.repl.sh = make_sh()
    sh = user_config.repl.sh
  end

  return sh
end

local function sh_fn(name)
  return function()
    local x = get_sh()
    if x:is_running() then
      if name == 'stop' then
        x:stop()
      elseif x[name] then
        x[name](x)
      end
    elseif name == 'start' then
      x:start()
    end
  end
end

dict.merge(repl.default_mappings, {
  sh_start = { 'n', '<leader>xx', sh_fn('start'), { desc = 'Start' } },
  sh_hide = { 'n', '<leader>xk', sh_fn('hide'), { desc = 'Hide window' } },
  sh_split_below = { 'n', '<leader>xs', sh_fn('split_below'), { desc = 'Split below' } },
  sh_split_right = { 'n', '<leader>xv', sh_fn('split_right'), { desc = 'Split right' } },
  sh_stop = { 'n', '<leader>xq', sh_fn('stop'), { desc = 'Kill' } },
  sh_cd_cwd = { 'n', '<leader>x.', function()
    local term = get_sh()
    term:send("pushd .")
    term:send("cd " .. vim.fn.getcwd())
  end, { desc = 'chdir into buffer directory' } },
  sh_popd = { 'n', '<leader>x<', function() get_sh():send("popd -1") end, { desc = 'popd -1' } },
  sh_pushd = { 'n', '<leader>x>', function() get_sh():send("pushd .") end, { desc = 'pushd .' } },
})

if repl.default_mappings then
  keymap.define(repl.default_mappings)
end

if not sh:is_running() then
  vim.defer_fn(function() user_config.repl.sh:start() end, 1000)
end
