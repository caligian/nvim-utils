local command = vim.api.nvim_create_user_command

local function compile_and_run(lines)
  if is_a(lines, "table") then
    lines = table.concat(lines, "\n")
  end

  local compiled, err = loadstring(lines)
  if err then
    err_writeln(err)
  elseif compiled then
    compiled()
  end
end

return {
  OpenScratch = {
    function()
      Buffer.split(Buffer.scratch "scratch", "s")
    end,
    {},
  },

  OpenScratchVertically = {
    function()
      Buffer.split(Buffer.scratch "scratch", "v")
    end,
    {},
  },

  -- Setup commands
  NvimEvalRegion = {
    function(opts)
      local lines = Buffer.range_text(Buffer.current())
      compile_and_run(lines)
    end,
    {},
  },

  NvimEvalBuffer = {
    function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      compile_and_run(lines)
    end,
    {},
  },

  NvimEvalTillCursor = {
    function()
      local line = vim.fn.line "."
      local lines = vim.api.nvim_buf_get_lines(0, 0, line - 1, false)
      compile_and_run(lines)
    end,
    {},
  },

  NvimEvalLine = {
    function()
      local line = vim.fn.getline "."
      compile_and_run(line)
    end,
    {},
  },

  TrimWhiteSpace = {
    function()
      local layout = vim.fn.winsaveview()
      vim.cmd "keeppatterns %s/\\s\\+$//e"
      vim.fn.winrestview(layout)
    end,
    {},
  },

  ToggleZenMode = {
    function()
      if vim.o.laststatus ~= 0 then
        vim.o.laststatus = 0
      else
        vim.o.laststatus = 3
      end
    end,
    {},
  },
}
