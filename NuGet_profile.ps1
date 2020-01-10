param (
    [Parameter(Mandatory = $True)]
    [string] $NuGetClientRoot
    )

Import-Module Posh-Git
Import-Module PSReadLine  
Set-PSReadlineKeyHandler -Key Tab -Function Complete
Set-PSReadlineOption -BellStyle None

. $PSScriptRoot\Patch_CLI.ps1
. $PSScriptRoot\Utilities.ps1

Set-Location $NuGetClientRoot

<#
Auto bootstraps NuGet for debugging the targets. This includes both restore and pack and is the recommended way to test things :) 
#>
$VSVersion = "16.0"
$Configuration = "Debug"
$Framework = "net472"

Function Invoke-NuGetCustom()
{
    $packDllPath = Join-Path $NuGetClientRoot "artifacts\NuGet.Build.Tasks.Pack\$VSVersion\bin\$Configuration\$Framework\NuGet.Build.Tasks.Pack.dll"
    $packTargetsPath = Join-Path $NuGetClientRoot "src\NuGet.Core\NuGet.Build.Tasks.Pack\NuGet.Build.Tasks.Pack.targets"
    $restoreDllPath = Join-Path $NuGetClientRoot "artifacts\NuGet.Build.Tasks\$VSVersion\bin\$Configuration\$Framework\NuGet.Build.Tasks.dll"
    $nugetRestoreTargetsPath = Join-Path $NuGetClientRoot "src\NuGet.Core\NuGet.Build.Tasks\NuGet.targets"
    Write-Host "msbuild /p:NuGetRestoreTargets=$nugetRestoreTargetsPath /p:RestoreTaskAssemblyFile=$restoreDllPath /p:NuGetBuildTasksPackTargets=$packTargetsPath /p:ImportNuGetBuildTasksPackTargetsFromSdk=true /p:NuGetPackTaskAssemblyFile=$packDllPath $($args[0..$args.Count])" 
    & msbuild /p:NuGetRestoreTargets=$nugetRestoreTargetsPath /p:RestoreTaskAssemblyFile=$restoreDllPath /p:NuGetBuildTasksPackTargets=$packTargetsPath /p:ImportNuGetBuildTasksPackTargetsFromSdk=true /p:NuGetPackTaskAssemblyFile=$packDllPath $args[0..$args.Count]
}

<#
Auto bootstraps NuGet for debugging the restore targets only (this doesn't include the pack targets!)
#>
Function Invoke-NuGetRestoreCustom()
{
    $restoreDllPath = Join-Path $NuGetClientRoot "artifacts\NuGet.Build.Tasks\$VSVersion\bin\$Configuration\$Framework\NuGet.Build.Tasks.dll"
    $nugetRestoreTargetsPath = Join-Path $NuGetClientRoot "src\NuGet.Core\NuGet.Build.Tasks\NuGet.targets"
    Write-Host "msbuild /p:NuGetRestoreTargets=$nugetRestoreTargetsPath /p:RestoreTaskAssemblyFile=$restoreDllPath $($args[0..$args.Count])" 
    & msbuild /p:NuGetRestoreTargets=$nugetRestoreTargetsPath /p:RestoreTaskAssemblyFile=$restoreDllPath $args[0..$args.Count]
}

<#
Auto bootstraps NuGet for debugging the pack targets only (this doesn't include the restore targets!)
#>
Function Invoke-NuGetPackCustom()
{
    $packDllPath = Join-Path $NuGetClientRoot "artifacts\NuGet.Build.Tasks.Pack\$VSVersion\bin\$Configuration\$Framework\NuGet.Build.Tasks.Pack.dll"
    $packTargetsPath = Join-Path $NuGetClientRoot "src\NuGet.Core\NuGet.Build.Tasks.Pack\NuGet.Build.Tasks.Pack.targets"
    Write-Host "msbuild /p:NuGetBuildTasksPackTargets=$packTargetsPath /p:ImportNuGetBuildTasksPackTargetsFromSdk=true /p:NuGetPackTaskAssemblyFile=$packDllPath $($args[0..$args.Count])" 
    & msbuild /p:NuGetBuildTasksPackTargets=$packTargetsPath /p:ImportNuGetBuildTasksPackTargetsFromSdk=true /p:NuGetPackTaskAssemblyFile=$packDllPath $args[0..$args.Count]
}