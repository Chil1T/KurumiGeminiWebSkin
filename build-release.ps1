param(
    [string]$InputCss = (Join-Path $PSScriptRoot 'KurumiskinforAI.css'),
    [string]$Base64File = (Join-Path $PSScriptRoot 'background.base64.txt'),
    [string]$OutputCss = '',
    [string]$OfficialCss = '',
    [string]$MimeType = 'image/png',
    [switch]$PublishOfficial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$placeholderUrl = 'url(占位符);'
$base64Sentinel = 'PASTE_BASE64_HERE'

if (-not (Test-Path $InputCss)) {
    throw "Input CSS not found: $InputCss"
}

if (-not (Test-Path $Base64File)) {
    throw "Base64 file not found: $Base64File"
}

$inputDir = Split-Path -Parent $InputCss
if ([string]::IsNullOrWhiteSpace($OutputCss)) {
    $OutputCss = Join-Path $inputDir 'dist\Kurumiskin.user.css'
}

if ([string]::IsNullOrWhiteSpace($OfficialCss)) {
    $OfficialCss = Join-Path $inputDir 'Kurumiskin.user.css'
}

$base64 = (Get-Content -Path $Base64File -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($base64) -or $base64 -eq $base64Sentinel) {
    throw "Base64 file '$Base64File' is empty. Paste the background base64 into it before building."
}

$resolvedMimeType = $MimeType
$base64 = $base64 -replace '^\s*url\(\s*', ''
$base64 = $base64 -replace '\s*\)\s*;?\s*$', ''
$base64 = $base64 -replace '^[\s''"]+', ''
$base64 = $base64 -replace '[\s''"]+$', ''

if ($base64 -match '^data:(?<mime>[^;]+);base64,(?<payload>.+)$') {
    $resolvedMimeType = $Matches.mime
    $base64 = $Matches.payload.Trim()
}

if ([string]::IsNullOrWhiteSpace($base64)) {
    throw "Base64 payload could not be resolved from '$Base64File'."
}

$input = Get-Content -Path $InputCss -Raw
if (-not $input.Contains($placeholderUrl)) {
    throw "Placeholder '$placeholderUrl' was not found in '$InputCss'."
}

$dataUrl = 'url("data:{0};base64,{1}");' -f $resolvedMimeType, $base64
$output = $input.Replace($placeholderUrl, $dataUrl)

$outputDir = Split-Path -Parent $OutputCss
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path $OutputCss -Value $output -Encoding UTF8

Write-Host "Release CSS written to $OutputCss"

if ($PublishOfficial) {
    $officialDir = Split-Path -Parent $OfficialCss
    if ($officialDir -and -not (Test-Path $officialDir)) {
        New-Item -ItemType Directory -Path $officialDir -Force | Out-Null
    }

    if (([System.IO.Path]::GetFullPath($OfficialCss)) -ne ([System.IO.Path]::GetFullPath($OutputCss))) {
        Set-Content -Path $OfficialCss -Value $output -Encoding UTF8
    }

    Write-Host "Official CSS written to $OfficialCss"
}
