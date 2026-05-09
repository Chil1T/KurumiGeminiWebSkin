param(
    [string]$InputCss = (Join-Path $PSScriptRoot 'KurumiskinforAI.css'),
    [string]$HtmlDir = (Join-Path $PSScriptRoot 'htmlsnaps'),
    [string]$OutputJson = (Join-Path $PSScriptRoot 'css-audit-report.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CssRules {
    param([string]$CssText)

    $rules = [System.Collections.Generic.List[object]]::new()
    $matches = [regex]::Matches($CssText, '(?s)([^{}]+)\{([^{}]*)\}')
    foreach ($match in $matches) {
        $selectorText = $match.Groups[1].Value.Trim()
        $declarationsText = $match.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($selectorText)) {
            continue
        }
        if ($selectorText.StartsWith('@')) {
            continue
        }

        $selectors = @($selectorText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($selectors.Count -eq 0) {
            continue
        }

        $declarations = [System.Collections.Generic.List[object]]::new()
        $lines = $declarationsText -split ';'
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if (-not $trimmed) {
                continue
            }
            $parts = $trimmed -split ':', 2
            if ($parts.Count -lt 2) {
                continue
            }
            $declarations.Add([pscustomobject]@{
                property = $parts[0].Trim().ToLowerInvariant()
                value = $parts[1].Trim()
            })
        }

        $rules.Add([pscustomobject]@{
            selectors = $selectors
            declarations = @($declarations)
        })
    }

    return @($rules)
}

function Expand-IsSelectors {
    param([string]$Selector)

    $match = [regex]::Match($Selector, ':is\(([^()]*)\)')
    if (-not $match.Success) {
        return @($Selector)
    }

    $options = @($match.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($option in $options) {
        $replacement = $Selector.Substring(0, $match.Index) + $option + $Selector.Substring($match.Index + $match.Length)
        foreach ($child in Expand-IsSelectors -Selector $replacement) {
            $expanded.Add($child)
        }
    }
    return @($expanded)
}

function Get-SelectorAnchors {
    param([string]$Selector)

    $expandedSelectors = Expand-IsSelectors -Selector $Selector
    $anchorsByVariant = [System.Collections.Generic.List[object]]::new()

    foreach ($expanded in $expandedSelectors) {
        $working = $expanded
        $working = [regex]::Replace($working, '::?[a-zA-Z-]+(\([^)]*\))?', '')
        $working = [regex]::Replace($working, '\s+', ' ').Trim()
        $tokens = [System.Collections.Generic.List[object]]::new()

        foreach ($className in [regex]::Matches($working, '\.([_a-zA-Z][-_a-zA-Z0-9]*)')) {
            $tokens.Add([pscustomobject]@{ type = 'class'; value = $className.Groups[1].Value })
        }

        foreach ($idName in [regex]::Matches($working, '#([_a-zA-Z][-_a-zA-Z0-9]*)')) {
            $tokens.Add([pscustomobject]@{ type = 'id'; value = $idName.Groups[1].Value })
        }

        foreach ($attr in [regex]::Matches($working, '\[([^\]=~\^\$\*\|\s]+)(?:[*\^\$\|~]?=\s*["'']?([^"''\]]+)["'']?)?\]')) {
            $attrName = $attr.Groups[1].Value
            $attrValue = $attr.Groups[2].Value
            $tokens.Add([pscustomobject]@{ type = 'attr'; value = $attrName; match = $attrValue })
        }

        $parts = $working -split '\s+|>'
        foreach ($part in $parts) {
            $clean = $part.Trim()
            if (-not $clean) {
                continue
            }
            $tagMatch = [regex]::Match($clean, '^([a-zA-Z][a-zA-Z0-9-]*)')
            if ($tagMatch.Success) {
                $tagName = $tagMatch.Groups[1].Value.ToLowerInvariant()
                if ($tagName -ne 'where' -and $tagName -ne 'is') {
                    $tokens.Add([pscustomobject]@{ type = 'tag'; value = $tagName })
                }
            }
        }

        $unique = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($token in $tokens) {
            $matchValue = ''
            if ($token.PSObject.Properties.Name -contains 'match') {
                $matchValue = $token.match
            }
            $key = '{0}:{1}:{2}' -f $token.type, $token.value, $matchValue
            if ($seen.Add($key)) {
                $unique.Add($token)
            }
        }

        $anchorsByVariant.Add([pscustomobject]@{
            selector = $expanded
            anchors = @($unique)
        })
    }

    return @($anchorsByVariant)
}

function Get-AnchorCount {
    param(
        [string]$Html,
        [object]$Anchor
    )

    switch ($Anchor.type) {
        'class' {
            $escaped = [regex]::Escape($Anchor.value)
            return ([regex]::Matches($Html, 'class\s*=\s*["''][^"'']*\b' + $escaped + '\b[^"'']*["'']', 'IgnoreCase')).Count
        }
        'id' {
            $escaped = [regex]::Escape($Anchor.value)
            return ([regex]::Matches($Html, 'id\s*=\s*["'']' + $escaped + '["'']', 'IgnoreCase')).Count
        }
        'attr' {
            $name = [regex]::Escape($Anchor.value)
            if ($Anchor.PSObject.Properties.Name -contains 'match' -and $Anchor.match) {
                $value = [regex]::Escape($Anchor.match)
                return ([regex]::Matches($Html, $name + '\s*=\s*["''][^"'']*' + $value + '[^"'']*["'']', 'IgnoreCase')).Count
            }
            return ([regex]::Matches($Html, '\b' + $name + '\b', 'IgnoreCase')).Count
        }
        'tag' {
            $escaped = [regex]::Escape($Anchor.value)
            return ([regex]::Matches($Html, '<' + $escaped + '\b', 'IgnoreCase')).Count
        }
        default {
            return 0
        }
    }
}

function Get-SelectorEstimate {
    param(
        [string]$Html,
        [string]$Selector
    )

    $variants = Get-SelectorAnchors -Selector $Selector
    if ($variants.Count -eq 0) {
        return [pscustomobject]@{
            estimatedMatches = 0
            supported = $false
        }
    }

    $best = 0
    $supported = $false
    foreach ($variant in $variants) {
        $anchors = @($variant.anchors)
        if ($anchors.Count -eq 0) {
            continue
        }

        $supported = $true
        $counts = [System.Collections.Generic.List[int]]::new()
        foreach ($anchor in $anchors) {
            $counts.Add((Get-AnchorCount -Html $Html -Anchor $anchor))
        }

        if ($counts.Count -gt 0) {
            $estimate = ($counts | Measure-Object -Minimum).Minimum
            if ($estimate -gt $best) {
                $best = $estimate
            }
        }
    }

    return [pscustomobject]@{
        estimatedMatches = $best
        supported = $supported
    }
}

function Get-PerformanceRisks {
    param([object[]]$Rules)

    $risks = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $Rules) {
        foreach ($declaration in $rule.declarations) {
            $property = $declaration.property
            $value = $declaration.value.ToLowerInvariant()
            $reason = $null

            switch ($property) {
                'background-attachment' {
                    if ($value -match '\bfixed\b') {
                        $reason = 'Fixed backgrounds can increase repaint cost during scroll.'
                    }
                }
                'backdrop-filter' {
                    $reason = 'Backdrop blur is expensive on large or frequently updated surfaces.'
                }
                'filter' {
                    $reason = 'Filter effects can trigger extra rasterization, especially on text.'
                }
                'transition' {
                    if ($value -match '(^|[\s,])all([\s,]|$)') {
                        $reason = 'transition: all animates more properties than needed.'
                    }
                }
                'box-shadow' {
                    if ($value -match '\b(10px|15px|20px)\b') {
                        $reason = 'Large shadows on frequently updated elements can increase paint cost.'
                    }
                }
            }

            if ($null -ne $reason) {
                $risks.Add([pscustomobject]@{
                    selectors = @($rule.selectors)
                    property = $property
                    value = $declaration.value
                    reason = $reason
                })
            }
        }
    }

    return @($risks)
}

if (-not (Test-Path $InputCss)) {
    throw "Input CSS not found: $InputCss"
}

if (-not (Test-Path $HtmlDir)) {
    throw "HTML snapshot directory not found: $HtmlDir"
}

$htmlFiles = @(Get-ChildItem -Path $HtmlDir -Filter *.html -File)
if ($htmlFiles.Count -eq 0) {
    throw "No HTML snapshot files were found in '$HtmlDir'."
}

$cssText = Get-Content -Path $InputCss -Raw
$cssText = [regex]::Replace($cssText, '/\*.*?\*/', '', 'Singleline')
$rules = Get-CssRules -CssText $cssText

$selectorResults = [System.Collections.Generic.List[object]]::new()
foreach ($rule in $rules) {
    foreach ($selector in $rule.selectors) {
        $perFile = [System.Collections.Generic.List[object]]::new()
        $total = 0
        $supported = $false

        foreach ($file in $htmlFiles) {
            $html = Get-Content -Path $file.FullName -Raw
            $estimate = Get-SelectorEstimate -Html $html -Selector $selector
            if ($estimate.supported) {
                $supported = $true
            }
            $total += [int]$estimate.estimatedMatches
            $perFile.Add([pscustomobject]@{
                file = $file.Name
                estimatedMatches = [int]$estimate.estimatedMatches
            })
        }

        $selectorResults.Add([pscustomobject]@{
            selector = $selector
            totalEstimatedMatches = $total
            supported = $supported
            files = @($perFile)
        })
    }
}

$report = [pscustomobject]@{
    inputCss = (Resolve-Path $InputCss).Path
    htmlDir = (Resolve-Path $HtmlDir).Path
    generatedAt = (Get-Date).ToString('o')
    snapshotCount = $htmlFiles.Count
    selectorCount = $selectorResults.Count
    selectors = @($selectorResults)
    zeroHitSelectors = @($selectorResults | Where-Object { $_.supported -and $_.totalEstimatedMatches -eq 0 } | Select-Object -ExpandProperty selector)
    unsupportedSelectors = @($selectorResults | Where-Object { -not $_.supported } | Select-Object -ExpandProperty selector)
    performanceRisks = @(Get-PerformanceRisks -Rules $rules)
}

$json = $report | ConvertTo-Json -Depth 6
Set-Content -Path $OutputJson -Value $json -Encoding UTF8

Write-Host "CSS audit report written to $OutputJson"
