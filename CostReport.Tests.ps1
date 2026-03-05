<#
.SYNOPSIS
    tests/CostReport.Tests.ps1
    Pester v5 unit tests for New-CostReport.ps1
    Runs without any Azure credentials.
#>

BeforeAll {
    . "$PSScriptRoot/../src/Helpers.ps1"
    . "$PSScriptRoot/../src/New-CostReport.ps1"

    # Shared test data
    $script:SampleTotal = @{ TotalCostUSD = 342.55; Currency = "USD" }

    $script:SampleByRG = @(
        @{ ResourceGroup = "rg-prod"; Cost = 210.0; Currency = "USD" }
        @{ ResourceGroup = "rg-dev";  Cost = 132.55; Currency = "USD" }
    )

    $script:SampleByService = @(
        @{ ServiceName = "Virtual Machines";            Cost = 180.0;  Currency = "USD" }
        @{ ServiceName = "Storage";                     Cost =  42.55; Currency = "USD" }
        @{ ServiceName = "App Service";                 Cost = 120.0;  Currency = "USD" }
    )

    $script:SampleAlerts = @(
        @{ Level = "WARNING"; Message = "Budget at 80%"; CurrentUSD = 342.55; ThresholdUSD = 500 }
    )
}

Describe "New-CostReport — File Output" {

    It "Creates the JSON report file" {
        $tmpDir = Join-Path $TestDrive "reports"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              $script:SampleAlerts `
            -Days                30 `
            -OutputDir           $tmpDir

        Test-Path $paths.json | Should -Be $true
    }

    It "Creates the CSV by service file" {
        $tmpDir = Join-Path $TestDrive "reports2"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              @() `
            -Days                7 `
            -OutputDir           $tmpDir

        Test-Path $paths.csv_service | Should -Be $true
    }

    It "Creates the CSV by resource group file" {
        $tmpDir = Join-Path $TestDrive "reports3"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              @() `
            -Days                14 `
            -OutputDir           $tmpDir

        Test-Path $paths.csv_rg | Should -Be $true
    }
}

Describe "New-CostReport — JSON Content" {

    It "JSON contains subscription_total" {
        $tmpDir = Join-Path $TestDrive "json_check"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              $script:SampleAlerts `
            -Days                30 `
            -OutputDir           $tmpDir

        $json = Get-Content $paths.json -Raw | ConvertFrom-Json
        $json.subscription_total.TotalCostUSD | Should -Be 342.55
    }

    It "JSON top_services are sorted by cost descending" {
        $tmpDir = Join-Path $TestDrive "sort_check"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              @() `
            -Days                30 `
            -OutputDir           $tmpDir

        $json   = Get-Content $paths.json -Raw | ConvertFrom-Json
        $costs  = $json.top_services | ForEach-Object { [double]$_.Cost }
        $sorted = $costs | Sort-Object -Descending

        $costs | Should -Be $sorted
    }

    It "JSON contains alerts array" {
        $tmpDir = Join-Path $TestDrive "alerts_check"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              $script:SampleAlerts `
            -Days                30 `
            -OutputDir           $tmpDir

        $json = Get-Content $paths.json -Raw | ConvertFrom-Json
        $json.alerts.Count | Should -Be 1
        $json.alerts[0].Level | Should -Be "WARNING"
    }

    It "JSON period_days matches the Days parameter" {
        $tmpDir = Join-Path $TestDrive "days_check"

        $paths = New-CostReport `
            -SubscriptionTotal   $script:SampleTotal `
            -CostByResourceGroup $script:SampleByRG `
            -CostByService       $script:SampleByService `
            -Alerts              @() `
            -Days                7 `
            -OutputDir           $tmpDir

        $json = Get-Content $paths.json -Raw | ConvertFrom-Json
        $json.period_days | Should -Be 7
    }
}
