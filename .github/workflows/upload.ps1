#Requires -Version 7

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$RefreshToken = $env:ONEDRIVE_REFRESH_TOKEN
if (-not $RefreshToken) {
    throw "ONEDRIVE_REFRESH_TOKEN is not configured"
}

$SiteId = ("$env:ONEDRIVE_SITE_ID").Trim()
$DestRoot = ("$env:ONEDRIVE_PATH").Trim("/")
$RenewUri = "https://api.oplist.org/onedrive/renewapi?refresh_ui=$([uri]::EscapeDataString($RefreshToken))&server_use=true&driver_txt=onedrive_go&client_uid=&client_key="

function Get-OneDriveAccessToken {
    $Response = Invoke-RestMethod -Uri $script:RenewUri -Method Get
    if (-not $Response.access_token) {
        throw "Failed to obtain OneDrive access token from api.oplist.org"
    }
    $script:AccessToken = $Response.access_token
    $Token = @{
        access_token  = $script:AccessToken
        token_type    = "Bearer"
        refresh_token = ""
        expiry        = "2045-12-31T23:59:59Z"
    } | ConvertTo-Json -Compress
    $env:RCLONE_CONFIG_ONEDRIVE_TOKEN = $Token
}

function Install-Rclone {
    $RclonePath = Join-Path $script:RepoRoot "bin\rclone.exe"
    if (Test-Path -Path $RclonePath) {
        return $RclonePath
    }

    Write-Host "rclone not found, downloading..."
    $TempDir = Join-Path $script:RepoRoot "temp"
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $RclonePath) -Force | Out-Null
    $ZipPath = Join-Path $TempDir "rclone.zip"
    Invoke-WebRequest -Uri "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force
    Copy-Item -Path (Join-Path $TempDir "rclone-*-windows-amd64\rclone.exe") -Destination $RclonePath
    return $RclonePath
}

function Get-OneDriveDrive {
    $Headers = @{ Authorization = "Bearer $script:AccessToken" }
    if ($script:SiteId) {
        $Uri = "https://graph.microsoft.com/v1.0/sites/$($script:SiteId)/drive"
    } else {
        $Uri = "https://graph.microsoft.com/v1.0/me/drive"
    }
    $Drive = Invoke-RestMethod -Uri $Uri -Headers $Headers
    if (-not $Drive.id -or -not $Drive.driveType) {
        throw "Failed to resolve OneDrive drive"
    }
    return $Drive
}

function Invoke-RcloneUpload {
    param([string[]] $Arguments)

    & $script:RclonePath @Arguments
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Host "rclone failed (exit code $LASTEXITCODE), refreshing access token and retrying..."
    Get-OneDriveAccessToken
    & $script:RclonePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "rclone failed: $($Arguments -join ' ')"
    }
}

$script:RclonePath = Install-Rclone

Get-OneDriveAccessToken
$Drive = Get-OneDriveDrive
Write-Host "Upload target: $($Drive.name) ($($Drive.driveType)) $($Drive.id)"

$env:RCLONE_CONFIG_ONEDRIVE_TYPE = "onedrive"
$env:RCLONE_CONFIG_ONEDRIVE_DRIVE_ID = $Drive.id
$env:RCLONE_CONFIG_ONEDRIVE_DRIVE_TYPE = $Drive.driveType

Invoke-RcloneUpload -Arguments @("lsd", "onedrive:")

$BuildInfo = @(Get-ChildItem -Path (Join-Path $RepoRoot '*.json') -File | ForEach-Object {
    $JsonFile = $_
    try {
        $Json = Get-Content -Path $JsonFile.FullName -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid build metadata: $($JsonFile.FullName)"
    }
    if (-not $Json.name -or -not $Json.os_version) {
        return
    }
    [pscustomobject]@{ Json = $Json; Path = $JsonFile.FullName }
})
if ($BuildInfo.Count -eq 0) {
    throw "No build metadata (*.json) found, nothing to upload"
}

foreach ($Item in $BuildInfo) {
    $Json = $Item.Json
    $JsonPath = $Item.Path
    $IsoPath = Join-Path $RepoRoot $Json.name
    if (-not (Test-Path -Path $IsoPath)) {
        throw "File not found: $IsoPath"
    }

    $Dest = "onedrive:" + ((@($DestRoot, $Json.os_ver, $Json.os_release, $Json.os_version) | Where-Object { $_ }) -join "/")
    Write-Host "Uploading $IsoPath to $Dest..."
    Invoke-RcloneUpload -Arguments @("copy", $IsoPath, $Dest, "--progress")
    Write-Host "Uploading $JsonPath to $Dest..."
    Invoke-RcloneUpload -Arguments @("copy", $JsonPath, $Dest, "--progress")

    if ($Json.msupdate.skipcheck -ne $true) {
        $Latest = "onedrive:" + ((@($DestRoot, $Json.os_ver, $Json.os_release, "latest_$($Json.os_arch).json") | Where-Object { $_ }) -join "/")
        Write-Host "Uploading $JsonPath to $Latest..."
        Invoke-RcloneUpload -Arguments @("copyto", $JsonPath, $Latest, "--progress")
    }
}
