return {
  highlight_on_yank = {
    "TextYankPost",
    {
      pattern = "*",
      callback = function()
        vim.highlight.on_yank { timeout = 200 }
      end,
    },
  },

  stop_jobs = {
    "ExitPre",
    {
      pattern = "*",
      callback = function()
        dict.each(user.jobs, function(_, job)
          job:close()
        end)

        dict.each(user.repls, function(_, job)
          job:stop()
        end)

        dict.each(user.terminals, function(_, job)
          job:stop()
        end)
      end,
    },
  },
}
