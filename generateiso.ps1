$adkInstallPath = ".\adk",
$peSourcePath = ".\pe",
$mountPath = "$peSourcePath\mount",
$isoOutputPath = "$peSourcePath\WinPE.iso"

# Set progress preference to silently continue
$ProgressPreference = 'SilentlyContinue'

# Define paths
$winpeMediaPath = "$peSourcePath\WinPE_amd64"
$isoRoot = ".\ISO"
$bootDir = "$isoRoot\boot"
$efiDir = "$isoRoot\efi"
$sourcesDir = "$isoRoot\sources"

# Define URLs
$adkPageUrl = "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install"
$explorerPlusPlusUrl = "https://github.com/derceg/explorerplusplus/releases/latest/download/Explorer++.zip"
$firefoxInstallerUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"

# Function to extract version number from a string
function Get-VersionNumber {
    param (
        [string]$inputString
    )
    if ($inputString -match '(\d+\.\d+\.\d+\.\d+)') {
        return [version]$matches[1]
    }
    return [version]'0.0.0.0'
}

# Download and parse ADK installation page
$pageContent = Invoke-WebRequest -Uri $adkPageUrl -UseBasicParsing

# Initialize variables to store the latest links
$latestAdkLink = ""
$latestAdkVersion = [version]'0.0.0.0'
$latestWinpeLink = ""
$latestWinpeVersion = [version]'0.0.0.0'

# Find the links and version numbers
foreach ($link in $pageContent.Links) {
    if ($link.outerhtml -match "ADK \d" -and $link.outerhtml -notmatch "PE add-on for the( Windows)? ADK") {
        $version = Get-VersionNumber -inputString $link.outerhtml
        if ($version -gt $latestAdkVersion) {
            $latestAdkVersion = $version
            $latestAdkLink = $link.href
        }
    } elseif ($link.outerhtml -match "PE add-on for the( Windows)? ADK") {
        $version = Get-VersionNumber -inputString $link.outerhtml
        if ($version -gt $latestWinpeVersion) {
            $latestWinpeVersion = $version
            $latestWinpeLink = $link.href
        }
    }
}

# Output the ADK version to a file
$adkVersionFile = "$peSourcePath\adk_version.txt"
$latestAdkVersion.ToString() | Out-File -FilePath $adkVersionFile

# Download paths for ADK and WinPE installers
$adkInstallerPath = "$env:TEMP\adksetup.exe"
$winpeInstallerPath = "$env:TEMP\adkwinpesetup.exe"

# Download the ADK installer
Invoke-WebRequest -Uri $latestAdkLink -OutFile $adkInstallerPath

# Download the WinPE add-on installer
Invoke-WebRequest -Uri $latestWinpeLink -OutFile $winpeInstallerPath

# Install Windows ADK silently
Start-Process -FilePath $adkInstallerPath -ArgumentList "/quiet", "/norestart", "/installpath", $adkInstallPath -Wait

# Install Windows PE add-on silently
Start-Process -FilePath $winpeInstallerPath -ArgumentList "/quiet", "/norestart", "/installpath", $adkInstallPath -Wait

# Clean up downloaded installers
Remove-Item -Path $adkInstallerPath, $winpeInstallerPath -Force

# Define paths for WinPE files
$winpePath = "$adkInstallPath\Assessment and Deployment Kit\Windows Preinstallation Environment"
$winpeArch = "amd64"
$winpeArchPath = "$winpePath\$winpeArch"
$winpeWim = "$winpeArchPath\WinPE.wim"

# Create the WinPE directory structure
New-Item -ItemType Directory -Path $mountPath, $winpeMediaPath, $isoRoot, $bootDir, $efiDir, $sourcesDir -Force

# Copy the base WinPE files
Copy-Item -Path "$winpeArchPath\Media\*" -Destination $winpeMediaPath -Recurse -Force

# Mount the WinPE image
Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Ignore
Mount-WindowsImage -ImagePath $winpeWim -Index 1 -MountPath $mountPath

# Add PowerShell to the WinPE image
$packagesPath = "$adkInstallPath\Assessment and Deployment Kit\Windows Preinstallation Environment\Packages"
$winpeOptionalPackages = @(
    "$packagesPath\WinPE-WMI.cab",
    "$packagesPath\WinPE-NetFX.cab",
    "$packagesPath\WinPE-Scripting.cab",
    "$packagesPath\WinPE-PowerShell.cab"
)

foreach ($package in $winpeOptionalPackages) {
    Add-WindowsPackage -Path $mountPath -PackagePath $package
}

Write-Output "PowerShell package has been added to the new Windows PE image."

# Download paths for Explorer++ and Firefox installer
$explorerPlusPlusZipPath = "$env:TEMP\ExplorerPlusPlus.zip"
$explorerPlusPlusExtractPath = "$env:TEMP\ExplorerPlusPlus"
$firefoxInstallerPath = "$mountPath\windows\system32\firefox_installer.exe"
$browserBatchPath = "$mountPath\windows\system32\browser.bat"

# Create necessary directories
New-Item -ItemType Directory -Path $explorerPlusPlusExtractPath -Force

# Download the latest Explorer++ zip file
Invoke-WebRequest -Uri $explorerPlusPlusUrl -OutFile $explorerPlusPlusZipPath

# Extract the zip file to the temporary extraction path
Expand-Archive -Path $explorerPlusPlusZipPath -DestinationPath $explorerPlusPlusExtractPath -Force

# Copy Explorer++ executable to the mounted Windows PE image's system32 directory
Copy-Item -Path "$explorerPlusPlusExtractPath\Explorer++.exe" -Destination "$mountPath\windows\system32" -Force

# Clean up downloaded and extracted files
Remove-Item -Path $explorerPlusPlusZipPath, $explorerPlusPlusExtractPath -Recurse -Force

Write-Output "Explorer++ has been downloaded and extracted to $mountPath\windows\system32."

# Download the latest Firefox web installer
Invoke-WebRequest -Uri $firefoxInstallerUrl -OutFile $firefoxInstallerPath

# Create the batch file to run the Firefox installer silently
$browserBatchContent = "@echo off`n$firefoxInstallerPath /S"
Set-Content -Path $browserBatchPath -Value $browserBatchContent -Force

Write-Output "Firefox web installer has been downloaded and browser.bat has been created in $mountPath\windows\system32."

# Commit the changes and unmount the image
Dismount-WindowsImage -Path $mountPath -Save

# Copy the updated WinPE.wim to the media folder
Copy-Item -Path "$winpeArchPath\WinPE.wim" -Destination "$winpeMediaPath\sources\boot.wim" -Force

# Copy the customized WinPE.wim to the sources directory
Copy-Item -Path "$winpeMediaPath\sources\boot.wim" -Destination "$sourcesDir\boot.wim" -Force

# Copy boot files from the ADK installation
Copy-Item -Path "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\boot\boot.sdi" -Destination $bootDir -Force
Copy-Item -Path "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\boot\etfsboot.com" -Destination $isoRoot -Force

# Copy EFI files from the ADK installation
Copy-Item -Path "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\efi\microsoft\boot" -Destination $efiDir -Recurse -Force

# Copy additional boot files
Copy-Item -Path "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\boot\bootfix.bin" -Destination $bootDir -Force

# Generate the bootable ISO using oscdimg
$oscdimgPath = "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
$isoOutputPath = "$peSourcePath\WinPE_$($latestAdkVersion.ToString()).iso"
Start-Process -FilePath $oscdimgPath -ArgumentList "-b$isoRoot\etfsboot.com", "-u2", "-h", "-m", "-o", "-udfver102", "-lWinPE", $isoRoot, $isoOutputPath -Wait

Write-Output "Bootable ISO has been created at $isoOutputPath."
