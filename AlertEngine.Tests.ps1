<#
.SYNOPSIS
    tests/AlertEngine.Tests.ps1
    Pester v5 unit tests for Invoke-AlertEngine.ps1
    Runs without any Azure credentials.
#>

BeforeAll {
    # Dot-source the modules under test
    . "$PSScriptRoot/../src/Helpers.ps1"
    . "$PSScriptRoot/../src/Invoke-AlertEngine.ps1"

    # Shared test config
    $script:BaseThresholds = [PSCustomObject]@{
        subscription_monthly_usd = 1000
        per_service_usd          = [PSCustomObject]@{
            "Virtual Machines" = 300
            "Storage"          = 50
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-ThresholdEvaluation — subscription level
# ---------------------------------------------------------------------------
Describe "Invoke-ThresholdEvaluation — Subscription Level" {

    It "Returns no alerts when spend is below 80 percent" {
        $total  = @{ TotalCostUSD = 700.0; Currency = "USD" }
        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     @() `
                    -Thresholds        $script:BaseThresholds

        $alerts.Count | Should -Be 0
    }

    It "Returns a WARNING when spend is between 80 and 100 percent" {
        $total  = @{ TotalCostUSD = 850.0; Currency = "USD" }
        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     @() `
                    -Thresholds        $script:BaseThresholds

        $alerts.Count         | Should -Be 1
        $alerts[0].Level      | Should -Be "WARNING"
    }

    It "Returns CRITICAL when spend meets or exceeds threshold" {
        $total  = @{ TotalCostUSD = 1000.0; Currency = "USD" }
        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     @() `
                    -Thresholds        $script:BaseThresholds

        $alerts[0].Level | Should -Be "CRITICAL"
    }

    It "Returns CRITICAL when spend exceeds threshold" {
        $total  = @{ TotalCostUSD = 1200.0; Currency = "USD" }
        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     @() `
                    -Thresholds        $script:BaseThresholds

        $alerts[0].Level | Should -Be "CRITICAL"
    }
}

# ---------------------------------------------------------------------------
# Invoke-ThresholdEvaluation — per-service level
# ---------------------------------------------------------------------------
Describe "Invoke-ThresholdEvaluation — Per-Service Level" {

    It "Triggers a WARNING when service cost exceeds limit" {
        $total      = @{ TotalCostUSD = 100.0; Currency = "USD" }
        $byService  = @(@{ ServiceName = "Virtual Machines"; Cost = 350.0; Currency = "USD" })

        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     $byService `
                    -Thresholds        $script:BaseThresholds

        $alerts.Count    | Should -BeGreaterThan 0
        $alerts[0].Level | Should -Be "WARNING"
        $alerts[0].Message | Should -Match "Virtual Machines"
    }

    It "Returns no alert when service cost is below limit" {
        $total      = @{ TotalCostUSD = 100.0; Currency = "USD" }
        $byService  = @(@{ ServiceName = "Virtual Machines"; Cost = 200.0; Currency = "USD" })

        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     $byService `
                    -Thresholds        $script:BaseThresholds

        $alerts.Count | Should -Be 0
    }

    It "Does not alert on services with no configured threshold" {
        $total      = @{ TotalCostUSD = 100.0; Currency = "USD" }
        $byService  = @(@{ ServiceName = "Some Unknown Service"; Cost = 9999.0; Currency = "USD" })

        $alerts = Invoke-ThresholdEvaluation `
                    -SubscriptionTotal $total `
                    -CostByService     $byService `
                    -Thresholds        $script:BaseThresholds

        $alerts.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# New-Alert helper
# ---------------------------------------------------------------------------
Describe "New-Alert" {

    It "Returns a correctly structured alert hashtable" {
        $alert = New-Alert -Level "CRITICAL" -Message "Test msg" -Current 1100 -Threshold 1000

        $alert.Level        | Should -Be "CRITICAL"
        $alert.Message      | Should -Be "Test msg"
        $alert.CurrentUSD   | Should -Be 1100
        $alert.ThresholdUSD | Should -Be 1000
    }

    It "Rounds values to 4 decimal places" {
        $alert = New-Alert -Level "WARNING" -Message "x" -Current 123.456789 -Threshold 100.0

        $alert.CurrentUSD | Should -Be 123.4568
    }
}

# ---------------------------------------------------------------------------
# Send-Alerts — dispatch routing
# ---------------------------------------------------------------------------
Describe "Send-Alerts — Dispatch" {

    It "Logs info and returns early when alerts list is empty" {
        $config = [PSCustomObject]@{
            email              = [PSCustomObject]@{ enabled = $false }
            teams_webhook_url  = $null
        }

        # Should not throw
        { Send-Alerts -Alerts @() -Config $config } | Should -Not -Throw
    }
}
