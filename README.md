# 💰 Azure Cost Monitor & Alert Dashboard (PowerShell)

> A production-grade **PowerShell** tool that queries **Azure Cost Management** via the `Az.CostManagement` module, aggregates spend by resource group and service, fires threshold-based alerts via **Email** and **Microsoft Teams**, and writes structured **JSON + CSV** reports.

[![CI](https://github.com/YOUR_USERNAME/azure-cost-monitor-ps/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_USERNAME/azure-cost-monitor-ps/actions)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell)](https://learn.microsoft.com/en-us/powershell/)
[![Az Module](https://img.shields.io/badge/Az.CostManagement-latest-0078D4?logo=microsoft-azure)](https://learn.microsoft.com/en-us/powershell/module/az.costmanagement/)
[![Pester](https://img.shields.io/badge/tested%20with-Pester%205-brightgreen)](https://pester.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Authentication](#authentication)
- [Usage](#usage)
- [Sample Output](#sample-output)
- [Running Tests](#running-tests)
- [CI/CD](#cicd)
- [Real-World Use Cases](#real-world-use-cases)
- [License](#license)

---

## Overview

Cloud cost overruns are one of the most common surprises in production Azure environments. This tool gives DevOps and cloud engineering teams **automated, scriptable visibility** into Azure spending — built entirely in **PowerShell**, the native language of Azure automation.

Designed to mirror real enterprise patterns:
- Authenticates via **Service Principal** (env vars) or **Managed Identity** (Azure Automation / VMs)
- Queries the **Azure Cost Management API** using the official `Az.CostManagement` module
- Evaluates configurable **budget thresholds** at subscription and per-service level
- Dispatches **HTML email and Teams card** alerts when limits are breached
- Outputs **JSON and CSV reports** for Power BI, Excel, or archival pipelines
- Ships with a **Pester v5** test suite — all tests run without Azure credentials

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   azure-cost-monitor-ps                          │
│                                                                  │
│  main.ps1  ──▶  Get-AzureCosts.ps1  ──▶  Az.CostManagement     │
│                       │                   (Azure Cost Mgmt API) │
│                       ▼                                          │
│           Invoke-AlertEngine.ps1  ──▶  Send-MailMessage (SMTP)  │
│                       │           ──▶  Invoke-RestMethod (Teams) │
│                       ▼                                          │
│           New-CostReport.ps1     ──▶  reports/*.json            │
│                                  ──▶  reports/*.csv             │
│                                  ──▶  Console summary table     │
└─────────────────────────────────────────────────────────────────┘

Azure Services Used:
  ┌──────────────────────────────┐
  │  Azure Cost Management API   │  ← Queried via Az.CostManagement
  │  Azure Active Directory      │  ← Service Principal via Az.Accounts
  └──────────────────────────────┘
```

---

## Features

| Feature | Description |
|---|---|
| 📊 **Cost aggregation** | Breaks down spend by Resource Group (daily) and by Service (total) |
| 🚨 **Threshold alerts** | Configurable per-subscription (WARNING at 80%, CRITICAL at 100%) and per-service limits |
| 📧 **Email notifications** | HTML-formatted alert emails via `Send-MailMessage` / Office 365 SMTP |
| 💬 **Teams alerts** | `MessageCard` payloads to Teams Incoming Webhooks via `Invoke-RestMethod` |
| 📁 **JSON reports** | Timestamped machine-readable output for automation pipelines |
| 📈 **CSV export** | `Export-Csv` output ready for Excel / Power BI |
| 🔄 **Retry logic** | `Invoke-WithRetry` — exponential back-off for all Azure API calls |
| 🔐 **Secret management** | `${ENV_VAR}` placeholders resolved at runtime — no secrets in config files |
| ✅ **Pester tests** | 20+ unit tests across 3 test files — no Azure credentials required |
| 🤖 **CI pipeline** | GitHub Actions runs Pester on PowerShell 7.2 and 7.4 on every push |

---

## Project Structure

```
azure-cost-monitor-ps/
├── main.ps1                            # CLI entry point
├── src/
│   ├── Helpers.ps1                     # Logger, config loader, retry wrapper
│   ├── Get-AzureCosts.ps1             # Az.CostManagement API queries
│   ├── Invoke-AlertEngine.ps1         # Threshold evaluation + notifications
│   └── New-CostReport.ps1             # JSON / CSV report writer + console summary
├── config/
│   └── settings.json.template          # Config template (copy → settings.json)
├── tests/
│   ├── Helpers.Tests.ps1              # Unit tests for utilities
│   ├── AlertEngine.Tests.ps1          # Unit tests for alert logic
│   └── CostReport.Tests.ps1           # Unit tests for report output
├── .github/
│   └── workflows/
│       └── ci.yml                      # GitHub Actions CI (Pester)
├── .gitignore
└── README.md
```

---

## Prerequisites

- **PowerShell 7.2+** (cross-platform: Windows, Linux, macOS)
- **Az PowerShell modules:**
  ```powershell
  Install-Module -Name Az.Accounts        -Scope CurrentUser -Force
  Install-Module -Name Az.CostManagement  -Scope CurrentUser -Force
  ```
- Azure subscription with **Cost Management Reader** role assigned to your identity
- (Optional) SMTP credentials for email alerts
- (Optional) Microsoft Teams Incoming Webhook URL

---

## Installation

```powershell
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/azure-cost-monitor-ps.git
cd azure-cost-monitor-ps

# 2. Install required Az modules
Install-Module Az.Accounts, Az.CostManagement -Scope CurrentUser -Force

# 3. Copy and fill in config
Copy-Item config/settings.json.template config/settings.json
```

---

## Configuration

Edit `config/settings.json`:

```json
{
  "alert_thresholds": {
    "subscription_monthly_usd": 500,
    "per_service_usd": {
      "Virtual Machines": 200,
      "Storage": 50
    }
  },
  "email": {
    "enabled": true,
    "sender": "alerts@yourdomain.com",
    "recipients": ["devops@yourdomain.com"],
    "smtp_host": "smtp.office365.com",
    "smtp_port": 587,
    "smtp_user": "${SMTP_USER}",
    "smtp_password": "${SMTP_PASSWORD}"
  },
  "teams_webhook_url": "${TEAMS_WEBHOOK_URL}"
}
```

> Values like `${SMTP_PASSWORD}` are resolved from **environment variables at runtime** — never commit secrets.

---

## Authentication

Uses `Connect-AzAccount` under the hood. Three supported methods in priority order:

**1. Service Principal (recommended for production):**
```powershell
$env:AZURE_TENANT_ID     = "<tenant-id>"
$env:AZURE_CLIENT_ID     = "<client-id>"
$env:AZURE_CLIENT_SECRET = "<client-secret>"
```

**2. Managed Identity** — runs automatically when deployed on an Azure VM or Azure Automation Runbook.

**3. Interactive** — falls back to `az login` / browser prompt for local development.

**Create a Service Principal with the required role:**
```bash
az ad sp create-for-rbac \
  --name "sp-cost-monitor" \
  --role "Cost Management Reader" \
  --scopes /subscriptions/<SUBSCRIPTION_ID>
```

---

## Usage

```powershell
# Basic run — last 30 days (default)
.\main.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Last 7 days
.\main.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Days 7

# Custom config and output directory
.\main.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -Days           14 `
  -ConfigPath     "config/settings.json" `
  -OutputDir      "C:\reports\azure-costs"
```

**Schedule with Windows Task Scheduler or Linux cron:**
```bash
# Linux cron — run daily at 08:00
0 8 * * * pwsh /opt/azure-cost-monitor-ps/main.ps1 \
  -SubscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  >> /var/log/cost-monitor.log 2>&1
```

**Azure Automation Runbook:**  
The `main.ps1` script runs unmodified as a PowerShell Runbook. Set the subscription ID as a Runbook parameter and inject SP credentials as Automation Variables.

---

## Sample Output

**Console summary:**
```
==============================================================
  AZURE COST MONITOR — SUMMARY REPORT
  Period  : Last 30 days
  Run at  : 2024-11-12 08:00:14 UTC
==============================================================
  Subscription total : $1,243.8700 USD

  Top Services by Cost:
    Virtual Machines                       $   612.0000
    Azure Kubernetes Service               $   289.4200
    Storage                                $    98.1500
    SQL Database                           $    75.5600
    App Service                            $    48.6700

  ⚠  2 ALERT(S) TRIGGERED:
    [CRITICAL] Subscription total $1243.87 has exceeded monthly budget of $1000
    [WARNING]  Service 'Virtual Machines' cost $612.00 exceeded threshold of $500
==============================================================
```

**JSON report snippet (`reports/cost_report_20241112_080014.json`):**
```json
{
  "generated_at": "2024-11-12T08:00:14+00:00",
  "period_days":  30,
  "subscription_total": {
    "TotalCostUSD": 1243.87,
    "Currency": "USD"
  },
  "top_services": [
    { "ServiceName": "Virtual Machines",            "Cost": 612.0  },
    { "ServiceName": "Azure Kubernetes Service",    "Cost": 289.42 }
  ],
  "alerts": [
    {
      "Level":        "CRITICAL",
      "Message":      "Subscription total $1243.87 has exceeded monthly budget of $1000",
      "CurrentUSD":   1243.87,
      "ThresholdUSD": 1000.0
    }
  ]
}
```

---

## Running Tests

```powershell
# Install Pester v5
Install-Module Pester -MinimumVersion 5.5.0 -Force -Scope CurrentUser

# Run all tests
Invoke-Pester ./tests -Output Detailed

# Run with code coverage
$cfg = New-PesterConfiguration
$cfg.Run.Path                  = "./tests"
$cfg.CodeCoverage.Enabled      = $true
$cfg.CodeCoverage.Path         = "./src/*.ps1"
Invoke-Pester -Configuration $cfg
```

All tests run **without Azure credentials** — Az module calls are never invoked by the unit test suite.

---

## CI/CD

GitHub Actions runs the full Pester suite on **PowerShell 7.2 and 7.4** on every push and pull request.  
See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

---

## Real-World Use Cases

| Scenario | How this project maps to it |
|---|---|
| **Azure Automation Runbook** | `main.ps1` runs as-is on a scheduled Runbook; SP creds injected as Automation Variables |
| **FinOps cost governance** | Automated daily/weekly spend reporting without portal access |
| **Linux DevOps agent** | Scheduled via cron on a Linux jump-box running PowerShell 7 |
| **Teams ChatOps** | Threshold alerts delivered directly to DevOps Teams channel |
| **Power BI pipeline** | CSV output feeds nightly into a Power BI dataset for trend dashboards |

---

## License

MIT — see [LICENSE](LICENSE) for details.
