<#
.SYNOPSIS
    New-CostReport.ps1 — Generates cost summary reports as:
      - JSON  (machine-readable, timestamped)
      - CSV   by Service
      - CSV   by Resource Group
      - Console summary table
#>

Set-StrictMode -Version Latest

function New-CostReport {
    <#
    .SYNOPSIS
        Writes all report artefacts to OutputDir and prints a console summary.
    .PARAMETER SubscriptionTotal
        Hashtable: { TotalCostUSD, Currency }
    .PARAMETER CostByResourceGroup
        Array of RG cost rows.
    .PARAMETER CostByService
        Array of service cost rows.
    .PARAMETER Alerts
        Array of triggered alert hashtables.
    .PARAMETER Days
        Lookback window (for metadata).
    .PARAMETER OutputDir
        Directory to write output files.
    .OUTPUTS
        Hashtable of { json, csv_service, csv_rg } => file paths.
    #>
    param (
        [Parameter(Mandatory = $true)] [hashtable]$SubscriptionTotal,
        [Parameter(Mandatory = $true)] [array]$CostByResourceGroup,
        [Parameter(Mandatory = $true)] [array]$CostByService,
        [Parameter(Mandatory = $true)] [array]$Alerts,
        [Parameter(Mandatory = $true)] [int]$Days,
        [Parameter(Mandatory = $true)] [string]$OutputDir
    )

    $logger = Get-Logger -Name "New-CostReport"

    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $ts = (Get-Date -Format "yyyyMMdd_HHmmss")

    # Sort services by cost descending
    $sortedServices = $CostByService | Sort-Object { [double]$_["Cost"] } -Descending

    # Build JSON payload
    $payload = [ordered]@{
        generated_at       = (Get-Date -Format "o")
        period_days        = $Days
        subscription_total = $SubscriptionTotal
        top_services       = @($sortedServices | Select-Object -First 10)
        resource_groups    = $CostByResourceGroup
        alerts             = $Alerts
    }

    # Write JSON
    $jsonPath = Join-Path $OutputDir "cost_report_$ts.json"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    $logger.Info("JSON report → $jsonPath")

    # Write CSV — by service
    $csvServicePath = Join-Path $OutputDir "cost_by_service_$ts.csv"
    if ($CostByService.Count -gt 0) {
        $CostByService | ForEach-Object {
            [PSCustomObject]$_
        } | Export-Csv -Path $csvServicePath -NoTypeInformation -Encoding UTF8
        $logger.Info("CSV (by service) → $csvServicePath")
    }

    # Write CSV — by resource group
    $csvRgPath = Join-Path $OutputDir "cost_by_rg_$ts.csv"
    if ($CostByResourceGroup.Count -gt 0) {
        $CostByResourceGroup | ForEach-Object {
            [PSCustomObject]$_
        } | Export-Csv -Path $csvRgPath -NoTypeInformation -Encoding UTF8
        $logger.Info("CSV (by resource group) → $csvRgPath")
    }

    # Print console summary
    Write-CostSummary `
        -SubscriptionTotal $SubscriptionTotal `
        -TopServices       $sortedServices `
        -Alerts            $Alerts `
        -Days              $Days

    return @{
        json        = $jsonPath
        csv_service = $csvServicePath
        csv_rg      = $csvRgPath
    }
}


function Write-CostSummary {
    <#
    .SYNOPSIS
        Prints a formatted cost summary table to the console.
    #>
    param (
        [hashtable]$SubscriptionTotal,
        [array]$TopServices,
        [array]$Alerts,
        [int]$Days
    )

    $sep = "=" * 62

    Write-Host ""
    Write-Host $sep -ForegroundColor Cyan
    Write-Host "  AZURE COST MONITOR — SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "  Period  : Last $Days days"
    Write-Host "  Run at  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    Write-Host $sep -ForegroundColor Cyan

    Write-Host ("  Subscription total : `${0:N4} {1}" -f `
        $SubscriptionTotal.TotalCostUSD, $SubscriptionTotal.Currency) `
        -ForegroundColor White

    Write-Host ""
    Write-Host "  Top Services by Cost:" -ForegroundColor White

    foreach ($svc in ($TopServices | Select-Object -First 5)) {
        $name = $svc["ServiceName"]
        $cost = [double]$svc["Cost"]
        Write-Host ("    {0,-38} `${1,10:N4}" -f $name, $cost)
    }

    Write-Host ""

    if ($Alerts.Count -gt 0) {
        Write-Host "  ⚠  $($Alerts.Count) ALERT(S) TRIGGERED:" -ForegroundColor Yellow
        foreach ($alert in $Alerts) {
            $color = if ($alert.Level -eq "CRITICAL") { "Red" } else { "Yellow" }
            Write-Host "    [$($alert.Level)] $($alert.Message)" -ForegroundColor $color
        }
    }
    else {
        Write-Host "  ✓  No thresholds breached." -ForegroundColor Green
    }

    Write-Host $sep -ForegroundColor Cyan
    Write-Host ""
}
