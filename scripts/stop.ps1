<#
.SYNOPSIS
    Остановка Hadoop-контейнеров на этой машине.
#>

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$composeFile = Join-Path $RepoRoot "docker-compose.generated.yml"

Write-Host ""
Write-Host ">>> Stopping containers..." -ForegroundColor Cyan

if (-not (Test-Path $composeFile)) {
    Write-Host "  docker-compose.generated.yml not found - nothing to stop" -ForegroundColor Yellow
    exit 0
}

Push-Location $RepoRoot
try {
    $removeVolumes = $args -contains "-v"
    if ($removeVolumes) {
        Write-Host "  (removing volumes)" -ForegroundColor Red
        docker compose -f docker-compose.generated.yml down -v
    } else {
        docker compose -f docker-compose.generated.yml down
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "  Containers stopped." -ForegroundColor Green
Write-Host ""