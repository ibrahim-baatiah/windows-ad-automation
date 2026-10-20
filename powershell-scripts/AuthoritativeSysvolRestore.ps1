#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Authoritative SYSVOL restore (DFSR) across all domain controllers.
    The PDC Emulator is used as the authoritative DC.

.NOTES
    Run as Domain Admin from a domain-joined machine with RSAT AD tools.
    Remote commands go over WinRM (Invoke-Command).
#>

[CmdletBinding()]
param(
    [int]$EventTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- helpers
function Write-Step($Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

function Get-SubscriptionDN($DC) {
    "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,$($DC.ComputerObjectDN)"
}

function Set-Subscription($DC, [hashtable]$Values) {
    Set-ADObject -Identity (Get-SubscriptionDN $DC) -Server $PDC -Replace $Values
    Write-Host "  $($DC.Name): $(($Values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
}

function Sync-AD {
    Write-Host "  Forcing AD replication from $PDC ..."
    repadmin /syncall $PDC /AdeP | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "repadmin /syncall failed (exit $LASTEXITCODE)" }
}

# Confirms every DC sees the expected msDFSR-Enabled value for every subscription object
function Confirm-Replicated([hashtable]$ExpectedEnabled, [int]$Retries = 10) {
    for ($i = 1; $i -le $Retries; $i++) {
        $bad = foreach ($obj in $DCs) {
            foreach ($target in $DCs) {
                $v = (Get-ADObject (Get-SubscriptionDN $obj) -Server $target.HostName -Properties msDFSR-Enabled).'msDFSR-Enabled'
                if ($v -ne $ExpectedEnabled[$obj.HostName]) { "$($obj.Name) on $($target.Name)" }
            }
        }
        if (-not $bad) { Write-Host "  Replication validated on all DCs." -ForegroundColor Green; return }
        Write-Host "  Not yet replicated ($($bad -join '; ')). Retry $i/$Retries ..."
        Start-Sleep -Seconds 5
        Sync-AD
    }
    throw "AD changes did not replicate to all DCs."
}

function Invoke-PollAD([string[]]$ComputerName) {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $r = Invoke-CimMethod -Namespace root\microsoftdfs -ClassName DfsrConfig -MethodName PollDsNow
        if ($r.ReturnValue -ne 0) { throw "PollDsNow failed on $env:COMPUTERNAME ($($r.ReturnValue))" }
    }
    Write-Host "  PollAD triggered on: $($ComputerName -join ', ')"
}

# Waits until each computer logs one of the given DFSR event IDs after $Since
function Wait-DfsrEvent([string[]]$ComputerName, [int[]]$Id, [datetime]$Since) {
    $deadline = (Get-Date).AddSeconds($EventTimeoutSec)
    $pending  = [System.Collections.Generic.List[string]]::new([string[]]$ComputerName)

    while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline) {
        foreach ($c in @($pending)) {
            $ev = Invoke-Command -ComputerName $c -ScriptBlock {
                Get-WinEvent -FilterHashtable @{ LogName = 'DFS Replication'; Id = $using:Id; StartTime = $using:Since } `
                    -MaxEvents 1 -ErrorAction SilentlyContinue
            }
            if ($ev) {
                Write-Host "  $c : Event $($ev.Id) at $($ev.TimeCreated)" -ForegroundColor Green
                [void]$pending.Remove($c)
            }
        }
        if ($pending.Count) { Start-Sleep -Seconds 5 }
    }
    if ($pending.Count) { throw "Timed out waiting for event(s) $($Id -join '/') on: $($pending -join ', ')" }
}

# ---------------------------------------------------------------- discovery
$PDC    = (Get-ADDomain).PDCEmulator
$DCs    = @(Get-ADDomainController -Filter *)
$PdcObj = $DCs | Where-Object HostName -eq $PDC
$Others = @($DCs | Where-Object HostName -ne $PDC)

Write-Host "Authoritative DC (PDC): $PDC"
Write-Host "Non-authoritative DCs : $(($Others.HostName) -join ', ')"
if ((Read-Host "`nProceed with authoritative SYSVOL restore? (yes/no)") -ne 'yes') { return }

# ---------------------------------------------------------------- 1. stop DFSR everywhere
Write-Step "1. Set DFSR to Manual and stop it on all DCs"
Invoke-Command -ComputerName $DCs.HostName -ScriptBlock {
    Set-Service DFSR -StartupType Manual
    Stop-Service DFSR -Force
}

# ---------------------------------------------------------------- 2. disable subscriptions
Write-Step "2. Disable SYSVOL subscriptions (PDC authoritative)"
Set-Subscription $PdcObj @{ 'msDFSR-Enabled' = $false; 'msDFSR-Options' = 1 }
foreach ($dc in $Others) { Set-Subscription $dc @{ 'msDFSR-Enabled' = $false } }

# ---------------------------------------------------------------- 3. replicate + validate
Write-Step "3. Force AD replication and validate"
Sync-AD
$expected = @{}; $DCs | ForEach-Object { $expected[$_.HostName] = $false }
Confirm-Replicated $expected

# ---------------------------------------------------------------- 4. start DFSR on PDC
Write-Step "4. Start DFSR on the PDC (expect event 4114)"
$t = (Get-Date).AddSeconds(-10)
Invoke-Command -ComputerName $PDC -ScriptBlock { Start-Service DFSR }
Wait-DfsrEvent $PDC 4114 $t

# ---------------------------------------------------------------- 5. enable on PDC
Write-Step "5. Enable SYSVOL subscription on the PDC (expect event 4602)"
Set-Subscription $PdcObj @{ 'msDFSR-Enabled' = $true }
Sync-AD
$t = (Get-Date).AddSeconds(-10)
Invoke-PollAD $PDC
Wait-DfsrEvent $PDC 4602 $t

# ---------------------------------------------------------------- 6. start DFSR on others
if ($Others) {
    Write-Step "6. Start DFSR on non-authoritative DCs (expect event 4114)"
    $t = (Get-Date).AddSeconds(-10)
    Invoke-Command -ComputerName $Others.HostName -ScriptBlock { Start-Service DFSR }
    Wait-DfsrEvent $Others.HostName 4114 $t

# ---------------------------------------------------------------- 7. enable on others
    Write-Step "7. Enable SYSVOL subscription on non-authoritative DCs (expect events 4614 and 4604)"
    foreach ($dc in $Others) { Set-Subscription $dc @{ 'msDFSR-Enabled' = $true } }
    Sync-AD
    $DCs | ForEach-Object { $expected[$_.HostName] = $true }
    Confirm-Replicated $expected
    $t = (Get-Date).AddSeconds(-10)
    Invoke-PollAD $Others.HostName
    Wait-DfsrEvent $Others.HostName 4614 $t
    Wait-DfsrEvent $Others.HostName 4604 $t
}

# ---------------------------------------------------------------- 8. restore startup type
Write-Step "8. Set DFSR back to Automatic on all DCs"
Invoke-Command -ComputerName $DCs.HostName -ScriptBlock { Set-Service DFSR -StartupType Automatic }

# ---------------------------------------------------------------- 9. health check
Write-Step "9. SYSVOL replication state (4 = Normal)"
$states = Invoke-Command -ComputerName $DCs.HostName -ScriptBlock {
    Get-CimInstance -Namespace root\microsoftdfs -ClassName DfsrReplicatedFolderInfo `
        -Filter "ReplicatedFolderName='SYSVOL share'"
} | Select-Object PSComputerName, ReplicatedFolderName, State

$states | Format-Table -AutoSize
if ($states.State | Where-Object { $_ -ne 4 }) {
    Write-Warning "Not all DCs are in state 4 yet. Re-check in a few minutes."
} else {
    Write-Host "Authoritative SYSVOL restore completed successfully." -ForegroundColor Green
}