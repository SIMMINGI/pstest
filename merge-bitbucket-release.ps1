<#
.SYNOPSIS
    Bitbucket 저장소별 지정 브랜치를 skhynix-release 브랜치로 병합하고 push합니다.

.DESCRIPTION
    기존 SSH 키 또는 SSH agent 인증을 사용합니다. 각 저장소는 독립된 임시 폴더에서
    처리하므로 한 저장소에서 충돌이나 오류가 발생해도 다음 저장소를 계속 처리합니다.
    대상 브랜치가 원격에 없으면 자동으로 만들지 않고 해당 저장소를 실패 처리합니다.

.EXAMPLE
    .\merge-bitbucket-release.ps1
#>

# 링크 예제 git@github.com:SIMMINGI/pstest.git
#param(
#    [string]$BitbucketHost = 'github.com',
#    [string]$Workspace = 'SIMMINGI',
#    [string]$TargetBranch = 'test-branch'
#

[CmdletBinding()]
param(
    [string]$BitbucketHost = 'github.com',
    [string]$Workspace = 'SIMMINGI',
    [string]$TargetBranch = 'test-branch'
)

$Repositories = @(
    [pscustomobject]@{ Name = 'pstest'; SourceBranch = 'main' }
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "$timestamp [$Level] $Message"
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Log 'INFO' ("git {0}" -f ($Arguments -join ' '))
    # Windows PowerShell 5.1은 native stderr를 ErrorRecord로 변환합니다.
    # git의 종료 코드를 직접 판정할 수 있도록 호출 중에는 non-terminating으로 수집합니다.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $details = ($output | Out-String).Trim()
        if ($details) {
            throw "git 명령 실패(exit=$exitCode): git $($Arguments -join ' ')`n$details"
        }
        throw "git 명령 실패(exit=$exitCode): git $($Arguments -join ' ')"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Test-RemoteBranch {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$Branch
    )

    $result = Invoke-Git -Arguments @(
        '-C', $RepositoryPath,
        'show-ref', '--verify', '--quiet',
        "refs/remotes/origin/$Branch"
    ) -AllowFailure

    return $result.ExitCode -eq 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log 'ERROR' 'git을 찾을 수 없습니다. Git을 설치하고 PATH에 추가한 뒤 다시 실행하세요.'
    exit 1
}

if ([string]::IsNullOrWhiteSpace($BitbucketHost) -or
    [string]::IsNullOrWhiteSpace($Workspace) -or
    [string]::IsNullOrWhiteSpace($TargetBranch)) {
    Write-Log 'ERROR' 'BitbucketHost, Workspace, TargetBranch는 비워 둘 수 없습니다.'
    exit 1
}

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ("merge-bitbucket-release-{0}" -f [guid]::NewGuid())
$results = [System.Collections.Generic.List[object]]::new()

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    Invoke-Git -Arguments @('--version') | Out-Null

    foreach ($repository in $Repositories) {
        $name = [string]$repository.Name
        $sourceBranch = [string]$repository.SourceBranch
        $repositoryPath = Join-Path $workRoot $name
        $repositoryUrl = "git@${BitbucketHost}:$Workspace/$name.git"

        Write-Log 'INFO' "[$name] $sourceBranch -> $TargetBranch 병합을 시작합니다."

        try {
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($sourceBranch)) {
                throw '저장소 이름과 소스 브랜치는 비워 둘 수 없습니다.'
            }
            if ($sourceBranch -eq $TargetBranch) {
                throw "소스 브랜치와 대상 브랜치가 같습니다: $sourceBranch"
            }

            Invoke-Git -Arguments @('clone', '--origin', 'origin', $repositoryUrl, $repositoryPath) | Out-Null
            Invoke-Git -Arguments @('-C', $repositoryPath, 'fetch', '--prune', 'origin') | Out-Null

            if (-not (Test-RemoteBranch -RepositoryPath $repositoryPath -Branch $sourceBranch)) {
                throw "원격 소스 브랜치가 없습니다: origin/$sourceBranch"
            }
            if (-not (Test-RemoteBranch -RepositoryPath $repositoryPath -Branch $TargetBranch)) {
                throw "원격 대상 브랜치가 없습니다: origin/$TargetBranch"
            }

            Invoke-Git -Arguments @(
                '-C', $repositoryPath,
                'checkout', '-B', $TargetBranch, "origin/$TargetBranch"
            ) | Out-Null
            Invoke-Git -Arguments @(
                '-C', $repositoryPath,
                'merge', '--no-ff', '--no-edit', "origin/$sourceBranch"
            ) | Out-Null
            Invoke-Git -Arguments @(
                '-C', $repositoryPath,
                'push', 'origin', $TargetBranch
            ) | Out-Null

            $results.Add([pscustomobject]@{
                Repository = $name
                SourceBranch = $sourceBranch
                Status = 'SUCCESS'
                Message = '병합 및 push 완료'
            })
            Write-Log 'OK' "[$name] 병합 및 push를 완료했습니다."
        }
        catch {
            $mergeHead = Join-Path $repositoryPath '.git/MERGE_HEAD'
            if (Test-Path -LiteralPath $mergeHead) {
                Invoke-Git -Arguments @('-C', $repositoryPath, 'merge', '--abort') -AllowFailure | Out-Null
            }

            $message = $_.Exception.Message
            $results.Add([pscustomobject]@{
                Repository = $name
                SourceBranch = $sourceBranch
                Status = 'FAILED'
                Message = $message
            })
            Write-Log 'ERROR' "[$name] 실패: $message"
        }
    }
}
catch {
    Write-Log 'ERROR' "실행 준비 중 오류가 발생했습니다: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}

Write-Host ''
Write-Host '================ 처리 결과 ================'
$results | Format-Table Repository, SourceBranch, Status, Message -AutoSize -Wrap

$failedCount = @($results | Where-Object Status -eq 'FAILED').Count
$successCount = @($results | Where-Object Status -eq 'SUCCESS').Count
Write-Log 'INFO' "성공: $successCount, 실패: $failedCount, 전체: $($results.Count)"

if ($failedCount -gt 0) {
    exit 1
}

exit 0
