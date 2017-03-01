
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 

function Remove-LeadingString
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $String,

        [Parameter(Mandatory = $true)]
        [string]
        $LeadingString
    )

    $retStr = $String
            if ($String.StartsWith($LeadingString, $true, [System.Globalization.CultureInfo]::InvariantCulture))
            {
                $retStr = $String.Substring($LeadingString.Length)
            }
                    
    return $retStr
}

function GivenABuiltLibrary
{
    param(
        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $InReleaseMode,

        [string]
        $WithVersion
    )

    $projectRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest' 
    # Make sure the output directory gets created by the task
    $outputDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $optionalArgs = @{ }
    if( $InReleaseMode )
    {
        $optionalArgs['BuildConfiguration'] = 'Release'
    }
    else
    {
        $optionalArgs['BuildConfiguration'] = 'Debug'
    }

    $context = New-WhsCITestContext -ForBuildRoot $projectRoot -ForTaskName 'NuGetPack' -ForOutputDirectory $outputDirectory @optionalArgs
    
    if( $WithVersion )
    {
        $Context.Version.NuGetVersion = $WithVersion
    }

    $Global:Error.Clear()
    $project = Join-Path -Path $projectRoot -ChildPath $projectName -Resolve
    'bin','obj','.output' | 
        ForEach-Object { Get-ChildItem -Path $projectRoot -Filter $_ -ErrorAction Ignore } | Remove-Item -Recurse -Force
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Invoke-MSBuild -Path $project -Target 'build' @propertyArg | Out-Null
    return $context
}

function WhenRunningNuGetPackTask
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [Switch]
        $ForProjectThatDoesNotExist,

        [string]
        $ThatFailsWithErrorMessage,

        [string]
        $WithVersion
    )

    process 
    {
        
        $Global:Error.Clear()
        $taskParameter = @{
                            Path = @(
                                        $projectName
                                    )
                          }

        $threwException = $false
        try
        {
            if( $WithVersion )
            {
                $Context.Version.NugetVersion = $WithVersion
            }
            if( $ForProjectThatDoesNotExist )
            {
                $taskParameter['Path'] = 'I\do\not\exist.csproj'
            }
            Invoke-WhsCINuGetPackTask -TaskContext $Context -TaskParameter $taskParameter | Out-Null

        }
        catch
        {
            $threwException = $true
            Write-Error $_
        }

        if( $ThatFailsWithErrorMessage )
        {
            It 'should throw an exception' {
                $threwException | Should Be $true
                $Global:Error | Should Not BeNullOrEmpty
                $Global:Error[0] | Should Match $ThatFailsWithErrorMessage
            }
        }
        else
        {
            It 'should not throw an exception' {
                $threwException | Should Be $false
                $Global:Error | Should BeNullOrEmpty
            }
        }

        return $Context

    }
}

function ThenPackageShouldBeCreated
{
    param(
        [string]
        $WithVersion,

        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    process
    {
        if( $WithVersion )
        {
            $Context.Version.NuGetVersion = $WithVersion
        }
        It 'should not write any errors' {
            $Global:Error | Should BeNullOrEmpty
        }

        It ('should create NuGet package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $Context.Version.NuGetVersion)) | Should Exist
        }

        It ('should create a NuGet symbols package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $Context.Version.NuGetVersion)) | Should Exist
        }
    }
}

function ThenPackageShouldNotBeCreated
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    It 'should not create any .nupkg files' {
        (Join-Path -Path $Context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a NuGet package with an invalid project' {
    GivenABuiltLibrary | 
        WhenRunningNuGetPackTask -ForProjectThatDoesNotExist -ThatFailsWithErrorMessage 'does not exist' | 
        ThenPackageShouldNotBeCreated
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a NuGet package' {
    GivenABuiltLibrary | WhenRunningNuGetPackTask | ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCINuGetPackTask.when passed a version' {
    $version = '4.5.6-rc1'
    GivenABuiltLibrary -WithVersion $version | WhenRunningNugetPackTask  | ThenPackageShouldBeCreated -WithVersion $version
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a package built in release mode' {
    GivenABuiltLibrary -InReleaseMode | WhenRunningNugetPackTask | ThenPackageShouldBeCreated
}
