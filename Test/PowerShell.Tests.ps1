
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {

    Set-StrictMode -Version 'Latest'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDir = $null
    $script:workingDirectory = $null
    $script:failed = $false
    $script:scriptBlock = $null
    $script:scriptName = $null

    function Get-OutputFilePath
    {
        $path = (Join-Path -Path $script:testDir -ChildPath ('{0}\run' -f $script:workingDirectory))
        if( -not [IO.Path]::IsPathRooted($path) )
        {
            $path = Join-Path -Path $script:testDir -ChildPath $path
        }
        return $path
    }

    function GivenAFailingScript
    {
        GivenAScript 'exit 1'
    }

    function GivenAPassingScript
    {
        param(
            [String] $Named
        )

        GivenAScript '' -Named $Named
    }

    function GivenAScript
    {
        param(
            [Parameter(Position=0)]
            [String]$Script,

            [String] $Named = 'myscript.ps1',

            [String]$WithParam = 'param([Parameter(Mandatory)][Object]$TaskContext)'
        )

        if (-not $Named)
        {
            $Named = 'myscript.ps1'
        }

        $script:scriptName = $Named
        $scriptPath = Join-Path -Path $script:testDir -ChildPath $script:scriptName

        @"
    $($WithParam)

    New-Item -Path '$( Get-OutputFilePath | Split-Path -Leaf)' -ItemType 'File'

    $($Script)
"@ | Set-Content -Path $scriptPath
    }

    function GivenLastExitCode
    {
        param(
            $ExitCode
        )

        $Global:LASTEXITCODE = $ExitCode
    }

    function GivenNoWorkingDirectory
    {
        $script:workingDirectory = $null
    }

    function GivenScriptBlock
    {
        param(
            [String]$ScriptBlock
        )

        $script:scriptBlock = $ScriptBlock
    }

    function GivenWorkingDirectory
    {
        param(
            [String]$Path,

            [switch]$ThatDoesNotExist
        )

        $script:workingDirectory = $Path

        $absoluteWorkingDir = $script:workingDirectory
        if( -not [IO.Path]::IsPathRooted($absoluteWorkingDir) )
        {
            $absoluteWorkingDir = Join-Path -Path $script:testDir -ChildPath $absoluteWorkingDir
        }

        if( -not $ThatDoesNotExist -and -not (Test-Path -Path $absoluteWorkingDir -PathType Container) )
        {
            New-Item -Path $absoluteWorkingDir -ItemType 'Directory'
        }

    }

    function ThenFile
    {
        param(
            $Path,
            $HasContent
        )

        $fullpath = Join-Path -Path $script:testDir -ChildPath $Path
        $fullpath | Should -Exist
        Get-Content -Path $fullpath | Should -Be $HasContent
    }

    function ThenTheLastErrorMatches
    {
        param(
            $Pattern
        )

        $Global:Error[0] | Should -Match $Pattern
    }

    function ThenTheLastErrorDoesNotMatch
    {
        param(
            $Pattern
        )

        $Global:Error[0] | Should -Not -Match $Pattern
    }

    function ThenTheScriptRan
    {
        Get-OutputFilePath | Should -Exist
    }

    function ThenTheScriptDidNotRun
    {
        Get-OutputFilePath | Should -Not -Exist
    }

    function ThenTheTaskFails
    {
        $script:failed | Should -BeTrue
    }

    function ThenTheTaskPasses
    {
        $script:failed | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
    }


    function WhenTheTaskRuns
    {
        [CmdletBinding()]
        param(
            [Object] $WithArgument,

            [switch] $InCleanMode,

            [switch] $InInitMode,

            [String] $WithDefaultProperty
        )

        $context = New-WhiskeyTestContext -ForDeveloper `
                                          -InCleanMode:$InCleanMode `
                                          -InInitMode:$InInitMode `
                                          -ForBuildRoot $script:testDir

        $taskParameter = @{}

        if( $script:scriptName )
        {
            $taskParameter['Path'] = @( $script:scriptName )

            Get-Content -Path (Join-Path -Path $script:testDir -ChildPath $script:scriptName) -Raw |
                Write-WhiskeyDebug -Context $context
        }

        if( $null -ne $script:scriptBlock )
        {
            $taskParameter['ScriptBlock'] = $script:scriptBlock
            $script:scriptBlock | Write-WhiskeyDebug -Context $context
        }

        if( $script:workingDirectory )
        {
            $taskParameter['WorkingDirectory'] = $script:workingDirectory
        }

        if( $WithArgument )
        {
            $taskParameter['Argument'] = $WithArgument
        }

        if ($WithDefaultProperty)
        {
            $taskParameter.Remove('Path')
            $taskParameter.Remove('Argument')
            $taskParameter[''] = $WithDefaultProperty
        }

        $script:failed = $false

        $Global:Error.Clear()
        $script:failed = $false
        try
        {
            Invoke-WhiskeyTask -Name 'PowerShell' -TaskContext $context -Parameter $taskParameter
        }
        catch
        {
            Write-CaughtError -ErrorRecord $_
            $script:failed = $true
        }
    }
}

Describe 'PowerShell' {
    BeforeEach {
        $script:testDir = New-WhiskeyTestRoot
        $script:failed = $false
        $script:scriptBlock = $null
        $script:scriptName = $null
        $script:workingDirectory = $null
    }

    AfterEach {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        # Rename the test directory to make sure PowerShell processes are terminated so that Pester can delete the
        # TestDrive.
        while ($stopwatch.Elapsed -lt [timespan]'00:00:10')
        {
            try
            {
                Rename-Item -Path $script:testDir -NewName ".$($script:testDir | Split-Path -Leaf)" -ErrorAction Ignore
            }
            catch
            {
                Write-Warning "Test directory ""$($script:testDir)"" still in use."
            }

            if (-not (Test-Path -Path $script:testDir))
            {
                break
            }

            Start-Sleep -Milliseconds 100
        }
    }

    It 'interprets zero exit code and no error as successful' {
        GivenAPassingScript
        GivenNoWorkingDirectory
        WhenTheTaskRuns
        ThenTheScriptRan
        ThenTheTaskPasses
    }

    It 'interprets zero exit code and no error as successful' {
        GivenAPassingScript
        GivenNoWorkingDirectory
        WhenTheTaskRuns
        ThenTheScriptRan
        ThenTheTaskPasses
    }

    It 'interprets a non-zero exit code as a build failure' {
        GivenNoWorkingDirectory
        GivenAFailingScript
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheScriptRan
        ThenTheTaskFails
        ThenTheLastErrorMatches 'failed, exited with code'
    }

    It 'ignores LASTEXITCODE from previous commands' {
        GivenNoWorkingDirectory
        GivenAPassingScript
        GivenLastExitCode 1
        WhenTheTaskRuns
        ThenTheScriptRan
        ThenTheTaskPasses
    }

    It 'interprets terminating error as a build failure' {
        GivenAScript @'
throw 'fubar!'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheScriptRan
        ThenTheLastErrorMatches 'threw a terminating exception'
    }

    It 'fails build immediately when script''s error action is stop and it writes an error' {
        GivenAScript @'
$ErrorActionPreference = 'Stop'
Write-Error 'snafu!'
throw 'fubar'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheScriptRan
        ThenTheLastErrorMatches 'threw a terminating exception'
        ThenTheLastErrorDoesNotMatch 'fubar'
        ThenTheLastErrorDoesNotMatch 'failed, exited with code'
    }

    It 'fails build immediately when script does not complete successfully' {
        GivenAScript @'
Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'
Write-WhiskeyDebug ('ErrorActionPreference  {0}' -f $ErrorActionPreference)
Non-ExistingCmdlet -Name 'Test'
throw 'fubar'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheScriptRan
        ThenTheLastErrorMatches 'threw a terminating exception'
        ThenTheLastErrorDoesNotMatch 'fubar'
        ThenTheLastErrorDoesNotMatch 'failed, exited with code'
    }

    It 'checks that working directory exists' {
        GivenWorkingDirectory 'C:\I\Do\Not\Exist' -ThatDoesNotExist
        GivenAPassingScript
        WhenTheTaskRuns  -ErrorAction SilentlyContinue
        ThenTheTaskFails
    }

    It 'passes parameters positionally' {
        GivenNoWorkingDirectory
        GivenAScript @"
`$One | Set-Content -Path 'one.txt'
`$Two | Set-Content -Path 'two.txt'
"@ -WithParam @"
param(
    `$One,
    `$Two
)
"@
        WhenTheTaskRuns -WithArgument (@( 'fubar', 'snafu' ))
        ThenTheTaskPasses
        ThenTheScriptRan
        ThenFile 'one.txt' -HasContent 'fubar'
        ThenFile 'two.txt' -HasContent 'snafu'
    }

    It 'passes named parameters' {
        GivenNoWorkingDirectory
        GivenAScript @"
`$One | Set-Content -Path 'one.txt'
`$Two | Set-Content -Path 'two.txt'
"@ -WithParam @"
param(
    # Don't remove the [Parameter] attributes. Part of the test!
    [Parameter(Mandatory=`$true)]
    `$One,
    [Parameter(Mandatory=`$true)]
    `$Two
)
"@
        WhenTheTaskRuns -WithArgument @{ 'Two' = 'fubar'; 'One' = 'snafu' }
        ThenTheTaskPasses
        ThenTheScriptRan
        ThenFile 'one.txt' -HasContent 'snafu'
        ThenFile 'two.txt' -HasContent 'fubar'
    }

    It 'passes task context' {
        $emptyContext = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyContextObject'
        GivenAScript @"
exit 0
"@ -WithParam @"
param(
    # Don't remove the [Parameter] attributes. Part of the test!
    [Parameter(Mandatory)]
    [Whiskey.Context]`$TaskContext
)

    `$expectedMembers = & {
$(
    foreach( $memberName in $emptyContext | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty 'Name' )
    {
        "'{0}'`n" -f $memberName
    }
)
    }

    foreach( `$expectedMember in `$expectedMembers )
    {
        if( -not (`$TaskContext | Get-Member -Name `$expectedMember) )
        {
            throw ('TaskContext missing member "{0}".' -f `$expectedMember)
        }
    }

    if( `$TaskContext.Version -is [String] )
    {
        throw ('TaskContext.Version is a string instead of a [Whiskey.BuildVersion].')
    }

    if( `$TaskContext.BuildMetadata -is [String] )
    {
        throw ('TaskContext.BuildMetadata is a string instead of a [Whiskey.BuildInfo].')
    }
"@
        WhenTheTaskRuns
        ThenTheTaskPasses
    }

    It 'passes boolean values to switch parameters' {
        GivenAScript @"
if( -not `$SomeBool -or `$SomeOtherBool )
{
    throw
}
"@ -WithParam @"
param(
    [switch]`$SomeBool,

    [switch]`$SomeOtherBool
)
"@
        WhenTheTaskRuns -WithArgument @{ 'SomeBool' = 'true' ; 'SomeOtherBool' = 'false' }
        ThenTheTaskPasses
    }

    It 'passes common parameters' {
        GivenAScript @"
Write-Debug 'Fubar'
"@ -WithParam @"
[CmdletBinding()]
param(
)
"@
        WhenTheTaskRuns -WithArgument @{ }
        ThenTheTaskPasses
    }

   It 'runs in clean mode' {
        GivenAScript
        WhenTheTaskRuns -InCleanMode
        ThenTheTaskPasses
        ThenTheScriptRan
    }

    It 'runs in initialize mode' {
        GivenAScript
        WhenTheTaskRuns -InInitMode
        ThenTheTaskPasses
        ThenTheScriptRan
    }

    It 'requires Path or ScriptBlock property' {
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches ([regex]::Escape('Property "Path" or "ScriptBlock" is mandatory'))
    }

    It 'requires only one of Path and ScriptBlock property' {
        GivenAPassingScript
        GivenScriptBlock ''
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches ([regex]::Escape('Property "Path" or "ScriptBlock" is mandatory'))
    }

    It 'runs script blocks' {
        GivenScriptBlock @'
Set-Content -Path 'file.txt' -Value 'test content'
'@
        WhenTheTaskRuns
        ThenTheTaskPasses
        ThenFile 'file.txt' -HasContent 'test content'
    }

    It 'fails build when script block throws an exception' {
        GivenScriptBlock @'
throw 'script block failed'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches 'threw a terminating exception'
    }

    It 'passes parameters to script blocks' {
        GivenScriptBlock @'
param(
    $Content
)
Set-Content -Path 'file.txt' -Value $Content
'@
        WhenTheTaskRuns -WithArgument @{ Content = 'content from parameter' }
        ThenTheTaskPasses
        ThenFile 'file.txt' -HasContent 'content from parameter'
    }

    It 'passes task context to script block' {
        GivenScriptBlock @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Whiskey.Context]$TaskContext
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TaskContext') )
{
    throw 'TaskContext not passed to scriptblock!'
}
'@
        WhenTheTaskRuns
        ThenTheTaskPasses
    }

    It 'runs a script block by default' {
        GivenNoWorkingDirectory
        WhenTheTaskRuns -WithDefaultProperty 'Write-Warning "ranme!"' -WarningVariable 'warnings'
        ThenTheTaskPasses
        $warnings | Should -Be 'ranme!'
    }

}
