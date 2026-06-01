Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ProjectRoot
$env:PYTHONPATH = $ProjectRoot

function Ensure-LocalConfig {
    $configPath = Join-Path $ProjectRoot "config.toml"
    $examplePath = Join-Path $ProjectRoot "config.example.toml"

    if (-not (Test-Path -LiteralPath $configPath)) {
        if (-not (Test-Path -LiteralPath $examplePath)) {
            throw "config.example.toml was not found."
        }

        Copy-Item -LiteralPath $examplePath -Destination $configPath
        Write-Host "Created local config.toml from config.example.toml."
        Write-Host "Edit config.toml and add your own API keys before generating videos."
    }
}

function Get-PythonRunner {
    $venvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
        return @{
            Command = $venvPython
            Prefix = @()
        }
    }

    $uvCommand = Get-Command uv -ErrorAction SilentlyContinue
    if ($null -ne $uvCommand) {
        return @{
            Command = $uvCommand.Source
            Prefix = @("run", "--python", "3.11", "python")
        }
    }

    throw "Python environment was not found. Install uv, then run: uv python install 3.11; uv sync --frozen --python 3.11"
}

Ensure-LocalConfig
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "storage") | Out-Null

$runner = Get-PythonRunner
$arguments = @(
    $runner.Prefix
    "main.py"
)

Write-Host "Starting API. Default docs URL: http://127.0.0.1:8080/docs"
Write-Host "The API host and port are controlled by listen_host/listen_port in config.toml."
& $runner.Command @arguments
