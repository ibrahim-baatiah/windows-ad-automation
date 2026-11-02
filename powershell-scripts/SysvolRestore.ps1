$creds = @{
    name="LAB\azureadmin"
    Password= ConvertTo-SecureString "Password1234" -AsPlainText -Force ## Read-Host "Passowrd: " -AsSecureString
}
$psCred = New-Object PSCredential($creds.name, $creds.Password)
$session = New-PSSession -ComputerName '10.10.1.4' -Credential $psCred

$DCList=Invoke-Command -Session $session -ScriptBlock  {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Error $_.Exception.Message
    }
    
    $PDC=(Get-ADDomain).PDCEmulator
    $DCs=Get-ADDomainController -Filter * ## | Select-Object -ExpandProperty Name

    $DCList=New-Object -TypeName System.Collections.ArrayList
    foreach ($DC in $DCs) {
        [void]$DCList.Add(
            [PSCustomObject]@{
            Name = $DC.Name
            IPv4Address = $DC.IPv4Address
            IsPDC = $DC.HostName -eq $PDC
            SubscriptionDN = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,$($DC.ComputerObjectDN)"
            }
        )
    }
    # $DCList | Format-Table -AutoSize
    
    foreach ($DC in $DCList) {
        try {
            $result = Invoke-Command -ComputerName $DC.Name -Credential $using:psCred -ErrorAction Stop -ScriptBlock {
                Get-CimInstance -Namespace root\microsoftdfs -ClassName DfsrReplicatedFolderInfo `
                -Filter "ReplicatedFolderName='SYSVOL Share'" |
                Select-Object ReplicatedFolderName, State
            }
            $state = $result.State
        }
        catch {
            $state = "Unreachable"
            Write-Warning $_.Exception.Message
        }
        $DC |  Add-Member -MemberType NoteProperty -Name DfsrState -Value $state -Force
    }
    # $DCList | Format-Table -AutoSize

    foreach ($DC in $DCList) {
        $text = switch ($DC.DfsrState) {
            0       { 'Uninitialized' }
            1       { 'Initialized' }
            2       { 'InitialSync' }
            3       { 'AutoRecovery' }
            4       { 'Normal' }
            5       { 'Error' }
            default { 'Unreachable' }
        }
        $DC | Add-Member -MemberType NoteProperty -Name StateText -Value $text -Force
    }
    $DCList
}

$unhealthy = $DCList | Where-Object {$_.DfsrState -ne 4}
if (-not $unhealthy) {
    Write-Output "SYSVOL healthy, nothing to do"
    return $DCList
}
Write-Output "Unhealthy DCs:"
$unhealthy | Format-Table Name, IPv4Address, IsPDC, DfsrState, StateText -AutoSize