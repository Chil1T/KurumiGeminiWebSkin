Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $repoRoot 'build-release.ps1'

Assert-True (Test-Path $buildScript) "Expected build script at '$buildScript'."

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kurumi-build-test-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $inputCss = Join-Path $tempRoot 'KurumiskinforAI.css'
    $base64File = Join-Path $tempRoot 'background.base64.txt'
    $outputCss = Join-Path $tempRoot 'dist\Kurumiskin.user.css'
    $officialCss = Join-Path $tempRoot 'Kurumiskin.user.css'

    @'
body {
    background-image:
        url(占位符);
}

.card {
    color: #fff;
}
'@ | Set-Content -Path $inputCss -Encoding UTF8

    'QUJDRA==' | Set-Content -Path $base64File -Encoding UTF8

    Push-Location $tempRoot
    try {
        & $buildScript -InputCss $inputCss -Base64File $base64File
    }
    finally {
        Pop-Location
    }

    Assert-True (Test-Path $outputCss) 'Expected output CSS to be created.'
    Assert-True (-not (Test-Path $officialCss)) 'Expected official CSS to remain untouched by default.'

    $output = Get-Content -Path $outputCss -Raw
    Assert-True ($output.Contains('url("data:image/png;base64,QUJDRA==");')) 'Expected placeholder to be replaced with a data URL.'
    Assert-True ($output.Contains('.card')) 'Expected non-background CSS to be preserved.'
    Assert-True (-not $output.Contains('占位符')) 'Expected placeholder to be removed from output.'

    Push-Location $tempRoot
    try {
        & $buildScript -InputCss $inputCss -Base64File $base64File -PublishOfficial
    }
    finally {
        Pop-Location
    }

    Assert-True (Test-Path $officialCss) 'Expected official CSS to be written when -PublishOfficial is used.'
    $official = Get-Content -Path $officialCss -Raw
    Assert-True ($official -eq $output) 'Expected published official CSS to match the generated dist artifact.'

    $normalizedOutputCss = Join-Path $tempRoot 'dist\Kurumiskin-normalized.user.css'
    'data:image/png;base64,QUJDRA==' | Set-Content -Path $base64File -Encoding UTF8

    & $buildScript -InputCss $inputCss -Base64File $base64File -OutputCss $normalizedOutputCss

    $normalizedOutput = Get-Content -Path $normalizedOutputCss -Raw
    Assert-True ($normalizedOutput.Contains('url("data:image/png;base64,QUJDRA==");')) 'Expected full data URL input to be normalized into a single data URL.'
    Assert-True (-not $normalizedOutput.Contains('data:image/png;base64,data:image/png;base64,')) 'Expected duplicate data URL prefixes to be removed.'
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}

Write-Host 'build-release test passed'
