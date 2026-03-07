<#
.SYNOPSIS
    Helpers.ps1 — Shared utilities: structured logger, config loader,
    environment variable resolution, and retry wrapper.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Logger factory
# ---------------------------------------------------------------------------

function Get-Logger {
    <#
    .SYNOPSIS
        Returns a simple structured logger hashtable with Info / Warning / Error methods.
    .PARAMETER Name
        Logger name (shown in every line).
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $logLevel = $env:LOG_LEVEL ?? "INFO"
    $logFile  = $env:LOG_FILE

    $fmt = {
        param($Level, $Msg)
        $ts   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $line = "$ts | $($Level.PadRight(8)) | $Name | $Msg"

        switch ($Level.Trim()) {
            "ERROR"   { Write-Host $line -ForegroundColor Red    }
            "WARNING" { Write-Host $line -ForegroundColor Yellow }
            default   { Write-Host $line }
        }

        if ($logFile) {
            Add-Content -Path $logFile -Value $line
        }
    }

    return @{
        Info    = { param($m) & $fmt "INFO"    $m }
        Warning = { param($m) & $fmt "WARNING" $m }
        Error   = { param($m) & $fmt "ERROR"   $m }
    }
}


# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

function Import-CostMonitorConfig {
    <#
    .SYNOPSIS
        Loads settings.json and resolves ${ENV_VAR} placeholders from the environment.
    .PARAMETER Path
        Path to the JSON config file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $(Resolve-Path $Path -ErrorAction SilentlyContinue ?? $Path)"
    }

    $raw    = Get-Content -Path $Path -Raw
    $config = $raw | ConvertFrom-Json -Depth 10

    # Resolve ${VAR_NAME} placeholders recursively
    $config = Resolve-EnvVars -Object $config

    return $config
}


function Resolve-EnvVars {
    <#
    .SYNOPSIS
        Recursively walks a PSCustomObject/hashtable and replaces
        strings matching '${VAR_NAME}' with environment variable values.
    #>
    param (
        [Parameter(Mandatory = $true)]
        $Object
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [string]) {
        if ($Object -match '^\$\{(.+)\}$') {
            $varName = $Matches[1]
            $value   = [System.Environment]::GetEnvironmentVariable($varName)
            if ($null -eq $value) {
                Write-Warning "Environment variable '$varName' is not set."
            }
            return $value
        }
        return $Object
    }

    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        return @($Object | ForEach-Object { Resolve-EnvVars -Object $_ })
    }

    if ($Object -is [PSCustomObject]) {
        $result = [PSCustomObject]@{}
        foreach ($prop in $Object.PSObject.Properties) {
            $result | Add-Member -NotePropertyName $prop.Name `
                                 -NotePropertyValue (Resolve-EnvVars -Object $prop.Value) `
                                 -Force
        }
        return $result
    }

    return $Object
}


# ---------------------------------------------------------------------------
# Azure connection helper
# ---------------------------------------------------------------------------

function Connect-AzureForCostMonitor {
    <#
    .SYNOPSIS
        Authenticates to Azure using a Service Principal (env vars) or
        falls back to az login / Managed Identity via Connect-AzAccount.
    .PARAMETER SubscriptionId
        Subscription to set as the active context.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    $clientId     = $env:AZURE_CLIENT_ID
    $clientSecret = $env:AZURE_CLIENT_SECRET
    $tenantId     = $env:AZURE_TENANT_ID

    if ($clientId -and $clientSecret -and $tenantId) {
        Write-Host "Authenticating via Service Principal..." -ForegroundColor Cyan
        $secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        $credential   = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)

        Connect-AzAccount `
            -ServicePrincipal `
            -Credential  $credential `
            -Tenant      $tenantId `
            -Subscription $SubscriptionId | Out-Null
    }
    else {
        Write-Host "No SP env vars found — attempting interactive / Managed Identity login..." -ForegroundColor Yellow
        Connect-AzAccount -Subscription $SubscriptionId | Out-Null
    }

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Host "Connected. Active subscription: $SubscriptionId" -ForegroundColor Green
}


# ---------------------------------------------------------------------------
# Retry wrapper
# ---------------------------------------------------------------------------

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Runs a script block with exponential back-off retry logic.
    .PARAMETER ScriptBlock
        The script block to execute.
    .PARAMETER MaxAttempts
        Maximum number of attempts. Default: 3
    .PARAMETER DelaySeconds
        Initial delay in seconds between attempts. Default: 2
    .PARAMETER BackoffMultiplier
        Multiplier applied to the delay after each failure. Default: 2
    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Get-AzCostManagementQuery ... } -MaxAttempts 3
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,

        [int]$MaxAttempts      = 3,
        [double]$DelaySeconds  = 2,
        [double]$BackoffMultiplier = 2
    )

    $attempt = 0
    $wait    = $DelaySeconds

    while ($attempt -lt $MaxAttempts) {
        try {
            $attempt++
            return & $ScriptBlock
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                Write-Error "Failed after $MaxAttempts attempt(s): $_"
                throw
            }
            Write-Warning "Attempt $attempt/$MaxAttempts failed: $_. Retrying in ${wait}s..."
            Start-Sleep -Seconds $wait
            $wait *= $BackoffMultiplier
        }
    }
}
