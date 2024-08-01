$adkfoldername='adk'
$adkInstallPath = ".\$adkfoldername"
$peSourcePath = ".\pe"
$mountPath = "$peSourcePath\mount"
$isoOutputPath = "$peSourcePath\WinPE.iso"

# Set progress preference to silently continue
$ProgressPreference = 'SilentlyContinue'

# Define paths
$winpeMediaPath = "$peSourcePath\WinPE_amd64"
$isoRoot = "$winpeMediaPath"
$bootDir = "$isoRoot\boot"
$efiDir = "$isoRoot\efi"
$sourcesDir = "$isoRoot\sources"

# Define paths for WinPE files
$winpePath = "$adkInstallPath\Assessment and Deployment Kit\Windows Preinstallation Environment"
$winpeArch = "amd64"
$winpeArchPath = "$winpePath\$winpeArch"
$winpesourceWim = "$winpeArchPath\en-us\WinPE.wim"
$winpeWim="$peSourcePath\WinPE.wim"

# Define URLs
$adkPageUrl = "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install"
$explorerPlusPlusUrl = "https://download.explorerplusplus.com/dev/latest/explorerpp_x64.zip"
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

# Download paths for ADK and WinPE installers
$adkInstallerPath = ".\adksetup.exe"
$winpeInstallerPath = ".\adkwinpesetup.exe"

# Download the ADK installer
Invoke-WebRequest -Uri $latestAdkLink -OutFile $adkInstallerPath

# Download the WinPE add-on installer
Invoke-WebRequest -Uri $latestWinpeLink -OutFile $winpeInstallerPath

# Install Windows ADK silently
& $adkInstallerPath /quiet /norestart /installpath "$((Get-Item .).FullName)\$adkfoldername" | Out-Null

# Install Windows PE add-on silently
& $winpeInstallerPath /quiet /norestart /installpath "$((Get-Item .).FullName)\$adkfoldername" | Out-Null

# Clean up downloaded installers
Remove-Item -Path $adkInstallerPath, $winpeInstallerPath -Force

# Create the WinPE directory structure
New-Item -ItemType Directory -Path $mountPath, $winpeMediaPath, $isoRoot, $bootDir, $efiDir, $sourcesDir -Force
$latestAdkVersion.ToString() | Out-File -FilePath $adkVersionFile

# Copy the base WinPE files
& "$winpePath\copype.cmd" $winpeArch $peSourcePath

# Mount the WinPE image
Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue
Mount-WindowsImage -ImagePath $winpeWim -Index 1 -Path $mountPath

# Add PowerShell to the WinPE image
$packagesPath = "$winpeArchPath\WinPE_OCs"
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
$explorerPlusPlusZipPath = "$peSourcePath\ExplorerPlusPlus.zip"
$explorerPlusPlusExtractPath = "$peSourcePath\ExplorerPlusPlus"
$firefoxInstallerPath = "$mountPath\windows\system32\firefox_installer.exe"
$browserBatchPath = "$mountPath\windows\system32\browser.bat"

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
Copy-Item -Path $winpeWim -Destination "$sourcesDir\boot.wim" -Force

# Generate the bootable ISO using oscdimg
$oscdimgPath = "$adkInstallPath\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
$isoOutputPath = "$peSourcePath\WinPE_$($latestAdkVersion.ToString()).iso"
Start-Process -FilePath $oscdimgPath -ArgumentList "-b$isoRoot\etfsboot.com", "-u2", "-h", "-m", "-o", "-udfver102", "-lWinPE", $isoRoot, $isoOutputPath -Wait

Write-Output "Bootable ISO has been created at $isoOutputPath."
