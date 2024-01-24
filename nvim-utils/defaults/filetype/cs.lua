local cs = {}

cs.repl = "csharp"

cs.compile = function(bufname)
  local exe = name:gsub("cs$", "exe")
  return template "csc {path}  && [[ -f %s ]] && mono {path}" {
    path = bufname,
  }
end

cs.build = "csc %%"

cs.server = {
  "omnisharp",
  config = {
    cmd = {
      Path.join(os.getenv "HOME", "Downloads", "omnisharp", "run"),
    },
    settings = {
      FormattingOptions = {
        EnableEditorConfigSupport = true,
        OrganizeImports = true,
        NewLine = "\n",
        UseTabs = false,
        TabSize = 2,
        IndentationSize = 2,
        SpacingAfterMethodDeclarationName = false,
        SpaceWithinMethodDeclarationParenthesis = false,
        SpaceBetweenEmptyMethodDeclarationParentheses = false,
        SpaceAfterMethodCallName = false,
        SpaceWithinMethodCallParentheses = false,
        SpaceBetweenEmptyMethodCallParentheses = false,
        SpaceAfterControlFlowStatementKeyword = true,
        SpaceWithinExpressionParentheses = false,
        SpaceWithinCastParentheses = false,
        SpaceWithinOtherParentheses = false,
        SpaceAfterCast = false,
        SpacesIgnoreAroundVariableDeclaration = false,
        SpaceBeforeOpenSquareBracket = false,
        SpaceBetweenEmptySquareBrackets = false,
        SpaceWithinSquareBrackets = false,
        SpaceAfterColonInBaseTypeDeclaration = true,
        SpaceAfterComma = true,
        SpaceAfterDot = false,
        SpaceAfterSemicolonsInForStatement = true,
        SpaceBeforeColonInBaseTypeDeclaration = true,
        SpaceBeforeComma = false,
        SpaceBeforeDot = false,
        SpaceBeforeSemicolonsInForStatement = false,
        SpacingAroundBinaryOperator = "single",
        IndentBraces = false,
        IndentBlock = true,
        IndentSwitchSection = true,
        IndentSwitchCaseSection = true,
        IndentSwitchCaseSectionWhenBlock = true,
        LabelPositioning = "oneLess",
        WrappingPreserveSingleLine = true,
        WrappingKeepStatementsOnSingleLine = true,
        NewLinesForBracesInTypes = true,
        NewLinesForBracesInMethods = true,
        NewLinesForBracesInProperties = true,
        NewLinesForBracesInAccessors = true,
        NewLinesForBracesInAnonymousMethods = true,
        NewLinesForBracesInControlBlocks = true,
        NewLinesForBracesInAnonymousTypes = true,
        NewLinesForBracesInObjectCollectionArrayInitializers = true,
        NewLinesForBracesInLambdaExpressionBody = true,
        NewLineForElse = false,
        NewLineForCatch = true,
        NewLineForFinally = true,
        NewLineForMembersInObjectInit = true,
        NewLineForMembersInAnonymousTypes = true,
        NewLineForClausesInQuery = true,
      },
    },
  },
}

return cs
