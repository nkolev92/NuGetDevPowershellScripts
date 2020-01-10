Function IsolateRestore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootDirectory
    )

    Write-Host "The root directory is $RootDirectory"
    $gpf = Join-Path $RootDirectory -ChildPath "gpf"
    $httpCache = Join-Path $RootDirectory -ChildPath "httpCache"
    $pluginLogs = Join-Path $RootDirectory -ChildPath "plugin-logs"

    Write-Host "Setting the global packages folder to $gpf"
    $env:NUGET_PACKAGES=$gpf
    Write-Host "Setting the http cache to $httpCache"
    $env:NUGET_HTTP_CACHE_PATH=$httpCache
    Write-Host "Enabling the plugins loggings"
    $Env:NUGET_PLUGIN_ENABLE_LOG='true'
    Write-Host "Setting the plugin log directory to $pluginLogs"
    $Env:NUGET_PLUGIN_LOG_DIRECTORY_PATH=$pluginLogs
    Write-Host "Creating the plugin logs path."
    New-Item -Path $pluginLogs
    # https://docs.microsoft.com/en-us/nuget/consume-packages/managing-the-global-packages-and-cache-folders
    # https://github.com/NuGet/Home/wiki/Plugin-Diagnostic-Logging
}

Function CompareFiles {
    [CmdletBinding()]
    param(
        [string]$file1,
        [string]$file2
    )

    if((Get-FileHash $file1).hash  -ne (Get-FileHash $file2).hash){
        Write-Host "Files are the same".
    } else {
        Write-Host "Files are different."
    }
}

Function Remove-OrphanedLocalBranches() {
    @(git branch -vv) | findstr ": gone]" | findstr /V "\*" | %{$_.Split(' ')[2];} | findstr /V "^release" | % { git branch -D $_}
}

Function Invoke-TestsWithFilter 
{    
    <#
  .SYNOPSIS
  Restores, Builds and runs tests.
  .DESCRIPTION
  Restores, Builds and runs tests using dotnet and filtering of scope.
  .EXAMPLE
  Run-TestsWithFilter TestMethodName -restore -build
  .EXAMPLE
  Run-TestsWithFilter TestMethodName -b
  .PARAMETER filter
  The filter to be passed to dotnet test --filter option. No filter will run all tests.
  .PARAMETER restore
  Restores the project before running tests.
  .PARAMETER build
  Builds the project before running tests.
  #>
    [CmdletBinding()]
    param
    (
        [Alias('f')]
        [string]$filter,
        [Alias('r')]
        [switch]$restore,
        [Alias('b')]
        [switch]$build
    )

    if ($restore) 
    {
        Write-Host "msbuild /v:m /m /t:restore"
        & msbuild /v:m /m /t:restore
    }

    if ($build) 
    {
        Write-Host "msbuild /v:m /m"
        & msbuild /v:m /m
    }

    if ([string]::IsNullOrEmpty($filter)) 
    {
        Write-Host "dotnet test --no-build --no-restore"
        & dotnet test --no-build --no-restore
    }
    else 
    {
        Write-Host "dotnet test --no-build --no-restore --filter DisplayName~$filter"
        & dotnet test --no-build --no-restore --filter DisplayName~$filter
    }
}

Function Invoke-Expression 
{
    param
    (
        [string]$expression
    )
    Write-Host "$expression"
    Invoke-Expression $expression
}