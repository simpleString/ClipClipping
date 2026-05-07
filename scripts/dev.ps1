param(
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Debug",
    [switch]$NoRun,
    [switch]$Reconfigure,
    [string]$BuildDir = "build",
    [string]$QtPrefix = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $root $BuildDir
$solutionPath = Join-Path $buildPath "ClipClipping.sln"

function Resolve-QtPrefix {
    param([string]$PreferredPrefix)

    if (![string]::IsNullOrWhiteSpace($PreferredPrefix)) {
        return $PreferredPrefix
    }

    $qtRoot = "C:\Qt"
    if (!(Test-Path -LiteralPath $qtRoot)) {
        return ""
    }

    $configs = Get-ChildItem -LiteralPath $qtRoot -Recurse -Filter "Qt6Config.cmake" -ErrorAction SilentlyContinue
    if (!$configs -or $configs.Count -eq 0) {
        return ""
    }

    $picked = $configs |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $picked.FullName))
}

function Resolve-QtBin {
    param([string]$PreferredPrefix)

    $prefix = Resolve-QtPrefix -PreferredPrefix $PreferredPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return ""
    }
    $binPath = Join-Path $prefix "bin"
    if (Test-Path -LiteralPath $binPath) {
        return $binPath
    }
    return ""
}

if ($Reconfigure -and (Test-Path -LiteralPath $buildPath)) {
    Remove-Item -LiteralPath $buildPath -Recurse -Force
}

if (!(Test-Path -LiteralPath $buildPath) -or !(Test-Path -LiteralPath $solutionPath)) {
    $resolvedQtPrefix = Resolve-QtPrefix -PreferredPrefix $QtPrefix
    $configureArgs = @("-S", $root, "-B", $buildPath, "-G", "Visual Studio 17 2022")
    if (![string]::IsNullOrWhiteSpace($resolvedQtPrefix)) {
        $configureArgs += @("-DCMAKE_PREFIX_PATH=$resolvedQtPrefix")
        Write-Host "Using Qt prefix: $resolvedQtPrefix"
    }
    cmake @configureArgs
    if ($LASTEXITCODE -ne 0) {
        if ([string]::IsNullOrWhiteSpace($resolvedQtPrefix)) {
            Write-Host "Qt6 was not found automatically." -ForegroundColor Yellow
            Write-Host "Run with explicit Qt path, for example:" -ForegroundColor Yellow
            Write-Host '.\scripts\dev.ps1 -QtPrefix "C:\Qt\6.6.3\msvc2019_64"' -ForegroundColor Yellow
        }
        exit $LASTEXITCODE
    }
}

cmake --build $buildPath --config $Config --target ClipClipping
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $NoRun) {
    $candidate1 = Join-Path $buildPath "$Config\ClipClipping.exe"
    $candidate2 = Join-Path $buildPath "bin\$Config\ClipClipping.exe"
    $candidate3 = Join-Path $buildPath "bin\ClipClipping.exe"
    $exe = ""
    if (Test-Path -LiteralPath $candidate1) {
        $exe = $candidate1
    } elseif (Test-Path -LiteralPath $candidate2) {
        $exe = $candidate2
    } elseif (Test-Path -LiteralPath $candidate3) {
        $exe = $candidate3
    }
    if ([string]::IsNullOrWhiteSpace($exe)) {
        Write-Error "Built executable not found. Checked: $candidate1 ; $candidate2 ; $candidate3"
        exit 1
    }
    $qtBin = Resolve-QtBin -PreferredPrefix $QtPrefix
    if (![string]::IsNullOrWhiteSpace($qtBin)) {
        if (-not ($env:Path -split ';' | Where-Object { $_ -eq $qtBin })) {
            $env:Path = "$qtBin;$env:Path"
        }
    }
    & $exe
    if ($LASTEXITCODE -eq -1073741515) {
        Write-Host "App failed to start (missing DLL)." -ForegroundColor Yellow
        Write-Host "Tip: run with explicit Qt path:" -ForegroundColor Yellow
        Write-Host '.\scripts\dev.ps1 -QtPrefix "C:\Qt\6.6.3\msvc2019_64"' -ForegroundColor Yellow
    }
}
