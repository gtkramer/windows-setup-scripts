#Requires -Version 5.1
# Machine-wide settings that do not belong in the answer file and are not plain registry values:
# the computer name and time zone from common.ps1, and 8.3 short names (off for new files, with
# a one-time count of the existing ones). Registry values are in system\registry.psd1.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# --- Computer name (takes effect after a restart) ---
if ($HostName -notmatch '^(?!\d+$)[A-Za-z0-9-]{1,15}$') { Die "HostName '$HostName' must be 1-15 letters, digits or hyphens." }
$pendingName = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName'
if ($pendingName -ne $HostName) {
    Rename-Computer -NewName $HostName -Force -WarningAction SilentlyContinue
    Write-Info "Computer name set to $HostName (after the next restart)."
}

# --- Time zone ---
if ((Get-TimeZone).Id -ne $TimeZoneId) {
    Set-TimeZone -Id $TimeZoneId
    Write-Info "Time zone set to $TimeZoneId."
}

# --- No 8.3 short names for new files. Existing ones are never stripped: Windows keeps them
#     until the file or folder is deleted or replaced. The run that turns creation off counts
#     them once, with Windows' own scan, and reports the number. Later runs skip the scan. ---
$shortNamesWereOff = (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisable8dot3NameCreation') -eq 1
fsutil behavior set disable8dot3 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "fsutil could not turn off 8.3 name creation (exit $LASTEXITCODE)."
} elseif (-not $shortNamesWereOff) {
    Write-Info "Counting the short names already on $SystemDrive (this can take a few minutes)."
    $scanLog = Join-Path $env:TEMP 'kit-8dot3-scan.log'   # the scan always writes one; deleted below
    try {
        $scan = @(fsutil 8dot3name scan /s /l $scanLog "$SystemDrive\") -join "`n"
        if ($scan -match '8dot3 names found:\s*([\d.,]+)') {
            $found = [long]($Matches[1] -replace '\D')
            $keys  = if ($scan -match 'affected registry keys:\s*([\d.,]+)') { [long]($Matches[1] -replace '\D') } else { $null }
            if ($found -eq 0) {
                Write-Info "No file or folder on $SystemDrive has a short name."
            } else {
                $keyNote = if ($null -ne $keys) { ' ({0:N0} registry entries refer to one.)' -f $keys } else { '' }
                Write-Warn ("{0:N0} files and folders on $SystemDrive still have a short name from before this setting. They keep it until they are deleted or replaced; new ones get none. Nothing to do.$keyNote" -f $found)
            }
        } else {
            Write-Warn "The scan of $SystemDrive did not report a count of existing short names. It said:"
            $scan -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Info "  $_" }
        }
    } catch {
        Write-Warn "The scan of $SystemDrive for existing short names failed: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $scanLog -Force -ErrorAction SilentlyContinue
    }
}

Write-Info 'Machine settings applied (name, time zone, no new 8.3 names).'
