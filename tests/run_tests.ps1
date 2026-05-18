# Test runner - runs all phase tests sequentially
# Usage: .\tests\run_tests.ps1 [phase]
# Example: .\tests\run_tests.ps1 phase4

param(
    [string]$Phase = "all"
)

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = @()

function Run-Test {
    param(
        [string]$TestPath,
        [string]$TestName
    )
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Running: $TestName" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    
    try {
        & $TestPath
        $status = "PASS"
        $color = "Green"
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        $status = "FAIL"
        $color = "Red"
    }
    
    Write-Host "`n[$status] $TestName" -ForegroundColor $color
    return @{
        Name = $TestName
        Status = $status
        Path = $TestPath
    }
}

# Get test files
$phases = @()
if ($Phase -eq "all") {
    $phases = Get-ChildItem -Path $testDir -Directory | Where-Object { $_.Name -match "^phase\d+" } | Sort-Object Name
} else {
    $phases = Get-ChildItem -Path $testDir -Directory | Where-Object { $_.Name -eq $Phase }
}

if ($phases.Count -eq 0) {
    Write-Host "No phases found matching: $Phase" -ForegroundColor Red
    exit 1
}

# Run tests
foreach ($phaseDir in $phases) {
    $testFiles = Get-ChildItem -Path $phaseDir.FullName -Filter "test_*.ps1" | Sort-Object Name
    
    if ($testFiles.Count -eq 0) {
        Write-Host "`nNo tests found in $($phaseDir.Name)" -ForegroundColor Yellow
        continue
    }
    
    foreach ($testFile in $testFiles) {
        $result = Run-Test -TestPath $testFile.FullName -TestName "$($phaseDir.Name)/$($testFile.Name)"
        $results += $result
    }
}

# Summary
Write-Host "`n`n" -ForegroundColor Cyan
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                      TEST SUMMARY                              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = @($results).Count

foreach ($result in $results) {
    $color = if ($result.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  [$($result.Status)] $($result.Name)" -ForegroundColor $color
}

Write-Host "`nTotal: $total | Passed: $passed | Failed: $failed" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
