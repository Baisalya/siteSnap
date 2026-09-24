[CmdletBinding()]
param(
    [switch] $RunQualityChecks
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bundleRelativePath = 'build\app\outputs\bundle\release\app-release.aab'

function Invoke-FlutterReleaseStep {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

Push-Location $repositoryRoot
try {
    Invoke-FlutterReleaseStep -Arguments @('pub', 'get')
    if ($RunQualityChecks) {
        Invoke-FlutterReleaseStep -Arguments @('analyze', '--no-pub')
        Invoke-FlutterReleaseStep -Arguments @('test', '--no-pub')
    } else {
        Write-Host 'Quality checks skipped. This command is packaging-only; use -RunQualityChecks for fresh analyze/test.' -ForegroundColor Yellow
    }
    Invoke-FlutterReleaseStep -Arguments @(
        'build',
        'appbundle',
        '--release',
        '--dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false',
        '--dart-define=SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION=false',
        '--dart-define=SURVEYCAM_PURCHASE_VERIFICATION_URL=https://baisalya-entitlement-api.baishalya1999.workers.dev/v1/google-play/verify',
        '--dart-define=SURVEYCAM_PRO_PRODUCT_ID=surveycam_pro',
        '--dart-define=SURVEYCAM_PRO_BASE_PLAN_ID=annual199',
        '--dart-define=SURVEYCAM_PRO_OFFER_ID=launch-1y-free',
        '--dart-define=SURVEYCAM_PRO_LAUNCH_OFFER_ENDS_AT=2027-02-11T23:59:59+05:30',
        '--dart-define=SURVEYCAM_ADMOB_REWARDED_ID=ca-app-pub-1529558529658186/7575240208'
    )

    $bundlePath = (Resolve-Path -LiteralPath $bundleRelativePath).Path
    $bundle = Get-Item -LiteralPath $bundlePath
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $bundlePath

    Write-Host "Google Play AAB: $bundlePath" -ForegroundColor Green
    Write-Host "Size: $($bundle.Length) bytes"
    Write-Host "SHA-256: $($hash.Hash)"
    Write-Host "Fresh quality checks: $($RunQualityChecks.IsPresent)"
} finally {
    Pop-Location
}
