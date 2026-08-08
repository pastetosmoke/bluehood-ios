# Windows PowerShell
# GitHub Secretsへ登録するBase64値を作る補助スクリプト

param(
  [Parameter(Mandatory=$true)] [string]$P12,
  [Parameter(Mandatory=$true)] [string]$MobileProvision,
  [Parameter(Mandatory=$true)] [string]$ExportOptions
)

function To-Base64([string]$Path) {
  [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $Path)))
}

Write-Host "BUILD_CERTIFICATE_BASE64:"
Write-Host (To-Base64 $P12)
Write-Host "`nPROVISIONING_PROFILE_BASE64:"
Write-Host (To-Base64 $MobileProvision)
Write-Host "`nEXPORT_OPTIONS_PLIST_BASE64:"
Write-Host (To-Base64 $ExportOptions)
