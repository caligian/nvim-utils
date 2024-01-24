local netrw = {}

netrw.autocmds = {
  temp_buffer = function(au)
    buffer.map(au.buf, "ni", "q", ":hide<CR>")
  end,
}

return netrw
