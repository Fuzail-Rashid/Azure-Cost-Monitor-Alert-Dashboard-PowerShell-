<#
.SYNOPSIS
    Get-AzureCosts.ps1 — Queries Azure Cost Management via Az.CostManagement
    and returns structured cost data grouped by ResourceGroup or Service.
#>

Set-StrictMode -Version Latest

function Get-SubscriptionTotalCost {
    <#
    .SYNOPSIS
        Returns the total cost for the subscription over the last N days.
    .PARAMETER SubscriptionId
        Azure Subscription ID.
    .PARAMETER Days
        Number of past days to query.
    .OUTPUTS
        Hashtable: { TotalCostUSD, Currency }
    #>
    param (
        [Parameter(Mandatory = $true)]  [string]$SubscriptionId,
        [Parameter(Mandatory = $false)] [int]$Days = 30
    )

    $logger = Get-Logger -Name "Get-SubscriptionTotalCost"
    $logger.Info("Querying subscription total for last $Days days...")

    $start = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddT00:00:00Z")
    $end   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT00:00:00Z")
    $scope = "/subscriptions/$SubscriptionId"

    $result = Invoke-WithRetry -ScriptBlock {
        Invoke-AzCostManagementQuery `
            -Scope      $scope `
            -Type       ActualCost `
            -Timeframe  Custom `
            -TimePeriodFrom $start `
            -TimePeriodTo   $end `
            -DatasetGranularity None `
            -DatasetAggregation @{
                totalCost = @{ Name = "Cost"; Function = "Sum" }
            }
    }

    $cost     = 0.0
    $currency = "USD"

    if ($result.Row.Count -gt 0) {
        $colNames = $result.Column.Name
        $row      = $result.Row[0]
        $costIdx  = $colNames.IndexOf("Cost")
        $currIdx  = $colNames.IndexOf("Currency")

        if ($costIdx -ge 0)  { $cost     = [double]$row[$costIdx] }
        if ($currIdx -ge 0)  { $currency = $row[$currIdx] }
    }

    $logger.Info("Subscription total: $cost $currency")
    return @{ TotalCostUSD = [Math]::Round($cost, 4); Currency = $currency }
}


function Get-CostByResourceGroup {
    <#
    .SYNOPSIS
        Returns daily costs grouped by ResourceGroup for the last N days.
    .PARAMETER SubscriptionId
        Azure Subscription ID.
    .PARAMETER Days
        Number of past days to query.
    .OUTPUTS
        Array of hashtables: [{ ResourceGroup, Cost, UsageDate, Currency }]
    #>
    param (
        [Parameter(Mandatory = $true)]  [string]$SubscriptionId,
        [Parameter(Mandatory = $false)] [int]$Days = 30
    )

    $logger = Get-Logger -Name "Get-CostByResourceGroup"
    $logger.Info("Querying cost by ResourceGroup for last $Days days...")

    $start = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddT00:00:00Z")
    $end   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT00:00:00Z")
    $scope = "/subscriptions/$SubscriptionId"

    $result = Invoke-WithRetry -ScriptBlock {
        Invoke-AzCostManagementQuery `
            -Scope      $scope `
            -Type       ActualCost `
            -Timeframe  Custom `
            -TimePeriodFrom $start `
            -TimePeriodTo   $end `
            -DatasetGranularity Daily `
            -DatasetAggregation @{
                totalCost = @{ Name = "Cost"; Function = "Sum" }
            } `
            -DatasetGrouping @(
                @{ Type = "Dimension"; Name = "ResourceGroup" }
            )
    }

    $rows     = @()
    $colNames = $result.Column.Name

    foreach ($row in $result.Row) {
        $record = @{}
        for ($i = 0; $i -lt $colNames.Count; $i++) {
            $record[$colNames[$i]] = $row[$i]
        }
        $rows += $record
    }

    $logger.Info("Retrieved $($rows.Count) ResourceGroup rows.")
    return $rows
}


function Get-CostByService {
    <#
    .SYNOPSIS
        Returns total costs grouped by ServiceName for the last N days.
    .PARAMETER SubscriptionId
        Azure Subscription ID.
    .PARAMETER Days
        Number of past days to query.
    .OUTPUTS
        Array of hashtables: [{ ServiceName, Cost, Currency }]
    #>
    param (
        [Parameter(Mandatory = $true)]  [string]$SubscriptionId,
        [Parameter(Mandatory = $false)] [int]$Days = 30
    )

    $logger = Get-Logger -Name "Get-CostByService"
    $logger.Info("Querying cost by ServiceName for last $Days days...")

    $start = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddT00:00:00Z")
    $end   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT00:00:00Z")
    $scope = "/subscriptions/$SubscriptionId"

    $result = Invoke-WithRetry -ScriptBlock {
        Invoke-AzCostManagementQuery `
            -Scope      $scope `
            -Type       ActualCost `
            -Timeframe  Custom `
            -TimePeriodFrom $start `
            -TimePeriodTo   $end `
            -DatasetGranularity None `
            -DatasetAggregation @{
                totalCost = @{ Name = "Cost"; Function = "Sum" }
            } `
            -DatasetGrouping @(
                @{ Type = "Dimension"; Name = "ServiceName" }
            )
    }

    $rows     = @()
    $colNames = $result.Column.Name

    foreach ($row in $result.Row) {
        $record = @{}
        for ($i = 0; $i -lt $colNames.Count; $i++) {
            $record[$colNames[$i]] = $row[$i]
        }
        $rows += $record
    }

    $logger.Info("Retrieved $($rows.Count) ServiceName rows.")
    return $rows
}
