require "lua-utils"

return function(opts)
  require "nvim-utils.state"

  local bootstrapper = require "nvim-utils.bootstrap"
  bootstrapper:setup(opts)

  require "nvim-utils.Path"
  require "nvim-utils.logger"
  require "nvim-utils.color"
  require "nvim-utils.Autocmd"
  require "nvim-utils.Kbd"
  require "nvim-utils.Buffer.Buffer"
  require "nvim-utils.Win"
  require "nvim-utils.Plugin"
  require "nvim-utils.Async"
  require "nvim-utils.Filetype"
  require "nvim-utils.BufferGroup"
  require "nvim-utils.Bookmark"
  require "nvim-utils.Terminal"
  require "nvim-utils.REPL"
  require "nvim-utils.telescope_utils"

  nvim.create.autocmd({ "BufDelete" }, {
    pattern = "*",
    callback = function(opts)
      if user.buffers[opts.buf] then
        user.buffers[opts.buf] = nil
      end
    end,
  })
end
