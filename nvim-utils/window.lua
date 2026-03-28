local win = {}
local function nr2id_wrap(fn)
  return function(winnr, ...)
    local winid = win.id(winnr)
    return fn(winid)
  end
end
local idwrap = nr2id_wrap

win.id = vim.fn.win_getid
win.id2nr = vim.fn.win_id2nr
win.move_separator = vim.fn.win_move_separator
win.screenpos = idwrap(vim.fn.win_screenpos)
win.nr2id = idwrap(vim.fn.win_getid)
win.bufnr = vim.fn.winbufnr
win.move_statusline = vim.fn.win_move_statusline
win.get_type = vim.fn.win_gettype
win.getnr = vim.api.win_get_number
win.gotoid = vim.fn.win_gotoid
win.call = vim.api.nvim_win_call
win.close = vim.api.nvim_win_close
win.hide = vim.api.nvim_win_hide
win.is_valid = vim.api.nvim_win_is_valid
win.set_buf = vim.api.nvim_win_set_buf
win.set_cursor = vim.api.nvim_win_set_cursor
win.get_config = vim.api.nvim_win_get_config
win.set_config = vim.api.nvim_win_set_config
win.del_var = vim.api.nvim_win_del_var
win.set_var = vim.api.nvim_win_set_var
win.get_var = vim.api.nvim_win_get_var
win.get_cursor = vim.api.nvim_win_get_cursor
win.get_height = vim.api.nvim_win_get_height
win.set_height = vim.api.nvim_win_set_height
win.set_width = vim.api.nvim_win_set_width
win.get_tabpage = vim.api.nvim_win_get_tabpage

--- Save and restore window view and cursor position
---@param winid number Window ID to save/restore
---@param fn function Function to execute with preserved state
---@return any
function win.save_excursion_and(winid, fn, ...)
  local args = { ... }
  return win.call(winid, function()
    local saved_view = vim.fn.winsaveview()
    local ok, result = pcall(fn, unpack(args))
    vim.fn.winrestview(saved_view)

    if not ok then
      error(result)
    end

    return result
  end)
end

--- Wrap a function while preserving the window view
--- @param fn function
--- @return (fun(winid: number, ...): any)
function win.save_excursion(fn)
  return function(winid, ...)
    return win.save_excursion_and(winid, fn, ...)
  end
end

return win
