local win = {}

win.id = vim.fn.win_getid
win.nr2id = vim.fn.win_getid
win.id2nr = vim.fn.win_id2nr
win.move_separator = vim.fn.win_move_separator
win.screenpos = vim.fn.win_screenpos
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

return win
