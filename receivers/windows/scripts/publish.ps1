[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot "../../../artifacts/windows"),
    [switch] $SkipRestore,
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"
$receiverRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $receiverRoot "src/PhoneSnap.Windows/PhoneSnap.Windows.csproj"
$tests = Join-Path $receiverRoot "tests/PhoneSnap.Core.Tests/PhoneSnap.Core.Tests.csproj"

Push-Location $receiverRoot
try {
    if (-not $SkipRestore) {
        dotnet restore PhoneSnap.Windows.slnx --locked-mode
        if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
    }

    if (-not $SkipTests) {
        dotnet test $tests --configuration Release --no-restore
        if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }
    }

    foreach ($runtime in @("win-x64", "win-arm64")) {
        $publishDirectory = Join-Path $OutputDirectory $runtime
        $archive = Join-Path $OutputDirectory "PhoneSnap-$runtime.zip"

        Remove-Item $publishDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $archive -Force -ErrorAction SilentlyContinue

        dotnet publish $project `
            --configuration Release `
            --runtime $runtime `
            --self-contained true `
            --no-restore `
            --output $publishDirectory `
            -p:PublishSingleFile=true
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $runtime" }

        Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $archive
        Write-Host "Created $archive"
    }
}
finally {
    Pop-Location
}
