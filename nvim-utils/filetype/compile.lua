require 'nvim-utils.filetype.filetype'
require 'nvim-utils.terminal'

function filetype:compile(bufnr, overrides)
  local ok, msg = buffer.id(bufnr)
  if not ok then
    error('bufnr: ' .. msg)
  end

  local config = self.run
  local name = sprintf('filetype.command.%s')
end
