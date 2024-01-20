require "logging.file"

local log_path = table.concat({ os.getenv "HOME", ".local", "share", "nvim", "messages" }, "/")

logger = logging.file {
  filename = log_path,
  datePattern = "%d-%m-%Y > ",
}

logger.log_path = log_path

vim.keymap.set("n", "<space>hL", function()
  vim.cmd(":vsplit | e " .. log_path)

  vim.bo.modifiable = false
  vim.bo.filetype = "nvimlog"

  vim.api.nvim_buf_set_keymap(vim.fn.bufnr(), "n", "q", ":hide<CR>", { desc = "hide buffer" })
end, { desc = "show logs" })

vim.keymap.set("n", "<space>hl", function()
  vim.cmd(":split | e " .. log_path)

  vim.bo.modifiable = false
  vim.bo.filetype = "nvimlog"

  vim.api.nvim_buf_set_keymap(vim.fn.bufnr(), "n", "q", ":hide<CR>", { desc = "hide buffer" })
end, { desc = "show logs" })

local function make_logger(name)
  _G[name:upper()] = function(...)
    return logger[name](logger, ...)
  end
end

make_logger "debug"
make_logger "info"
make_logger "warn"
make_logger "error"

local function make_pcall_wrapper(name)
  local function _pcall(f, ...)
    local ok, msg = pcall(f, ...)

    if not ok then
      msg = msg or "[WARN]"
      msg = sprintf("-- START --\nArguments: %s\n%s\n-- END --", dump { ... }, msg)
      logger[name](logger, msg)
      return nil, msg
    end

    return msg
  end

  _G["pcall_" .. name] = _pcall
end

make_pcall_wrapper "debug"
make_pcall_wrapper "info"
make_pcall_wrapper "warn"
make_pcall_wrapper "error"
