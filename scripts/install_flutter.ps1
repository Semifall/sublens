$url = "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.4-stable.zip"
$zipPath = "D:\flutter_windows.zip"
$destPath = "D:\"

Write-Host "1. Starting Flutter SDK download from mirror..." -ForegroundColor Green
Write-Host "URL: $url"
Write-Host "Saving to: $zipPath"

# Download the file
Invoke-WebRequest -Uri $url -OutFile $zipPath

Write-Host "2. Download complete. Extracting archive to $destPath..." -ForegroundColor Green
Expand-Archive -Path $zipPath -DestinationPath $destPath -Force

Write-Host "3. Cleanup temporary zip file..." -ForegroundColor Green
Remove-Item $zipPath

Write-Host "4. Configuring permanent User Environment Variables..." -ForegroundColor Green
[System.Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn", "User")
[System.Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://pub.flutter-io.cn", "User")

$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*D:\flutter\bin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", $userPath + ";D:\flutter\bin", "User")
    Write-Host "Added D:\flutter\bin to User PATH."
} else {
    Write-Host "D:\flutter\bin is already in User PATH."
}

# Set environment variables for the current running process session too
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:PATH += ";D:\flutter\bin"

Write-Host "5. Verifying installation..." -ForegroundColor Green
& flutter --version

Write-Host "Flutter SDK installation and configuration completed successfully!" -ForegroundColor Green
