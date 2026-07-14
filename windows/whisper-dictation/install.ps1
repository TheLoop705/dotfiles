[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$taskName = 'Whisper Dictation'
$sourceRoot = $PSScriptRoot
$appRoot = Join-Path $env:LOCALAPPDATA 'WhisperDictation'
$venvRoot = Join-Path $appRoot 'venv'
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'
$venvPythonw = Join-Path $venvRoot 'Scripts\pythonw.exe'
$serviceScript = Join-Path $appRoot 'whisper_dictation.py'
$requirements = Join-Path $sourceRoot 'requirements.txt'
$userId = "$env:USERDOMAIN\$env:USERNAME"

try {
    $basePython = (& py -3.13 -c 'import sys; print(sys.executable)') | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $basePython) {
        throw 'Python 3.13 was not found.'
    }
}
catch {
    throw 'Install Python 3.13 first: winget install --id Python.Python.3.13 --exact --source winget'
}

New-Item -ItemType Directory -Path $appRoot -Force | Out-Null

if (-not (Test-Path -LiteralPath $venvPython)) {
    & $basePython -m venv $venvRoot
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install --requirement $requirements

Copy-Item -LiteralPath (Join-Path $sourceRoot 'whisper_dictation.py') -Destination $serviceScript -Force
$config = [ordered]@{
    model        = 'small'
    device       = 'cpu'
    compute_type = 'int8'
    cpu_threads  = 8
    sample_rate  = 16000
    hotkey       = 'ctrl+shift+space'
    beam_size    = 5
    model_dir    = Join-Path $appRoot 'models'
    log_dir      = Join-Path $appRoot 'logs'
    model_path   = $null
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appRoot 'config.json') -Encoding utf8

Write-Host 'Downloading and loading the local multilingual Whisper small model...'
& $venvPython $serviceScript --warmup

$snapshotsPath = Join-Path $config.model_dir 'models--Systran--faster-whisper-small\snapshots'
$modelSnapshot = Get-ChildItem -LiteralPath $snapshotsPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $modelSnapshot) {
    throw "Whisper small downloaded but no model snapshot was found in $snapshotsPath"
}
$config.model_path = $modelSnapshot.FullName
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appRoot 'config.json') -Encoding utf8

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask -and $existingTask.State -eq 'Running') {
    Stop-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 1
}

$action = New-ScheduledTaskAction -Execute $venvPythonw -Argument ('"{0}"' -f $serviceScript) -WorkingDirectory $appRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Description 'Local Whisper small-model dictation; Ctrl+Shift+Space toggles recording.' `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName $taskName
if ($task.State -ne 'Running') {
    throw "The $taskName task did not stay running. See $appRoot\logs\dictation.log."
}

Write-Host "Ready. Press Ctrl+Shift+Space to start recording, then press it again to transcribe and type the result."
