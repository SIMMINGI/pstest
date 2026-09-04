$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'merge-bitbucket-release_260904.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("mbr-cache-test-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$gitCalls = [System.Collections.Generic.List[string]]::new()

function git {
    $arguments = @($args)
    $gitCalls.Add(($arguments -join ' '))

    $cloneIndex = [Array]::IndexOf($arguments, 'clone')
    if ($cloneIndex -ge 0) {
        $clonePath = $arguments[-1]
        New-Item -ItemType Directory -Path (Join-Path $clonePath '.git') -Force | Out-Null
    }

    if (($arguments -join ' ') -match 'remote get-url origin') {
        'git@github.com:SIMMINGI/pstest.git'
    }

    $global:LASTEXITCODE = 0
}

try {
    & $scriptPath -WorkRootBase $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw "첫 번째 실행 실패(exit=$LASTEXITCODE)"
    }

    $repositoryPath = Join-Path $testRoot 'pstest'
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryPath '.git'))) {
        throw '첫 번째 실행 후 clone 저장소가 보존되지 않았습니다.'
    }

    & $scriptPath -WorkRootBase $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw "두 번째 실행 실패(exit=$LASTEXITCODE)"
    }

    $cloneCalls = @($gitCalls | Where-Object { $_ -match '(?:^| )clone(?: |$)' })
    if ($cloneCalls.Count -ne 1) {
        throw "기존 저장소를 재사용하지 않고 clone을 $($cloneCalls.Count)회 실행했습니다."
    }

    $fetchCalls = @($gitCalls | Where-Object { $_ -match '(?:^| )fetch --prune origin$' })
    if ($fetchCalls.Count -ne 2) {
        throw "각 실행에서 fetch가 수행되지 않았습니다. 실제 횟수: $($fetchCalls.Count)"
    }

    Write-Host 'PASS: 첫 실행은 clone하고 이후 실행은 기존 저장소를 fetch하여 재사용합니다.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
