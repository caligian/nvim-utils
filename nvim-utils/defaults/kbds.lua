-- Only works for toggleable options
local function _toggle_option(option)
  local bufnr = vim.fn.bufnr()
  local winid = vim.fn.bufwinid(bufnr)
  local ok, out = pcall(vim.api.nvim_buf_get_option, bufnr, option)

  if ok then
    vim.api.nvim_buf_set_option(bufnr, option, not out)
  end

  if not ok then
    ok, out = pcall(vim.api.nvim_win_get_option, winid, option)
    if ok then
      vim.api.nvim_win_set_option(winid, option, not out)
    end
  end
end

local function close_other_windows()
  local current_winid = Win.current_id()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(current_tab)

  list.each(wins, function(winid)
    if winid == current_winid then
      return
    else
      Win.call(Winid.id2nr(winid), function()
        vim.cmd ":hide"
      end)
    end
  end)
end

local opts = { noremap = true, leader = true }

local withopts = function(overrides)
  overrides = is_string(overrides) and { desc = overrides } or overrides
  return dict.lmerge(overrides, opts)
end

local function unwrap(f)
  return function()
    local ft = Filetype(Buffer.current())
    if ft then
      return f(ft)
    end
  end
end

local function format(cmd_for)
  return unwrap(function(ft)
    return ft:format_buffer(Buffer.current(), cmd_for)
  end)
end

local function _compile(action, cmd_for)
  return unwrap(function(ft)
    return ft:compile_buffer(Buffer.current(), action, cmd_for)
  end)
end

local function compile(cmd_for)
  return _compile("compile", cmd_for)
end

local function test(cmd_for)
  return _compile("test", cmd_for)
end

local function build(cmd_for)
  return _compile("build", cmd_for)
end

return {
  workspace_test = {
    "n",
    "<leader>mt",
    test "workspace",
    {},
  },
  dir_test = {
    "n",
    "<leader>ct",
    test "dir",
    {},
  },
  buffer_test = {
    "n",
    "<localleader>ct",
    test "buffer",
    {},
  },
  workspace_build = {
    "n",
    "<leader>mb",
    build "workspace",
    {},
  },
  dir_build = {
    "n",
    "<leader>cb",
    build "dir",
    {},
  },
  buffer_build = {
    "n",
    "<localleader>cb",
    build "buffer",
    {},
  },
  workspace_compile = {
    "n",
    "<leader>mc",
    compile "workspace",
    {},
  },
  dir_compile = {
    "n",
    "<leader>cc",
    compile "dir",
    {},
  },
  buffer_compile = {
    "n",
    "<localleader>cc",
    compile "buffer",
    {},
  },
  workspace_format = {
    "n",
    "<leader>mf",
    format "workspace",
    {},
  },
  dir_format = {
    "n",
    "<leader>bF",
    format "dir",
    {},
  },
  buffer_format = {
    "n",
    "<localleader>bf",
    format "buffer",
    {},
  },

  paste_above_cursor = {
    "n",
    "gp",
    ":put<CR>",
    { desc = "paste above cursor" },
  },

  paste_below_cursor = {
    "n",
    "gP",
    ":put!<CR>",
    { desc = "paste below cursor" },
  },

  netrw = {
    "n",
    "|",
    ":Lexplore <bar> vert resize 40<CR>",
    withopts "Open netrw",
  },

  netrw_quickmap1 = {
    "n",
    "g?",
    ":h netrw-quickmap<CR>",
    {
      event = "FileType",
      pattern = "netrw",
      desc = "Help",
    },
  },

  noh = {
    "n",
    "\\\\",
    ":noh<CR>",
    { desc = "No highlight", noremap = true },
  },

  term_normal_mode = {
    "t",
    "<esc>",
    "<C-\\><C-n>",
    { desc = "Terminal to normal mode" },
  },

  zenmode = {
    "n",
    "oz",
    ":ToggleZenMode<CR>",
    withopts "Toggle Zen mode",
  },

  open_config = {
    "n",
    "fp",
    ":chdir ~/.config/nvim <bar> e .<CR>",
    withopts { desc = "Open framework config" },
  },

  reload_buffer = {
    "n",
    "be",
    ":e!<CR>",
    withopts { desc = "Reload buffer" },
  },

  save_buffer = {
    "n",
    "fs",
    ":w! %<CR>",
    withopts { desc = "Save buffer" },
  },

  hide_buffer = {
    "n",
    "bk",
    ":hide<CR>",
    { desc = "Hide buffer" },
  },

  wipeout_buffer = {
    "n",
    "bq",
    ":bwipeout! %<CR>",
    { desc = "Wipeout buffer" },
  },

  save_and_hide = {
    "n",
    "bK",
    ":w! <bar> hide<CR>",
    { desc = "Save and hide buffer" },
  },

  previous_buffer = {
    "n",
    "bp",
    ":bprev<CR>",
    { desc = "Previous buffer" },
  },

  next_buffer = {
    "n",
    "bn",
    ":bnext<CR>",
    { desc = "Next buffer" },
  },

  first = {
    "n",
    "b0",
    ":bfirst<CR>",
    { desc = "First buffer" },
  },

  last = {
    "n",
    "b$",
    ":blast<CR>",
    { desc = "Last buffer" },
  },

  source = {
    "n",
    "<leader>fv",
    ":w! % <bar> :source %<CR>",
    {
      event = "BufEnter",
      pattern = { "*.vim", "*.lua" },
      desc = "Source vim or lua buffer",
    },
  },

  eval_line = {
    "n",
    "ee",
    "<cmd>NvimEvalLine<CR>",
    withopts { desc = "Lua source line" },
  },

  eval_buffer = {
    "n",
    "eb",
    "<cmd>NvimEvalBuffer<CR>",
    withopts { desc = "Lua source buffer" },
  },

  eval_till_cursor = {
    "n",
    "e.",
    "<cmd>NvimEvalTillCursor<CR>",
    withopts { desc = "Lua source till point" },
  },

  eval_region = {
    "v",
    "ee",
    "<esc>:NvimEvalRegion<CR>",
    withopts { desc = "Lua source range" },
  },

  scratch_split = {
    "n",
    ",",
    ":OpenScratch<CR>",
    withopts "split scratch",
  },

  scratch_float = {
    "n",
    "F",
    ":OpenScratchFloat<CR>",
    withopts "float scratch",
  },

  scratch_vsplit = {
    "n",
    ";",
    ":OpenScratchVertically<CR>",
    withopts "vsplit scratch",
  },

  tab_new = {
    "n",
    "tt",
    ":tabnew<CR>",
    withopts { desc = "New tab" },
  },

  tab_hide = {
    "n",
    "tk",
    ":tabclose<CR>",
    withopts { desc = "Close tab" },
  },

  tab_next = {
    "n",
    "tn",
    ":tabnext<CR>",
    withopts { desc = "Next tab" },
  },

  tab_previous = {
    "n",
    "tp",
    ":tabprev<CR>",
    withopts { desc = "Previous tab" },
  },

  quit = {
    "n",
    "qa",
    ":qa<CR>",
    withopts "quit",
  },

  force_quit = {
    "n",
    "qq",
    ":qa!<CR>",
    withopts "force quit",
  },

  save_and_quit = {
    "n",
    "qx",
    ":xa<CR>",
    withopts "save and quit",
  },

  wrap = {
    "n",
    "ot",
    partial(_toggle_option, "textwrap"),
    withopts "Toggle wrapping",
  },

  readonly = {
    "n",
    "or",
    partial(_toggle_option, "readonly"),
    withopts "Toggle readonly",
  },

  cursorline = {
    "n",
    "oc",
    partial(_toggle_option, "cursorline"),
    withopts "Toggle cursorline",
  },

  buflisted = {
    "n",
    "ol",
    partial(_toggle_option, "buflisted"),
    withopts "Toggle buflisted",
  },

  backup = {
    "n",
    "ob",
    partial(_toggle_option, "backup"),
    withopts "Toggle backup",
  },

  expandtab = {
    "n",
    "oe",
    partial(_toggle_option, "expandtab"),
    withopts "Toggle expandtab",
  },

  smartindent = {
    "n",
    "os",
    partial(_toggle_option, "smartindent"),
    withopts "Toggle smartindent",
  },

  modified = {
    "n",
    "o!",
    partial(_toggle_option, "modified"),
    withopts "Toggle modified status",
  },

  ruler = {
    "n",
    "ou",
    partial(_toggle_option, "ruler"),
    withopts "Toggle ruler",
  },

  modifiable = {
    "n",
    "om",
    partial(_toggle_option, "modifiable"),
    withopts "Toggle modifiable",
  },

  left = {
    "n",
    "wh",
    "<C-w>h",
    withopts "Left win",
  },

  hide_others = {
    "n",
    "wo",
    close_other_windows,
    withopts "Hide other wins",
  },

  max_height = {
    "n",
    "w_",
    "<C-w>_",
    withopts "Max out height",
  },

  max_width = {
    "n",
    "w|",
    "<C-w>|",
    withopts "Max out width",
  },

  down = {
    "n",
    "wj",
    "<C-w>j",
    withopts "Down win",
  },

  up = {
    "n",
    "wk",
    "<C-w>k",
    withopts "Up win",
  },

  right = {
    "n",
    "wl",
    "<C-w>l",
    withopts "Right win",
  },

  inc_height = {
    "n",
    "w+",
    "<C-w>+",
    withopts "Increase height",
  },

  dec_height = {
    "n",
    "w-",
    "<C-w>-",
    withopts "Decrease height",
  },

  equalize = {
    "n",
    "w=",
    "<C-w>=",
    withopts "Equalize height and width",
  },

  inc_width = {
    "n",
    "w>",
    "<C-w>>",
    withopts "Increase width",
  },

  dec_width = {
    "n",
    "w<",
    "<C-w><",
    withopts "Decrease width",
  },

  split = {
    "n",
    "ws",
    "<C-w>s",
    withopts "Split win",
  },

  vspilt = {
    "n",
    "wv",
    "<C-w>v",
    withopts "Vsplit win",
  },

  tabnew = {
    "n",
    "wt",
    "<C-w>T",
    withopts "Tabnew win",
  },

  other = {
    "n",
    "ww",
    "<C-w>w",
    withopts "Other win",
  },

  swap = {
    "n",
    "wx",
    "<C-w>x",
    withopts "Swap win",
  },

  insert_separator = {
    "n",
    "#",
    function()
      local tw = vim.bo.textwidth
      local comment = strsplit(vim.bo.commentstring or "#", " ")[1]
      if not comment then
        return
      end

      local l = #comment
      tw = tw == 0 and 50 or tw

      if l > 1 then
        comment = string.rep(comment, math.floor(tw / l))
      else
        comment = string.rep(comment, tw)
      end

      vim.api.nvim_put({ comment }, "l", true, true)
    end,
    withopts "Add separator line",
  },

  open_qflist = {
    "n",
    "cq",
    ":botright copen<CR>",
    withopts "open qflist",
  },

  close_qflist = {
    "n",
    "ck",
    ":cclose<CR>",
    withopts "close qflist",
  },

  lsp_info = {
    "n",
    "li",
    ":LspInfo<CR>",
    withopts "lsp info",
  },
  stop_lsp = {
    "n",
    "lL",
    ":LspStop<CR>",
    withopts "stop lsp",
  },
  restart_lsp = {
    "n",
    "l!",
    ":LspRestart<CR>",
    withopts "restart lsp",
  },
  start_lsp = {
    "n",
    "ll",
    ":LspStart<CR>",
    withopts "start lsp",
  },
}
