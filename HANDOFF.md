# 작업 핸드오프

## 작업 위치

- 저장소: `/Users/a10177/dev/testtest/pstest`
- 원격 저장소: `https://github.com/SIMMINGI/pstest.git`
- 현재 브랜치: `main`
- 확인한 기준 커밋: `851aafb Add Bitbucket release merge script`

## 작업 목적

여러 Git 저장소에서 지정한 소스 브랜치를 `skhynix-release` 브랜치에 `--no-ff` 방식으로 병합하고 push하는 PowerShell 스크립트를 만든다. 실제 운영 대상은 Bitbucket이지만, 현재는 GitHub 테스트 저장소로 동작을 검증한다.

GitHub 테스트 설정은 다음과 같다.

```text
SSH URL:       git@github.com:SIMMINGI/pstest.git
Git host:      github.com
Owner:         SIMMINGI
Repository:    pstest
Source branch: main
Target branch: skhynix-release
```

## 현재 구현

대상 파일은 `merge-bitbucket-release.ps1`이다.

현재 구현에는 다음 동작이 들어 있다.

- 기존 SSH 키 또는 SSH agent를 이용한 clone/fetch/push
- 저장소별 독립 임시 디렉터리 사용
- 원격 소스 및 대상 브랜치 존재 여부 확인
- `git merge --no-ff --no-edit` 실행
- 실제 병합 중 충돌이 발생했을 때만 `git merge --abort` 실행
- 한 저장소 실패 후에도 다음 저장소 계속 처리
- 저장소별 성공/실패 요약과 실패 시 종료 코드 `1`
- Windows PowerShell 5.1에서 native Git stderr를 직접 처리하도록 보완

## 현재 상태에서 꼭 수정할 부분

저장소에 커밋된 스크립트의 기본값은 아직 예시 값이다.

```powershell
[string]$BitbucketHost = 'testbuc.com'
[string]$Workspace = 'testws'

$Repositories = @(
    [pscustomobject]@{ Name = 'testrepo1'; SourceBranch = 'dev' }
    [pscustomobject]@{ Name = 'testrepo2'; SourceBranch = 'main' }
)
```

GitHub 테스트를 위해 아래 값으로 변경해야 한다.

```powershell
[string]$BitbucketHost = 'github.com'
[string]$Workspace = 'SIMMINGI'

$Repositories = @(
    [pscustomobject]@{ Name = 'pstest'; SourceBranch = 'main' }
)
```

또한 현재 저장소의 `merge-bitbucket-release.ps1`은 UTF-8 BOM 없이 저장되어 있다. Windows PowerShell 5.1에서 한글이 깨지지 않도록 **UTF-8 with BOM**으로 다시 저장해야 한다.

## 브랜치 상태 관련 주의사항

확인 시점의 원격 브랜치는 `main`과 `test-branch`뿐이며 `skhynix-release`는 확인되지 않았다. 현재 스크립트는 대상 브랜치를 자동 생성하지 않으므로, 테스트 전에 원격 `skhynix-release` 브랜치를 먼저 만들거나 자동 생성 정책을 별도로 결정해야 한다.

## Windows 실행 정책

서명되지 않은 로컬 스크립트를 현재 사용자에게 영구 허용하려면 일반 PowerShell에서 다음을 한 번 실행한다.

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
Unblock-File -LiteralPath .\merge-bitbucket-release.ps1
```

정책 확인:

```powershell
Get-ExecutionPolicy -List
```

`MachinePolicy` 또는 `UserPolicy`가 설정되어 있으면 회사 정책이 우선하므로 임의로 우회하지 않는다.

## 다음 작업 순서

1. 스크립트 기본값을 GitHub 테스트 설정으로 변경한다.
2. 스크립트를 UTF-8 BOM으로 저장한다.
3. `skhynix-release` 원격 브랜치 존재 여부를 확인하고, 없을 때 처리 방식을 결정한다.
4. 실제 push 전에 SSH 접속과 대상 브랜치를 확인한다.
5. 정상 병합, 충돌, 대상 브랜치 누락 시나리오를 검증한다.

현재 저장소에는 이 스크립트용 자동화 테스트가 없다. 실제 원격 push는 상태를 바꾸는 작업이므로 대상 URL과 브랜치를 확인한 뒤 실행한다.
