param([string]$GodotExe = 'godot')

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$previousAppData = $env:APPDATA
$logRoot = Join-Path $projectPath '.godot\puzzle_checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

function Run-GodotCheck([string]$scriptName, [string]$successPattern) {
    $stdout = Join-Path $logRoot ($scriptName + '.stdout.log')
    $stderr = Join-Path $logRoot ($scriptName + '.stderr.log')
    $run = Start-Process -FilePath $GodotExe -WindowStyle Hidden -PassThru `
        -ArgumentList @('--headless', '--path', $projectPath, '--audio-driver', 'Dummy', '--script', ('res://tests/' + $scriptName + '.gd')) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $runHandle = $run.Handle
    if (-not $run.WaitForExit(60000)) {
        $run.Kill()
        throw "$scriptName timed out; inspect $logRoot"
    }
    $run.WaitForExit()
    if ($run.ExitCode -ne 0 -or
        (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script') -or
        -not (Select-String -LiteralPath $stdout -Pattern $successPattern)) {
        Get-Content -LiteralPath $stderr
        throw "$scriptName failed; inspect $logRoot"
    }
    Get-Content -LiteralPath $stdout | Select-String -Pattern $successPattern
}

Push-Location $projectPath
try {
    $env:APPDATA = Join-Path $projectPath '.godot\puzzle_test_user'
    New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
    Run-GodotCheck 'export_alchemical_boards' 'EXPORTED ALCHEMY BOARDS: 48'
    & python tests/alchemical_solver_audit.py > (Join-Path $logRoot 'solver.log')
    if ($LASTEXITCODE -ne 0) { throw 'Alchemy solver audit failed' }
    Get-Content -LiteralPath (Join-Path $logRoot 'solver.log') | Select-Object -Last 1
    Run-GodotCheck 'potion_stress_smoke' 'POTION STRESS: \d+ checks, 0 failures'
    Run-GodotCheck 'alchemical_rules_smoke' 'ALCHEMY RULES: \d+ checks, 0 failures'
    Run-GodotCheck 'puzzle_session_smoke' 'PUZZLE SESSION: \d+ checks, 0 failures'
    Run-GodotCheck 'potion_checkpoint_smoke' 'POTION CHECKPOINT: \d+ checks, 0 failures'
    Run-GodotCheck 'ui_feedback_smoke' 'UI FEEDBACK: \d+ checks, 0 failures'
} finally {
    $env:APPDATA = $previousAppData
    Pop-Location
}
