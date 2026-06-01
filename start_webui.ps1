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

function Test-TcpPortAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [Parameter(Mandatory = $true)][int]$Port
    )

    if ($Address -eq "0.0.0.0") {
        $ipAddress = [Net.IPAddress]::Any
    } else {
        $ipAddress = $null
        foreach ($candidate in [Net.Dns]::GetHostAddresses($Address)) {
            if ($candidate.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
                $ipAddress = $candidate
                break
            }
        }

        if ($null -eq $ipAddress) {
            throw "Could not resolve IPv4 address for $Address."
        }
    }

    $listener = [Net.Sockets.TcpListener]::new($ipAddress, $Port)
    try {
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        try {
            $listener.Stop()
        } catch {
        }
    }
}

Ensure-LocalConfig
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "storage") | Out-Null

$webHost = if ($env:MPT_WEBUI_HOST) { $env:MPT_WEBUI_HOST } else { "127.0.0.1" }
$requestedPort = if ($env:MPT_WEBUI_PORT) { [int]$env:MPT_WEBUI_PORT } else { 8501 }

$candidatePorts = New-Object System.Collections.Generic.List[int]
$candidatePorts.Add($requestedPort)
foreach ($port in 8502..8599) {
    if ($port -ne $requestedPort) {
        $candidatePorts.Add($port)
    }
}

$selectedPort = $null
foreach ($port in $candidatePorts) {
    if (Test-TcpPortAvailable -Address $webHost -Port $port) {
        $selectedPort = $port
        break
    }
}

if ($null -eq $selectedPort) {
    throw "No available WebUI port found in 8501-8599 for $webHost."
}

if ($selectedPort -ne $requestedPort) {
    Write-Host "Port $requestedPort is unavailable, using $selectedPort instead."
}

$runner = Get-PythonRunner
$arguments = @(
    $runner.Prefix
    "-m"
    "streamlit"
    "run"
    ".\webui\Main.py"
    "--server.address=$webHost"
    "--server.port=$selectedPort"
    "--browser.serverAddress=$webHost"
    "--browser.gatherUsageStats=False"
    "--server.headless=True"
    "--server.enableCORS=True"
)

Write-Host "WebUI address: http://$webHost`:$selectedPort"
& $runner.Command @arguments
