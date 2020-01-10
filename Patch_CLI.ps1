Function Patch-CLI {
    param
    (
        [string]$sdkLocation,
        [string]$nugetClientRoot,
        [switch]$createSdkLocation
    )


    if ( (-Not $createSdkLocation) -And (-Not (Test-Path $sdkLocation)))
    {
        Write-Error "The SDK path $sdkLocation does not exist!"
        return;
    }

    if($createSdkLocation)
    {
        if(-Not (Test-Path $sdkLocation))
        {
            New-Item $sdkLocation -ItemType Directory
        }
    }
    $sdk_path = $sdkLocation
    
    $nugetXplatArtifactsPath = [System.IO.Path]::Combine($nugetClientRoot, 'artifacts', 'NuGet.CommandLine.XPlat', '16.0', 'bin', 'Debug', 'netcoreapp2.1')
    $nugetBuildTasks = [System.IO.Path]::Combine($nugetClientRoot, 'artifacts', 'NuGet.Build.Tasks', '16.0', 'bin', 'Debug', 'netstandard2.0', 'NuGet.Build.Tasks.dll')
    $nugetTargets = [System.IO.Path]::Combine($nugetClientRoot, 'src', 'NuGet.Core', 'NuGet.Build.Tasks', 'NuGet.targets')

    if (-Not (Test-Path $nugetXplatArtifactsPath)) {
        Write-Error "$nugetXplatArtifactsPath not found!"
        return;
    }

    if (-Not (Test-Path $nugetBuildTasks)) {
        Write-Error "$nugetBuildTasks not found!"
        return;
    }

    if (-Not (Test-Path $nugetTargets)) {
        Write-Error "$nugetTargets not found!"
        return;
    }
 
    Write-Host
    Write-Host "Source commandline path - $nugetXplatArtifactsPath"
    Write-Host "Destination sdk path - $sdk_path"
    Write-Host
    
    Get-ChildItem $nugetXplatArtifactsPath -Filter NuGet*.dll | 
        Foreach-Object {	
            $new_position = "$($sdk_path)\$($_.BaseName )$($_.Extension )"
                
            Write-Host "Moving to - $($new_position)"
            Copy-Item $_.FullName $new_position
        }

    $buildTasksDest = "$($sdk_path)\NuGet.Build.Tasks.dll" 
    Write-Host "Moving to - $($buildTasksDest)"
    Copy-Item $nugetBuildTasks $buildTasksDest

    $nugetTargetsDest = "$($sdk_path)\NuGet.targets" 
    Write-Host "Moving to - $($nugetTargetsDest)"
    Copy-Item $nugetTargets $nugetTargetsDest
}

[Reflection.Assembly]::LoadWithPartialName('System.IO.Compression') | Out-Null

Function Deduce-Version(
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $nupkgsDirectory)
{
    $packageId = 'NuGet.Common'

    $nupkgFiles = $nupkgsDirectory.GetFiles("$packageId`.*.nupkg", [System.IO.SearchOption]::TopDirectoryOnly)

    ForEach ($nupkgFile In $nupkgFiles)
    {
        $fileName = $nupkgFile.Name
        $from = $packageId.Length + 1 # +1 for .

        $to = $fileName.IndexOf('.symbols.nupkg')

        If ($to -eq -1)
        {
            $to = $fileName.IndexOf('.nupkg')
        }

        Return $fileName.Substring($from, $to - $from)
    }
}

Function Get-NupkgFile(
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $nupkgsDirectory,
    [Parameter(Mandatory = $True)] [string] $packageId,
    [Parameter(Mandatory = $True)] [string] $packageVersion,
    [Parameter(Mandatory = $True)] [bool] $includeSymbols)
{
    [System.IO.FileInfo] $nupkgFile

    If ($includeSymbols)
    {
        $nupkgFile = [System.IO.FileInfo]::new([System.IO.Path]::Combine($nupkgsDirectory.FullName, "$packageId`.$packageVersion`.symbols.nupkg"))
    }
    Else
    {
        $nupkgFile = [System.IO.FileInfo]::new([System.IO.Path]::Combine($nupkgsDirectory.FullName, "$packageId`.$packageVersion`.nupkg"))
    }

    If (!$nupkgFile.Exists)
    {
        Throw [System.IO.FileNotFoundException]::new("$($nupkgFile.FullName) does not exist.", $nupkgFile.FullName)
    }

           Return $nupkgFile
}

Function Extract-FilesFromNupkg(
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $nupkgsDirectory,
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $destinationDirectory,
    [Parameter(Mandatory = $True)] [string] $packageId,
    [Parameter(Mandatory = $True)] [string] $packageVersion,
    [Parameter(Mandatory = $True)] [string[]] $sourceFilePaths,
    [Parameter(Mandatory = $True)] [bool] $includeSymbols)
{
    $nupkgFile = Get-NupkgFile $nupkgsDirectory $packageId $packageVersion $includeSymbols

    $stream = [System.IO.File]::OpenRead($nupkgFile.FullName)

    Try
    {
        $zip = [System.IO.Compression.ZipArchive]::new($stream)

        ForEach ($sourceFilePath In $sourceFilePaths)
        {
            $zipEntry = $zip.GetEntry($sourceFilePath)
            $sourceFileStream = $zipEntry.Open()
            $destinationFilePath = [System.IO.Path]::Combine($destinationDirectory.FullName, $zipEntry.Name)
            $destinationFile = [System.IO.FileInfo]::new($destinationFilePath)

            If ($destinationFile.Exists)
            {
                $destinationFile.Delete()
                $destinationFile.Refresh()
            }

            Write-Host "Extracting $($nupkgFile.Name)/$sourceFilePath"

            $destinationFileStream = $destinationFile.OpenWrite()

            Try
            {
                $sourceFileStream.CopyTo($destinationFileStream)
            }
            Finally
            {
                $sourceFileStream.Dispose()
                $destinationFileStream.Dispose()
            }
        }
    }
    Finally
    {
        $zip.Dispose()
        $stream.Dispose()
    }
}

Function Is-DotNetSdkDirectory(
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $sdkDirectory)
{
    If (!$sdkDirectory.Exists)
    {
        Return $False
    }

    $files = $sdkDirectory.GetFiles('NuGet.*.dll', [System.IO.SearchOption]::TopDirectoryOnly)

    If ($files.Count -eq 0)
    {
        Return $False
    }

    $dotnetFile = [System.IO.FileInfo]::new([System.IO.Path]::Combine($sdkDirectory.FullName, '..', '..', 'dotnet.exe'))

    Return $dotnetFile.Exists
}

Function Is-NupkgsDirectory(
    [Parameter(Mandatory = $True)] [System.IO.DirectoryInfo] $nupkgsDirectory)
{
    If (!$nupkgsDirectory.Exists)
    {
        Return $False
    }

    $nupkgs = $nupkgsDirectory.GetFiles('*.nupkg', [System.IO.SearchOption]::TopDirectoryOnly)

    Return $nupkgs.Count -gt 0
}

# Example Patch-CLI-From-NupkgsDirectory -nupkgsDirectoryPath 'F:\git\NuGet.Client\artifacts\nupkgs' -sdkDirectoryPath 'F:\repro\dotnet\sdk\3.0.100-preview4-011223'
Function Patch-CLI-From-NupkgsDirectory(
    [Parameter(Mandatory = $True)]  [string] $nupkgsDirectoryPath,
    [Parameter(Mandatory = $True)]  [string] $sdkDirectoryPath,
    [Parameter(Mandatory = $False)] [string] $version = $Null,
    [Parameter(Mandatory = $False)] [bool] $includeSymbols
)
{
    $nupkgsDirectory = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($nupkgsDirectoryPath))
    $sdkDirectory = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($sdkDirectoryPath))
    $isNupkgsDirectory = Is-NupkgsDirectory($nupkgsDirectory)
    $isSdkDirectory = Is-DotNetSdkDirectory($sdkDirectory)

    If (!$isNupkgsDirectory)
    {
        Write-Error "$($nupkgsDirectory.FullName) is not a valid nupkgs directory.  Example of an expected nupkgs directory:  C:\git\NuGet.Client\artifacts\nupkgs."
        Exit 1
    }

    If (!$isSdkDirectory)
    {
        Write-Error "$($sdkDirectory.FullName) is not a valid .NET Core SDK directory.  Example of an expected .NET Core SDK directory:  C:\Program Files\dotnet\sdk\2.1.700-preview-009601"
        Exit 1
    }

    If (!$version)
    {
        $version = Deduce-Version -nupkgsDirectory $nupkgsDirectory
    }

    Write-Host "Source directory:  $($nupkgsDirectory.FullName)"
    Write-Host "Destination directory:  $($sdkDirectory.FullName)"
    Write-Host "Version:  $version"
    Write-Host

    $files = @('runtimes/any/native/NuGet.targets', 'lib/netstandard2.0/NuGet.Build.Tasks.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Build.Tasks.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Build.Tasks' $version $files $includeSymbols

    $files = @('lib/netcoreapp2.1/NuGet.CommandLine.XPlat.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netcoreapp2.1/NuGet.CommandLine.XPlat.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.CommandLine.XPlat' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Commands.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Commands.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Commands' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Common.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Common.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Common' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Configuration.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Configuration.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Configuration' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Credentials.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Credentials.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Credentials' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.DependencyResolver.Core.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.DependencyResolver.Core.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.DependencyResolver.Core' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Frameworks.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Frameworks.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Frameworks' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.LibraryModel.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.LibraryModel.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.LibraryModel' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Packaging.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Packaging.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Packaging' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Packaging.Core.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Packaging.Core.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Packaging.Core' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.ProjectModel.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.ProjectModel.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.ProjectModel' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Protocol.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Protocol.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Protocol' $version $files $includeSymbols

    $files = @('lib/netstandard2.0/NuGet.Versioning.dll')
    If ($includeSymbols)
    {
        $files += 'lib/netstandard2.0/NuGet.Versioning.pdb'
    }
    Extract-FilesFromNupkg $nupkgsDirectory $sdkDirectory 'NuGet.Versioning' $version $files $includeSymbols
}

# Example Patch-CLI-From-NupkgsDirectory -nupkgsDirectoryPath '\\ddfiles\Drops\NuGet\Drops\CI\NuGet.Client\dev-nkolev92-cancellationTracking\5.4.0.8758\artifacts\VS15\Nupkgs' -sdkDirectoryPath 'C:\Users\nikolev.REDMOND\Downloads\dotnet-3.0.1xx-sdk-latest-win-x64\sdk\3.0.100-rc2-014271'
Function Patch-CLI-Zip(
    [Parameter(Mandatory = $True)]  [string] $nupkgsDirectoryPath,
    [Parameter(Mandatory = $True)]  [string] $sdkFilePath,
    [Parameter(Mandatory = $True)]  [string] $patchSdkDirectory,
    [Parameter(Mandatory = $False)] [bool] $includeSymbols
)
{
    $nupkgsDirectoryPath = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($nupkgsDirectoryPath))
    $sdkFilePath = Resolve-Path $sdkFilePath
    $patchSdkDirectory = Resolve-Path $patchSdkDirectory

    $isNupkgsDirectory = Is-NupkgsDirectory($nupkgsDirectoryPath)

    if(-Not (Test-Path $sdkFilePath))
    {
        Write-Error "The sdk file path $sdkFilePath does not exist"
        Exit 1
    }
    If (!$isNupkgsDirectory)
    {
        Write-Error "$($nupkgsDirectoryPath.FullName) is not a valid nupkgs directory.  Example of an expected nupkgs directory:  C:\git\NuGet.Client\artifacts\nupkgs."
        Exit 1
    }

    $version = Deduce-Version -nupkgsDirectory $nupkgsDirectoryPath
    $newSdkPath = Calculate-New-Sdk-Path $sdkFilePath $patchSdkDirectory $version

    Write-Host "Source directory:  $($nupkgsDirectoryPath)"
    Write-Host "Destination SDK file path:  $($newSdkPath)"
    Write-Host "Current SDK file path: $($sdkFilePath)"
    Write-Host "Version:  $version"
    Write-Host

    $parent = New-TemporaryDirectory
    Write-Host "Using temp path $parent"

    Expand-Archive -Path $sdkFilePath -DestinationPath $parent

    $extractedSdkDirectory = Find-Sdk-RootPath $parent

    Patch-CLI-From-NupkgsDirectory  -nupkgsDirectoryPath $nupkgsDirectoryPath -sdkDirectoryPath $extractedSdkDirectory

    Compress-Archive "$parent\*" -DestinationPath $newSdkPath -Update
    Write-Host "Cleaning up temp path $parent"
    Remove-Item $parent -Recurse

    Write-Host "New SDK at $newSdkPath"
}

Function Calculate-New-Sdk-Path(
    [Parameter(Mandatory = $True)] [string] $sdkFilePath,
    [Parameter(Mandatory = $True)] [string] $patchSdkDirectory,
    [Parameter(Mandatory = $True)] [string] $version
)
{
    $currentSdkName = [System.IO.Path]::GetFileNameWithoutExtension($sdkFilePath)
    $newSDKName = $currentSdkName + "-" + $version + ".zip"
    return Join-Path $patchSdkDirectory $newSDKName
}

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Find-Sdk-RootPath(
    [Parameter(Mandatory = $True)] [string] $sdkRootPath
)
{
    if(-Not (Test-Path $sdkRootPath))
    {
        Write-Error "The sdk root path does not exist $sdkRootPath"
        Exit 1
    }
    $sdkDirectory = Join-Path $sdkRootPath "sdk"
    $sdkVersionedDirectory = Join-Path $sdkDirectory (Get-ChildItem $sdkDirectory)[0].Name
    return $sdkVersionedDirectory
}