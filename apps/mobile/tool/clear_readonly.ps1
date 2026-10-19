# Clears the ReadOnly attribute on every directory of the Flutter project.
#
# On some Windows setups (observed under %USERPROFILE%\Downloads) directories
# created by the Flutter/Gradle toolchain come back with the ReadOnly attribute.
# Dart then reports "doesn't allow reading and writing" for gen-l10n and
# Gradle's clean tasks fail to delete build outputs. Run this before a build:
#
#   powershell -NoProfile -File tool/clear_readonly.ps1
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ro = [IO.FileAttributes]::ReadOnly
$cleared = 0
# -ErrorAction SilentlyContinue: Gradle's .transforms caches exceed MAX_PATH and are irrelevant here.
foreach ($dir in @(Get-Item -LiteralPath $Root) + (Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dir.Attributes -band $ro) {
        $dir.Attributes = $dir.Attributes -band (-bnot $ro)
        $cleared++
    }
}
Write-Output "cleared ReadOnly on $cleared directories under $Root"
