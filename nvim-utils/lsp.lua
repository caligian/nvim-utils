local lsp = ns()

lsp.diagnostic = {
  virtual_text = false,
  underline = false,
  update_in_insert = false,
}

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
  border = "single",
  title = "hover",
})

vim.diagnostic.config(lsp.diagnostic)

---@diagnostic disable-next-line: inject-field
function lsp.fix_omnisharp(client, _)
  client.server_capabilities.semanticTokensProvider = {
    full = vim.empty_dict(),
    legend = {
      tokenModifiers = { "static_symbol" },
      tokenTypes = {
        "comment",
        "excluded_code",
        "identifier",
        "keyword",
        "keyword_control",
        "number",
        "operator",
        "operator_overloaded",
        "preprocessor_keyword",
        "string",
        "whitespace",
        "text",
        "static_symbol",
        "preprocessor_text",
        "punctuation",
        "string_verbatim",
        "string_escape_character",
        "class_name",
        "delegate_name",
        "enum_name",
        "interface_name",
        "module_name",
        "struct_name",
        "type_parameter_name",
        "field_name",
        "enum_member_name",
        "constant_name",
        "local_name",
        "parameter_name",
        "method_name",
        "extension_method_name",
        "property_name",
        "event_name",
        "ns_name",
        "label_name",
        "xml_doc_comment_attribute_name",
        "xml_doc_comment_attribute_quotes",
        "xml_doc_comment_attribute_value",
        "xml_doc_comment_cdata_section",
        "xml_doc_comment_comment",
        "xml_doc_comment_delimiter",
        "xml_doc_comment_entity_reference",
        "xml_doc_comment_name",
        "xml_doc_comment_processing_instruction",
        "xml_doc_comment_text",
        "xml_literal_attribute_name",
        "xml_literal_attribute_quotes",
        "xml_literal_attribute_value",
        "xml_literal_cdata_section",
        "xml_literal_comment",
        "xml_literal_delimiter",
        "xml_literal_embedded_expression",
        "xml_literal_entity_reference",
        "xml_literal_name",
        "xml_literal_processing_instruction",
        "xml_literal_text",
        "regex_comment",
        "regex_character_class",
        "regex_anchor",
        "regex_quantifier",
        "regex_grouping",
        "regex_alternation",
        "regex_text",
        "regex_self_escaped_character",
        "regex_other_escape",
      },
    },
    range = true,
  }
end

function lsp.attach_formatter(client)
  require("lsp-format").on_attach(client)
end

function lsp.on_attach(client, bufnr)
  if client.name == "omnisharp" then
    lsp.fix_omnisharp(client)
  else
    Buffer.set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
  end

  local ft = vim.bo.filetype
  local has_formatter = Filetype(ft):loadfile()

  if has_formatter and not has_formatter.formatter then
    lsp.attach_formatter(client)
  end

  local mappings = {
    float_diagnostic = {
      "n",
      "<leader>li",
      partial(vim.diagnostic.open_float, { scope = "l", focus = false }),
      {
        desc = "LSP diagnostic float",
        noremap = true,
      },
    },
    set_loclist = {
      "n",
      "lq",
      vim.diagnostic.setloclist,
      {
        desc = "LSP set loclist",
        noremap = true,
        leader = true,
      },
    },
    buffer_declarations = {
      "n",
      "gD",
      vim.lsp.buf.declaration,
      {
        desc = "Buffer declarations",
        silent = true,
        noremap = true,
      },
    },
    buffer_definitions = {
      "n",
      "gd",
      vim.lsp.buf.definition,
      {
        desc = "Buffer definitions",
        silent = true,
        noremap = true,
      },
    },
    float_documentation = {
      "n",
      "K",
      vim.lsp.buf.hover,
      {
        desc = "Show float UI",
        silent = true,
        noremap = true,
      },
    },
    implementations = {
      "n",
      "gi",
      vim.lsp.buf.implementation,
      {
        desc = "Show implementations",
        silent = true,
        noremap = true,
      },
    },
    signatures = {
      "n",
      "<C-k>",
      vim.lsp.buf.signature_help,
      {
        desc = "Signatures",
        silent = true,
        noremap = true,
      },
    },
    add_workspace_folder = {
      "n",
      "<leader>lwa",
      vim.lsp.buf.add_workspace_folder,
      {
        desc = "Add workspace folder",
        silent = true,
        noremap = true,
      },
    },
    remove_workspace_folder = {
      "n",
      "<leader>lwx",
      vim.lsp.buf.remove_workspace_folder,
      {
        desc = "Remove workspace folder",
        silent = true,
        noremap = true,
      },
    },
    list_workspace_folders = {
      "n",
      "<leader>lwl",
      function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
      end,
      {
        desc = "List workspace folders",
        silent = true,
        noremap = true,
      },
    },
    type_definition = {
      "n",
      "<leader>lD",
      vim.lsp.buf.type_definition,
      {
        desc = "Show type definitions",
        silent = true,
        noremap = true,
      },
    },
    buffer_rename = {
      "n",
      "<leader>lR",
      vim.lsp.buf.rename,
      {
        desc = "Rename buffer",
        silent = true,
        noremap = true,
      },
    },
    code_action = {
      "n",
      "<leader>la",
      vim.lsp.buf.code_action,
      {
        desc = "Show code actions",
        silent = true,
        noremap = true,
      },
    },
    buffer_references = {
      "n",
      "gr",
      vim.lsp.buf.references,
      {
        desc = "Show buffer references",
        silent = true,
        noremap = true,
      },
    },
  }

  for name, value in pairs(mappings) do
    value[4] = value[4] or {}
    value[4].buffer = bufnr
    value[4].name = "lsp." .. name
  end

  Kbd.from_dict(mappings)
end

function lsp.setup_server(server, opts)
  opts = opts or {}
  local capabilities = opts.capabilities or require("cmp_nvim_lsp").default_capabilities()
  local on_attach = opts.on_attach or lsp.on_attach
  local flags = opts.flags
  local default_conf = {
    capabilities = capabilities,
    on_attach = on_attach,
    flags = flags,
  }

  default_conf = dict.merge(default_conf, opts)

  if default_conf.cmd then
    default_conf.cmd = totable(default_conf.cmd)
  end

  require("lspconfig")[server].setup(default_conf)
end

return lsp
