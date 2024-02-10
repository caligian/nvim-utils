return {
  add_dir_bookmark = {
    "n",
    "<leader>bM",
    function()
      Bookmark.add_and_save(Path.dirname(Buffer.get_name(Buffer.bufnr())))
    end,
    {
      desc = "add dir bookmark",
    },
  },
  add_bookmark = {
    "n",
    "<leader>bm",
    function()
      Bookmark.add_and_save(Buffer.get_name(Buffer.bufnr()), Win.pos(Buffer.winnr(Buffer.current())).row)
    end,
    {
      desc = "add bookmark",
    },
  },

  bookmark_line_picker = {
    "n",
    "g.",
    function()
      Bookmark.run_line_picker(Buffer.current())
    end,
    {
      desc = "buffer bookmarks ",
    },
  },

  bookmark_picker = {
    "n",
    "g<space>",
    function()
      Bookmark.run_dwim_picker()
    end,
    {
      desc = "all bookmarks",
    },
  },
}
