<#
.SYNOPSIS
    tests/Helpers.Tests.ps1
    Pester v5 unit tests for Helpers.ps1 utilities.
#>

BeforeAll {
    . "$PSScriptRoot/../src/Helpers.ps1"
}

Describe "Import-CostMonitorConfig" {

    It "Loads a valid JSON config file" {
        $tmpFile = Join-Path $TestDrive "test-settings.json"
        @{
            alert_thresholds = @{
                subscription_monthly_usd = 500
            }
            email = @{ enabled = $false }
        } | ConvertTo-Json | Set-Content $tmpFile

        $cfg = Import-CostMonitorConfig -Path $tmpFile
        $cfg.alert_thresholds.subscription_monthly_usd | Should -Be 500
    }

    It "Throws when config file does not exist" {
        { Import-CostMonitorConfig -Path "nonexistent/path/settings.json" } | Should -Throw
    }
}

Describe "Resolve-EnvVars" {

    It "Resolves a single environment variable placeholder" {
        $env:TEST_COST_VAR = "hello-from-env"

        $result = Resolve-EnvVars -Object '${TEST_COST_VAR}'
        $result | Should -Be "hello-from-env"

        Remove-Item Env:TEST_COST_VAR
    }

    It "Returns plain strings unchanged" {
        $result = Resolve-EnvVars -Object "just-a-string"
        $result | Should -Be "just-a-string"
    }

    It "Recursively resolves nested objects" {
        $env:NESTED_VAR = "nested-value"

        $obj = [PSCustomObject]@{
            outer = [PSCustomObject]@{
                inner = '${NESTED_VAR}'
            }
        }

        $resolved = Resolve-EnvVars -Object $obj
        $resolved.outer.inner | Should -Be "nested-value"

        Remove-Item Env:NESTED_VAR
    }
}

Describe "Invoke-WithRetry" {

    It "Returns the result on first successful attempt" {
        $result = Invoke-WithRetry -ScriptBlock { "success" }
        $result | Should -Be "success"
    }

    It "Retries and eventually succeeds" {
        $script:callCount = 0

        $result = Invoke-WithRetry -MaxAttempts 3 -DelaySeconds 0 -ScriptBlock {
            $script:callCount++
            if ($script:callCount -lt 3) { throw "transient error" }
            "recovered"
        }

        $result              | Should -Be "recovered"
        $script:callCount    | Should -Be 3
    }

    It "Throws after exhausting all attempts" {
        {
            Invoke-WithRetry -MaxAttempts 2 -DelaySeconds 0 -ScriptBlock {
                throw "always fails"
            }
        } | Should -Throw
    }
}

Describe "Get-Logger" {

    It "Returns a hashtable with Info, Warning, and Error keys" {
        $logger = Get-Logger -Name "test"
        $logger.Keys | Should -Contain "Info"
        $logger.Keys | Should -Contain "Warning"
        $logger.Keys | Should -Contain "Error"
    }

    It "Info method executes without error" {
        $logger = Get-Logger -Name "test"
        { & $logger.Info "test message" } | Should -Not -Throw
    }
}
