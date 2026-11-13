$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
python -m venv .venv
if ($LASTEXITCODE) { throw 'venv creation failed' }
& .\.venv\Scripts\python.exe -m pip install -e .
if ($LASTEXITCODE) { throw 'dependency installation failed' }
Write-Host 'Run .\.venv\Scripts\tradewinds.exe doctor'
