local tabpage = {}
local list = require('lua-utils.list')

tabpage.get_number = vim.api.nvim_tabpage_get_number
tabpage.is_valid = vim.api.nvim_tabpage_is_valid
tabpage.del_var = vim.api.nvim_tabpage_del_var
tabpage.set_var = vim.api.nvim_tabpage_set_var
tabpage.get_win = vim.api.nvim_tabpage_get_win
tabpage.set_win = vim.api.nvim_tabpage_set_win
tabpage.get_window = vim.api.nvim_tabpage_get_win
tabpage.set_window = vim.api.nvim_tabpage_set_win
tabpage.is_valid = vim.api.nvim_tabpage_is_valid
tabpage.list_wins = vim.api.nvim_tabpage_list_wins
tabpage.list_bufs = vim.fn.tabpagebuflist
tabpage.list_windows = tabpage.list_wins
tabpage.list_buffers = tabpage.list_bufs
tabpage.winnr = vim.fn.tabpagewinnr

function tabpage.current()
  return tabpage.get_number(0)
end

function tabpage.buffer_picker(tabnr)
  tabnr = tabnr or tabpage.current()
  local picker = require('nvim-utils.picker')
  local p = picker('Tab buffers')
  local buffers = tabpage.list_buffers(tabnr)
  local choices = {}

  if #buffers == 0 then
    return false
  else
    for i=1, #buffers do
      choices[i] = {buffers[i], vim.api.nvim_buf_get_name(buffers[i])}
    end
  end

  local actions = p.actions

  local function default_action(entries)
    local entry = entries[1].value
    local winid = vim.fn.bufwinid(entry)
    tabpage.set_window(0, winid)
  end

  function actions.focus(pbufnr)
    default_action(p:entries(pbufnr))
  end

  function actions.wipeout(pbufnr)
    list.each(p:entries(pbufnr), function (entry)
      vim.api.nvim_buf_delete(entry.value, true)
    end)
  end
 
  function actions.delete(pbufnr)
    list.each(p:entries(pbufnr), function (entry)
      vim.api.nvim_buf_delete(entry.value, false)
    end)
  end

  return p:find(choices, default_action, {
    entry_maker =  function (entry)
      local bufnr, bufname = unpack(entry)
      return {
        display = bufname:gsub(os.getenv('HOME'), '~'),
        ordinal = bufname,
        value = bufnr
      }
    end,
    keymaps = {
      {'n', 'd', 'delete', 'Delete buffer'},
      {'n', 'x', 'wipeout', 'Wipeout buffer'},
      {'i', '<C-d>', 'delete', 'Delete buffer'},
      {'i', '<C-x>', 'wipeout', 'Wipeout buffer'},
    }
  })
end

return tabpage
