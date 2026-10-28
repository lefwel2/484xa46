
# install_firefox.ps1
# Windows PowerShell 5.1+
# Downloads and silently installs official 64-bit Firefox.

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:ProgramData 'FleetDeckAutomation'
$logFile = Join-Path $logDir 'install.log'
$installer = Join-Path $env:TEMP 'FirefoxSetup.exe'
$url = 'https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    "[$(Get-Date -Format o)] $Message" |
        Out-File -FilePath $logFile -Append -Encoding utf8
}

try {
    Write-Log 'Firefox installation worker started.'

    # Retry until the internet is available.
    while ($true) {
        try {
            $null = Invoke-WebRequest `
                -Uri 'https://download.mozilla.org/' `
                -Method Head -UseBasicParsing -TimeoutSec 15
            break
        }
        catch {
            Write-Log 'Internet unavailable; retrying in 30 seconds.'
            Start-Sleep -Seconds 30
        }
    }

    # Download Firefox.
    Invoke-WebRequest -Uri $url -OutFile $installer `
        -UseBasicParsing -TimeoutSec 300

    if (!(Test-Path $installer) -or
        (Get-Item $installer).Length -lt 1MB) {
        throw 'Installer is missing or unexpectedly small.'
    }

    # Validate the Authenticode signature.
    $signature = Get-AuthenticodeSignature -FilePath $installer

    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch 'Mozilla') {
        throw 'Firefox installer signature validation failed.'
    }

    # Install silently.
    $process = Start-Process -FilePath $installer `
        -ArgumentList '-ms' -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Firefox installer exited with code $($process.ExitCode)."
    }

    Write-Log 'Firefox installation completed successfully.'
}
catch {
    Write-Log "INSTALLATION FAILED: $($_.Exception.Message)"
    exit 1
}
finally {
    Remove-Item -Path $installer -Force -ErrorAction SilentlyContinue
}
