if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Exit
}


<#
.SYNOPSIS
    Installs baseline and department software using WinGet.

.DESCRIPTION
    Determines the department from Active Directory.
    Falls back to manual selection if unavailable.
#>

#region Variables

$RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path

$ConfigPath = Join-Path $RootPath "Configs"

$LogFolder = Join-Path $RootPath "Logs"

$LogFile = Join-Path $LogFolder (
    "Deployment_{0}.log" -f (
        Get-Date -Format "yyyyMMdd_HHmmss"
    )
)

#endregion

#region Logging

if (!(Test-Path $LogFolder))
{
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

Start-Transcript -Path $LogFile

#endregion

#region Functions

function Write-Section
{
    param([string]$Text)

    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
}

function Test-WinGetInstalled
{
    if (!(Get-Command winget -ErrorAction SilentlyContinue))
    {
        throw "WinGet is not installed."
    }
}

function Get-UserDepartment
{
    try
    {
        Import-Module ActiveDirectory -ErrorAction Stop

        $User = Get-ADUser `
            $env:USERNAME `
            -Properties Department

        if ($User.Department)
        {
            return $User.Department
        }
    }
    catch
    {
        Write-Warning "Unable to read department from Active Directory."
    }

    return $null
}

function Select-Department
{
    Write-Host ""
    Write-Host "Select Department:"
    Write-Host "1 - Finance"
    Write-Host "2 - Engineering"
    Write-Host "3 - HR"
    Write-Host "4 - Marketing"

    $Selection = Read-Host "Choice"

    switch ($Selection)
    {
        "1" { "Finance" }
        "2" { "Engineering" }
        "3" { "HR" }
        "4" { "Marketing" }
        default { throw "Invalid department selection." }
    }
}

function Install-WinGetConfig
{
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFile
    )

    if (!(Test-Path $ConfigFile))
    {
        throw "$ConfigFile not found."
    }

    Write-Host "Processing $ConfigFile" -ForegroundColor Green

    winget import `
        --import-file $ConfigFile `
        --accept-package-agreements `
        --accept-source-agreements `
        --ignore-unavailable
}

function Confirm-PackageInstalled
{
    param(
        [string]$PackageName
    )

    $Found = winget list --exact --id $PackageName 2>$null

    return [bool]$Found
}

#endregion

try
{
    Write-Section "Department Deployment Started"

    Test-WinGetInstalled

    Write-Host "Updating WinGet sources..."
    winget source update

    $Department = Get-UserDepartment

    if (!$Department)
    {
        Write-Warning "No department found in AD."
        $Department = Select-Department
    }

    Write-Host ""
    Write-Host "Detected Department: $Department" `
        -ForegroundColor Green

    $BaseFile = Join-Path $ConfigPath "Base.json"
    $DeptFile = Join-Path $ConfigPath "$Department.json"

    Write-Section "Installing Base Applications"

    Install-WinGetConfig $BaseFile

    Write-Section "Installing Department Applications"

    Install-WinGetConfig $DeptFile

    Write-Section "Deployment Complete"

    Write-Host "Department: $Department"
    Write-Host "Log File: $LogFile"

}
catch
{
    Write-Host ""
    Write-Error $_.Exception.Message
}
finally
{
    Stop-Transcript
}