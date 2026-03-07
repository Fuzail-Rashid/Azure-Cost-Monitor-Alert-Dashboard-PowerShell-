<#
.SYNOPSIS
    Invoke-AlertEngine.ps1 — Evaluates cost thresholds and dispatches
    alerts via SMTP email and/or Microsoft Teams Incoming Webhook.
#>

Set-StrictMode -Version Latest

function Invoke-ThresholdEvaluation {
    <#
    .SYNOPSIS
        Compares current spend to configured thresholds.
        Returns a list of triggered alert objects.
    .PARAMETER SubscriptionTotal
        Hashtable from Get-SubscriptionTotalCost: { TotalCostUSD, Currency }
    .PARAMETER CostByService
        Array of service cost rows from Get-CostByService.
    .PARAMETER Thresholds
        PSCustomObject from config: alert_thresholds block.
    .OUTPUTS
        Array of alert hashtables: [{ Level, Message, CurrentUSD, ThresholdUSD }]
    #>
    param (
        [Parameter(Mandatory = $true)] [hashtable]$SubscriptionTotal,
        [Parameter(Mandatory = $true)] [array]$CostByService,
        [Parameter(Mandatory = $true)] $Thresholds
    )

    $logger = Get-Logger -Name "Invoke-ThresholdEvaluation"
    $alerts = @()
    $total  = $SubscriptionTotal.TotalCostUSD

    # --- Subscription-level threshold ------------------------------------------
    $subLimit = $Thresholds.subscription_monthly_usd

    if ($subLimit -and $total -ge $subLimit) {
        $alerts += New-Alert `
            -Level     "CRITICAL" `
            -Message   "Subscription total `$$([Math]::Round($total,2)) has exceeded monthly budget of `$$subLimit" `
            -Current   $total `
            -Threshold $subLimit
    }
    elseif ($subLimit -and $total -ge ($subLimit * 0.80)) {
        $alerts += New-Alert `
            -Level     "WARNING" `
            -Message   "Subscription total `$$([Math]::Round($total,2)) has reached 80% of monthly budget (`$$subLimit)" `
            -Current   $total `
            -Threshold $subLimit
    }

    # --- Per-service thresholds ------------------------------------------------
    $serviceThresholds = $Thresholds.per_service_usd

    if ($serviceThresholds) {
        foreach ($row in $CostByService) {
            $serviceName = $row["ServiceName"]
            $serviceCost = [double]$row["Cost"]
            $limit       = $serviceThresholds.$serviceName

            if ($limit -and $serviceCost -ge $limit) {
                $alerts += New-Alert `
                    -Level     "WARNING" `
                    -Message   "Service '$serviceName' cost `$$([Math]::Round($serviceCost,2)) exceeded threshold of `$$limit" `
                    -Current   $serviceCost `
                    -Threshold $limit
            }
        }
    }

    $logger.Info("$($alerts.Count) alert(s) triggered.")
    return $alerts
}


function Send-Alerts {
    <#
    .SYNOPSIS
        Dispatches all triggered alerts via configured channels.
    .PARAMETER Alerts
        Array of alert hashtables from Invoke-ThresholdEvaluation.
    .PARAMETER Config
        Full config PSCustomObject.
    #>
    param (
        [Parameter(Mandatory = $true)] [array]$Alerts,
        [Parameter(Mandatory = $true)] $Config
    )

    $logger = Get-Logger -Name "Send-Alerts"

    if ($Alerts.Count -eq 0) {
        $logger.Info("No alerts to dispatch.")
        return
    }

    foreach ($alert in $Alerts) {
        $logger.Warning("[$($alert.Level)] $($alert.Message)")
    }

    if ($Config.email.enabled -eq $true) {
        Send-AlertEmail -Alerts $Alerts -EmailConfig $Config.email
    }

    if ($Config.teams_webhook_url) {
        Send-TeamsAlert -Alerts $Alerts -WebhookUrl $Config.teams_webhook_url
    }
}


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

function Send-AlertEmail {
    <#
    .SYNOPSIS
        Sends an HTML-formatted alert summary via SMTP.
    #>
    param (
        [Parameter(Mandatory = $true)] [array]$Alerts,
        [Parameter(Mandatory = $true)] $EmailConfig
    )

    $logger = Get-Logger -Name "Send-AlertEmail"

    $recipients = $EmailConfig.recipients
    if (-not $recipients -or $recipients.Count -eq 0) {
        $logger.Warning("Email enabled but no recipients configured.")
        return
    }

    $subject = "[Azure Cost Alert] $($Alerts.Count) threshold(s) breached"
    $body    = Build-EmailBody -Alerts $Alerts

    try {
        $smtpParams = @{
            SmtpServer  = $EmailConfig.smtp_host
            Port        = $EmailConfig.smtp_port ?? 587
            From        = $EmailConfig.sender
            To          = $recipients
            Subject     = $subject
            Body        = $body
            BodyAsHtml  = $true
            UseSsl      = $true
        }

        if ($EmailConfig.smtp_user) {
            $secPwd    = ConvertTo-SecureString $EmailConfig.smtp_password -AsPlainText -Force
            $smtpCreds = New-Object System.Management.Automation.PSCredential(
                $EmailConfig.smtp_user, $secPwd
            )
            $smtpParams["Credential"] = $smtpCreds
        }

        Send-MailMessage @smtpParams
        $logger.Info("Alert email sent to: $($recipients -join ', ')")
    }
    catch {
        $logger.Error("Failed to send alert email: $_")
    }
}


function Build-EmailBody {
    param ([array]$Alerts)

    $rows = ($Alerts | ForEach-Object {
        $color = if ($_.Level -eq "CRITICAL") { "#c0392b" } else { "#e67e22" }
        "<tr>
            <td style='padding:8px;color:$color'><b>$($_.Level)</b></td>
            <td style='padding:8px'>$($_.Message)</td>
        </tr>"
    }) -join "`n"

    return @"
<html><body>
<h2 style='font-family:Arial'>Azure Cost Monitor — Alert Summary</h2>
<table border='1' cellpadding='4' style='border-collapse:collapse;font-family:Arial'>
  <tr style='background:#2c3e50;color:white'>
    <th style='padding:8px'>Level</th>
    <th style='padding:8px'>Details</th>
  </tr>
  $rows
</table>
<p style='font-family:Arial;color:#7f8c8d'>Generated by azure-cost-monitor-ps</p>
</body></html>
"@
}


# ---------------------------------------------------------------------------
# Microsoft Teams
# ---------------------------------------------------------------------------

function Send-TeamsAlert {
    <#
    .SYNOPSIS
        Posts a MessageCard to a Microsoft Teams Incoming Webhook.
    #>
    param (
        [Parameter(Mandatory = $true)] [array]$Alerts,
        [Parameter(Mandatory = $true)] [string]$WebhookUrl
    )

    $logger = Get-Logger -Name "Send-TeamsAlert"

    $facts = $Alerts | ForEach-Object {
        @{ name = $_.Level; value = $_.Message }
    }

    $hasCritical = $Alerts | Where-Object { $_.Level -eq "CRITICAL" }
    $themeColor  = if ($hasCritical) { "FF0000" } else { "FFA500" }

    $payload = @{
        "@type"      = "MessageCard"
        "@context"   = "https://schema.org/extensions"
        "summary"    = "Azure Cost Alert"
        "themeColor" = $themeColor
        "title"      = "⚠️ Azure Cost Monitor — $($Alerts.Count) Alert(s)"
        "sections"   = @(@{ facts = $facts })
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
            -Uri         $WebhookUrl `
            -Method      POST `
            -ContentType "application/json" `
            -Body        $payload

        $logger.Info("Teams webhook response: $response")
    }
    catch {
        $logger.Error("Failed to post Teams webhook: $_")
    }
}


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

function New-Alert {
    param (
        [string]$Level,
        [string]$Message,
        [double]$Current,
        [double]$Threshold
    )
    return @{
        Level        = $Level
        Message      = $Message
        CurrentUSD   = [Math]::Round($Current,   4)
        ThresholdUSD = [Math]::Round($Threshold, 4)
    }
}
