﻿<#
    MIT License

    Copyright (c) Microsoft Corporation.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE
#>

# Version 21.07.22.0947

# Modified by Frank Zoechling to support German OS (see line 72/73)

[CmdletBinding(DefaultParameterSetName = "TestAMSI", HelpUri = "https://aka.ms/css-exchange")]
param(
    [Parameter(ParameterSetName = 'TestAMSI', Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ExchangeServerFQDN,
    [Parameter(ParameterSetName = 'CheckAMSIProviders', Mandatory = $false)]
    [switch]$CheckAMSIProviders,
    [Parameter(ParameterSetName = 'EnableAMSI', Mandatory = $false)]
    [switch]$EnableAMSI,
    [Parameter(ParameterSetName = 'DisableAMSI', Mandatory = $false)]
    [switch]$DisableAMSI,
    [Parameter(ParameterSetName = 'RestartIIS', Mandatory = $false)]
    [switch]$RestartIIS
)

Function Confirm-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent() )
    if ($currentPrincipal.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator )) {
        return $true
    } else {
        return $false
    }
}

function Test-AMSI {
    $msgNewLine = "`n"
    $currentForegroundColor = $host.ui.RawUI.ForegroundColor
    if (-not (Confirm-Administrator)) {
        Write-Output $msgNewLine
        Write-Warning "This script needs to be executed in elevated mode. Start the Exchange Management Shell as an Administrator and try again."
        $Error.Clear()
        Start-Sleep -Seconds 2
        exit
    }
    $datetime = Get-Date
    $installpath = (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ExchangeServer\v15\Setup -ErrorAction SilentlyContinue).MsiInstallPath
    if ($ExchangeServerFQDN) {
        try {
            $CookieContainer = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $Cookie = New-Object System.Net.Cookie("X-BEResource", "a]@$($ExchangeServerFQDN):444/ecp/proxyLogon.ecp#~1941997017", "/", "$ExchangeServerFQDN")
            $CookieContainer.Cookies.Add($Cookie)
            Invoke-WebRequest https://$ExchangeServerFQDN/ecp/x.js -Method POST -Headers @{"Host" = "$ExchangeServerFQDN" } -WebSession $CookieContainer
        } catch [System.Net.WebException] {
			#If ($_.Exception.Message -notlike "*The remote server returned an error: (400) Bad Request*") {    # commented out and iserted next line to support German OS
            If ($_.Exception.Message -notlike "*Der Remoteserver hat einen Fehler zurückgegeben: (400) Ungültige Anforderung.*") {
                $Message = ($_.Exception.Message).ToString().Trim()
                Write-Output $msgNewLine
                Write-Error $Message
                $host.ui.RawUI.ForegroundColor = "Yellow"
                Write-Output "If you are using Microsoft Defender then AMSI may be disabled or you are using a AntiVirus Product that may not be AMSI capable (Please Check with your AntiVirus Provider for Exchange AMSI Support)"
                $host.ui.RawUI.ForegroundColor = $currentForegroundColor
                Write-Output $msgNewLine
            } else {
                Write-Output $msgNewLine
                $host.ui.RawUI.ForegroundColor = "Green"
                Write-Output "We sent an test request to the ECP Virtual Directory of the server requested"
                $host.ui.RawUI.ForegroundColor = "Red"
                Write-Output "The remote server returned an error: (400) Bad Request"
                $host.ui.RawUI.ForegroundColor = "Green"
                Write-Output "---------------------------------------------------------------------------------------------------------------"
                $host.ui.RawUI.ForegroundColor = "Yellow"
                Write-Output "This may be indicative of a potential block from AMSI"
                $host.ui.RawUI.ForegroundColor = "Green"
                $msgCheckLogs = "Check your log files located in " + $installpath + "Logging\HttpRequestFiltering\"
                Write-Output $msgCheckLogs
                $msgDetectedTimeStamp = "for a Detected result around " + $datetime.ToUniversalTime()
                Write-Output $msgDetectedTimeStamp
                $host.ui.RawUI.ForegroundColor = $currentForegroundColor
                Write-Output $msgNewLine
            }
        } catch {
            Write-Error -Message $_.Exception.Message
        }
        return
    }
    if ($CheckAMSIProviders) {
        $AMSI = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers' -Recurse
        $AMSI -match '[0-9A-Fa-f\-]{36}' | Out-Null
        $Matches.Values | ForEach-Object { Get-ChildItem "HKLM:\SOFTWARE\Classes\CLSID\{$_}" | Format-Table -AutoSize }
    }
    if ($EnableAMSI) {
        Remove-SettingOverride -Identity DisablingAMSIScan -Confirm:$false
        Get-ExchangeDiagnosticInfo -Process Microsoft.Exchange.Directory.TopologyService -Component VariantConfiguration -Argument Refresh
        Write-Warning "Remember to restart IIS for this to take affect. You can accomplish this by running .\Test-AMSI.ps1 -RestartIIS"
        return
    }
    if ($DisableAMSI) {
        New-SettingOverride -Name DisablingAMSIScan -Component Cafe -Section HttpRequestFiltering -Parameters ("Enabled=False") -Reason "Disabled via CSS-Exchange Script"
        Get-ExchangeDiagnosticInfo -Process Microsoft.Exchange.Directory.TopologyService -Component VariantConfiguration -Argument Refresh
        Write-Warning "Remember to restart IIS for this to take affect. You can accomplish this by running .\Test-AMSI.ps1 -RestartIIS"
        return
    }
    if ($RestartIIS) {
        Restart-Service -Name W3SVC, WAS -Force
        return
    }
}

Test-AMSI
