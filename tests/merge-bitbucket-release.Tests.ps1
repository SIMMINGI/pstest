$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'merge-bitbucket-release.ps1'
$gitCalls = [System.Collections.Generic.List[string]]::new()

function git {
    $arguments = @($args)
    $gitCalls.Add(($arguments -join ' '))

    $cloneIndex = [Array]::IndexOf($arguments, 'clone')
    if ($cloneIndex -ge 0) {
        $clonePath = $arguments[-1]
        New-Item -ItemType Directory -Path (Join-Path $clonePath '.git') -Force | Out-Null
    }

    $global:LASTEXITCODE = 0
}

& $scriptPath
if ($LASTEXITCODE -ne 0) {
    throw "스크립트 실행 실패(exit=$LASTEXITCODE)"
}

$cloneCall = $gitCalls | Where-Object { $_ -match '(?:^| )clone(?: |$)' } | Select-Object -First 1
if (-not $cloneCall) {
    throw 'clone 호출을 찾을 수 없습니다.'
}

$expectedPattern = [regex]::Escape('C:\git-tmp\') + 'mbr-[0-9a-f]{8}\\pstest$'
if ($cloneCall -notmatch $expectedPattern) {
    throw "clone 경로가 짧은 고정 작업 경로를 사용하지 않습니다: $cloneCall"
}

Write-Host 'PASS: clone은 C:\git-tmp 아래의 짧은 임시 경로를 사용합니다.'

$gitCalls.Clear()
$overrideBase = Join-Path ([IO.Path]::GetTempPath()) 'mbr-override-test'
try {
    & $scriptPath -WorkRootBase $overrideBase
    if ($LASTEXITCODE -ne 0) {
        throw "스크립트 실행 실패(exit=$LASTEXITCODE)"
    }

    $cloneCall = $gitCalls | Where-Object { $_ -match '(?:^| )clone(?: |$)' } | Select-Object -First 1
    $expectedOverridePattern = [regex]::Escape("$overrideBase\") + 'mbr-[0-9a-f]{8}\\pstest$'
    if ($cloneCall -notmatch $expectedOverridePattern) {
        throw "WorkRootBase 매개변수가 clone 경로에 반영되지 않았습니다: $cloneCall"
    }

    Write-Host 'PASS: WorkRootBase 매개변수로 작업 경로를 변경할 수 있습니다.'
}
finally {
    if (Test-Path -LiteralPath $overrideBase) {
        Remove-Item -LiteralPath $overrideBase -Recurse -Force
    }
}
