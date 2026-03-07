#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Azure Cost Monitor & Alert Dashboard — Entry Point

.DESCRIPTION
    Queries Azure Cost Management, evaluates budget thresholds,
    dispatches alerts via Email and Microsoft Teams, and writes
    JSON + CSV reports.

.PARAMETER SubscriptionId
    Azure Subscription ID to monitor.

.PARAMETER Days
    Number of past days to analyse. Default: 30

.PARAMETER ConfigPath
    Path to settings.json. Default: config/settings.json

.PARAMETER OutputDir
    Directory to write report files. Default: reports

.EXAMPLE
    .\main.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.EXAMPLE
    .\main.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Days 7 -OutputDir "./reports"

.NOTES
    Requires: Az.Accounts, Az.CostManagement modules
    Auth    : DefaultAzureCredential — Service Principal env vars or az login
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config/settings.json",

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Bootstrap — dot-source all modules
# ---------------------------------------------------------------------------
$srcPath = Join-Path $PSScriptRoot "src"

. "$srcPath/Helpers.ps1"
. "$srcPath/Get-AzureCosts.ps1"
. "$srcPath/Invoke-AlertEngine.ps1"
. "$srcPath/New-CostReport.ps1"

$logger = Get-Logger -Name "main"

# ---------------------------------------------------------------------------
# 1. Load configuration
# ---------------------------------------------------------------------------
$logger.Info("Loading configuration from: $ConfigPath")

try {
    $config = Import-CostMonitorConfig -Path $ConfigPath
}
catch {
    $logger.Error("Failed to load config: $_")
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Connect to Azure
# ---------------------------------------------------------------------------
$logger.Info("Connecting to Azure (Subscription: $SubscriptionId)...")

try {
    Connect-AzureForCostMonitor -SubscriptionId $SubscriptionId
}
catch {
    $logger.Error("Azure authentication failed: $_")
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Fetch cost data
# ---------------------------------------------------------------------------
$logger.Info("Fetching cost data for the last $Days days...")

$subscriptionTotal  = Get-SubscriptionTotalCost  -SubscriptionId $SubscriptionId -Days $Days
$costByResourceGroup = Get-CostByResourceGroup   -SubscriptionId $SubscriptionId -Days $Days
$costByService       = Get-CostByService         -SubscriptionId $SubscriptionId -Days $Days

$logger.Info("Data fetch complete.")

# ---------------------------------------------------------------------------
# 4. Evaluate alerts
# ---------------------------------------------------------------------------
$logger.Info("Evaluating alert thresholds...")

$alerts = Invoke-ThresholdEvaluation `
    -SubscriptionTotal $subscriptionTotal `
    -CostByService     $costByService `
    -Thresholds        $config.alert_thresholds

Send-Alerts -Alerts $alerts -Config $config

# ---------------------------------------------------------------------------
# 5. Generate reports
# ---------------------------------------------------------------------------
$logger.Info("Generating reports in: $OutputDir")

$reportPaths = New-CostReport `
    -SubscriptionTotal   $subscriptionTotal `
    -CostByResourceGroup $costByResourceGroup `
    -CostByService       $costByService `
    -Alerts              $alerts `
    -Days                $Days `
    -OutputDir           $OutputDir

$logger.Info("All done. Reports:")
foreach ($entry in $reportPaths.GetEnumerator()) {
    $logger.Info("  [$($entry.Key.ToUpper())]  $($entry.Value)")
}

exit 0
