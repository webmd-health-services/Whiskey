
function Install-WhiskeyDotNetTool
{
    <#
    .SYNOPSIS
    Installs the .NET Core SDK tooling for a Whiskey task.

    .DESCRIPTION
    The `Install-WhiskeyDotNetTool` function installs the desired version of the .NET Core SDK for a Whiskey task. When given a `Version` the function will attempt to resolve that version to a valid released version of the SDK. If `Version` is null the function will search for a `global.json` file, first in the `WorkingDirectory` and then the `InstallRoot`, and if found it will look for the desired SDK verson in the `sdk.version` property of that file. After installing the SDK the function will update the `global.json`, creating it in the `InstallRoot` if it doesn't exist, `sdk.version` property with the installed version of the SDK. The function returns the path to the installed `dotnet.exe` command.

    .EXAMPLE
    Install-WhiskeyDotNetTool -InstallRoot 'C:\Build\Project' -WorkingDirectory 'C:\Build\Project\src' -Version '2.1.4'
    
    Demonstrates installing version '2.1.4' of the .NET Core SDK to a '.dotnet' directory in the 'C:\Build\Project' directory.

    .EXAMPLE
    Install-WhiskeyDotNetTool -InstallRoot 'C:\Build\Project' -WorkingDirectory 'C:\Build\Project\src' -Version '2.*'
    
    Demonstrates installing the latest '2.*' version of the .NET Core SDK to a '.dotnet' directory in the 'C:\Build\Project' directory.

    .EXAMPLE
    Install-WhiskeyDotNetTool -InstallRoot 'C:\Build\Project' -WorkingDirectory 'C:\Build\Project\src'
    
    Demonstrates installing the version of the .NET Core SDK specified in the `sdk.version` property of the `global.json` file found in either the `WorkingDirectory` or the `InstallRoot` paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # Path where the `.dotnet` directory will be installed containing the .NET Core SDK.
        [String]$InstallRoot,

        [Parameter(Mandatory)]
        # The working directory of the task requiring the .NET Core SDK tool. This path is used for searching for an existing `global.json` file containing an SDK version value.
        [String]$WorkingDirectory,

        [AllowEmptyString()]
        [AllowNull()]
        # The version of the .NET Core SDK to install. Accepts wildcards.
        [String]$Version
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $globalJsonPath = Join-Path -Path $WorkingDirectory -ChildPath 'global.json'
    if (-not (Test-Path -Path $globalJsonPath -PathType Leaf))
    {
        $globalJsonPath = Join-Path -Path $InstallRoot -ChildPath 'global.json'
    }
    
    $sdkVersion = $null
    if ($Version)
    {
        Write-WhiskeyVerbose -Message ('[{0}] .NET Core SDK version ''{1}'' found in whiskey.yml' -f $MyInvocation.MyCommand,$Version)
        $sdkVersion = Resolve-WhiskeyDotNetSdkVersion -Version $Version
    }
    elseif (Test-Path -Path $globalJsonPath -PathType Leaf)
    {
        try
        {
            $globalJson = Get-Content -Path $globalJsonPath -Raw | ConvertFrom-Json
        }
        catch
        {
            Write-WhiskeyError -Message ('global.json file ''{0}'' contains invalid JSON.' -f $globalJsonPath)
            return
        }

        $globalJsonVersion = $globalJson |
                                 Select-Object -ExpandProperty 'sdk' -ErrorAction Ignore |
                                 Select-Object -ExpandProperty 'version' -ErrorAction Ignore
        
        $globalJsonRollForward = $globalJson |
                           Select-Object -ExpandProperty 'sdk' -ErrorAction Ignore |
                           Select-Object -ExpandProperty 'rollForward' -ErrorAction Ignore
        $rollForward = [Whiskey.DotNetSdkRollForward]$globalJsonRollForward
        if ( $globalJsonVersion -and $null -ne $rollForward )
        {
            $msg = "[$($MyInvocation.MyCommand)] .NET Core SDK version '$($globalJsonVersion)' with rollforward value set to '$($globalJsonRollForward)' found in '$($globalJsonPath)'"
            Write-WhiskeyVerbose -Message $msg
            $sdkVersion = Resolve-WhiskeyDotNetSdkVersion -Version $globalJsonVersion -RollForward $rollForward
        }
        elseif ($globalJsonVersion)
        {
            Write-WhiskeyVerbose -Message ('[{0}] .NET Core SDK version ''{1}'' found in ''{2}''' -f $MyInvocation.MyCommand,$globalJsonVersion,$globalJsonPath)
            $sdkVersion = Resolve-WhiskeyDotNetSdkVersion -Version $globalJsonVersion
        }
    }

    if (-not $sdkVersion)
    {
        Write-WhiskeyVerbose -Message ('[{0}] No specific .NET Core SDK version found in whiskey.yml or global.json. Using latest LTS version.' -f $MyInvocation.MyCommand)
        $sdkVersion = Resolve-WhiskeyDotNetSdkVersion -LatestLTS
    }

    $installRoot = Join-Path -Path $InstallRoot -ChildPath '.dotnet'
    $dotnetPath = Install-WhiskeyDotNetSdk -InstallRoot $installRoot -Version $sdkVersion

    Set-WhiskeyDotNetGlobalJson -Directory ($globalJsonPath | Split-Path -Parent) -SdkVersion $sdkVersion

    return $dotnetPath
}
