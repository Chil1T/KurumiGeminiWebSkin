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

function Find-SelectorResult {
    param(
        [object[]]$Selectors,
        [string]$Selector
    )

    return $Selectors | Where-Object { $_.selector -eq $Selector } | Select-Object -First 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$auditScript = Join-Path $repoRoot 'audit-css.ps1'

Assert-True (Test-Path $auditScript) "Expected audit script at '$auditScript'."

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kurumi-audit-test-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $cssPath = Join-Path $tempRoot 'sample.css'
    $snapDir = Join-Path $tempRoot 'snaps'
    $reportPath = Join-Path $tempRoot 'report.json'
    New-Item -ItemType Directory -Path $snapDir | Out-Null

    @'
.card {
    color: #fff;
}

.card .title {
    color: #eee;
}

button.primary {
    transition: all 0.3s ease;
}

.missing-selector {
    display: none;
}

.glass {
    backdrop-filter: blur(10px);
}

body {
    background-attachment: fixed;
}
'@ | Set-Content -Path $cssPath -Encoding UTF8

    @'
<html>
  <body>
    <div class="card">
      <span class="title">Hello</span>
    </div>
    <button class="primary">Run</button>
    <div class="glass">Pane</div>
  </body>
</html>
'@ | Set-Content -Path (Join-Path $snapDir 'page.html') -Encoding UTF8

    & $auditScript -InputCss $cssPath -HtmlDir $snapDir -OutputJson $reportPath | Out-Null

    Assert-True (Test-Path $reportPath) 'Expected audit report JSON to be created.'

    $report = Get-Content -Path $reportPath -Raw | ConvertFrom-Json

    Assert-True ($report.snapshotCount -eq 1) 'Expected one HTML snapshot to be analyzed.'
    Assert-True ($report.selectorCount -ge 6) 'Expected selector count to include all sample selectors.'

    $missing = Find-SelectorResult -Selectors $report.selectors -Selector '.missing-selector'
    Assert-True ($null -ne $missing) 'Expected missing selector result.'
    Assert-True ($missing.totalEstimatedMatches -eq 0) 'Expected missing selector to have zero estimated matches.'

    $cardTitle = Find-SelectorResult -Selectors $report.selectors -Selector '.card .title'
    Assert-True ($null -ne $cardTitle) 'Expected compound selector result.'
    Assert-True ($cardTitle.totalEstimatedMatches -ge 1) 'Expected compound selector to match the snapshot.'

    $riskProperties = @($report.performanceRisks | ForEach-Object { $_.property })
    Assert-True ($riskProperties -contains 'transition') 'Expected transition: all to be flagged as a performance risk.'
    Assert-True ($riskProperties -contains 'backdrop-filter') 'Expected backdrop-filter to be flagged as a performance risk.'
    Assert-True ($riskProperties -contains 'background-attachment') 'Expected background-attachment: fixed to be flagged as a performance risk.'
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}

Write-Host 'audit-css test passed'
