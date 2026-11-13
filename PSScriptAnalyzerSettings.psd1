# PSScriptAnalyzer settings, shared by local runs and CI (.github/workflows/powershell.yml)
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
# Excluded rules (whole rule):
#   PSAvoidUsingWriteHost        - interactive scripts; colored output is intended (pwsh 5+ sends it to the information stream)
#   PSUseShouldProcessForStateChangingFunctions
#                                - Update-ShellCache only rebuilds a cache; New-TweakOp only builds an object;
#                                  tweaks have their own -DryRun
#   PSUseBOMForUnicodeEncodedFile - non-ASCII scripts are pwsh 7 only (UTF-8 without BOM is fine);
#                                  CI checks this separately (non-ASCII => #Requires -Version 7 or listed as dot-source only)
#   PSAvoidUsingPositionalParameters
#                                - the tweak table (Svc / Reg / Win32 ...) reads better positionally
# PSAvoidUsingInvokeExpression is NOT excluded: each use is allowed one by one with SuppressMessageAttribute.
@{
  ExcludeRules = @(
    'PSAvoidUsingWriteHost'
    'PSUseShouldProcessForStateChangingFunctions'
    'PSUseBOMForUnicodeEncodedFile'
    'PSAvoidUsingPositionalParameters'
  )
}
