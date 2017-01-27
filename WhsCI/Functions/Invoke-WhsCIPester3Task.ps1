
function Invoke-WhsCIPester3Task
{
    <#
    .SYNOPSIS
    Runs Pester tests using Pester 3.

    .DESCRIPTION
    The `Invoke-Pester3Task` runs tests using Pester 3. You pass the path(s) to test to the `Path` parameter, which are passed directly to the `Invoke-Pester` function's `Script` parameter. Use the `Config` parameter to pass additional configuration needed by this task. The additional configuration can be:

    * Version: The version of Pester 3 to use. Can be a version between 3.0 but less than 4.0. Must match a version on the Powershell Gallery. To find a list of all the versions of Pester available, install the Package Management module, then run `Find-Module -Name 'Pester' -AllVersions`. You usually want the latest version.

    If any tests fail (i.e. if the `FailedCount property on the result object returned by `Invoke-Pester` is greater than 0), this function will throw a terminating error.

    .EXAMPLE
    Invoke-Pester3Task -OutputRoot '.\.output' -Path '.\Test' -Config @{ Version = '3.4.3' }

    Demonstrates how to run Pester tests against a set of test fixtures. In this case, Pester version 3.4.3 will recursively run all tests under `.\Test` and output an XML report with the results in the `.\.output` directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the output directory. The Pester test result XML files will be saved to this directory.
        $OutputRoot,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The paths to the tests to run. These are passed directly to the `Invoke-Pester` function's `Script` parameter.
        $Path,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # Additional configuration used by the task. The following properties are supported:
        #
        # * Version: The version of Pester 3 to use. Can be a version between 3.0 but less than 4.0. Must match a version on the Powershell Gallery. To find a list of all the versions of Pester available, install the Package Management module, then run `Find-Module -Name 'Pester' -AllVersions`. You usually want the latest version.
        $Config
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $Config.ContainsKey('Version') )
    {
        throw ('Configuration property ''Version'' is mandatory. It should be set to the version of Pester 3 you want to use. It should be greater than or equal to 3.0.3 and less than 4.0.0. Available version numbers can be found at https://www.powershellgallery.com/packages/Pester')
    }

    $version = $Config['Version'] | ConvertTo-WhsCISemanticVersion
    if( -not $version )
    {
        throw ('Configuration property ''Version'' isn''t a valid version number. It must be a version number of the form MAJOR.MINOR.BUILD.')
    }
    $version = [version]('{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch)

    $pesterModulePath = Install-WhsCITool -ModuleName 'Pester' -Version $version
    if( -not $pesterModulePath )
    {
        throw ('Failed to download or install Pester {0}, most likely because version {0} does not exist. Available version numbers can be found at https://www.powershellgallery.com/packages/Pester' -f $version)
    }

    $testIdx = 0
    $outputFileNameFormat = 'pester-{0:00}.xml'
    while( (Test-Path -Path (Join-Path -Path $OutputRoot -ChildPath ($outputFileNameFormat -f $testIdx))) )
    {
        $testIdx++
    }

    # We do this in the background so we can test this with Pester. Pester tests calling Pester tests. Madness!
    $result = Start-Job -ScriptBlock {
        $script = $using:Path
        $outputRoot = $using:OutputRoot
        $testIdx = $using:testIdx
        $pesterModulePath = $using:pesterModulePath
        $outputFileNameFormat = $using:outputFileNameFormat

        Import-Module -Name $pesterModulePath
        $outputFile = Join-Path -Path $outputRoot -ChildPath ($outputFileNameFormat -f $testIdx)
        Invoke-Pester -Script $script -OutputFile $outputFile -OutputFormat LegacyNUnitXml -PassThru
    } | Wait-Job | Receive-Job

    if( $result.FailedCount )
    {
        throw ('Pester tests failed.')
    }
}