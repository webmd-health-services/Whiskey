
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$workingDirectory = $null
$failed = $false
$scriptBlock = $null
$scriptName = $null

function Get-OutputFilePath
{
    $path = (Join-Path -Path $testRoot -ChildPath ('{0}\run' -f $workingDirectory))
    if( -not [IO.Path]::IsPathRooted($path) )
    {
        $path = Join-Path -Path $testRoot -ChildPath $path
    }
    return $path
}

function GivenAFailingScript
{
    GivenAScript 'exit 1'
}

function GivenAPassingScript
{
    GivenAScript ''
}

function GivenAScript
{
    param(
        [Parameter(Position=0)]
        [String]$Script,

        [String]$WithParam = 'param([Parameter(Mandatory)][Object]$TaskContext)'
    )

    $script:scriptName = 'myscript.ps1'
    $scriptPath = Join-Path -Path $testRoot -ChildPath $scriptName

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

    $absoluteWorkingDir = $workingDirectory
    if( -not [IO.Path]::IsPathRooted($absoluteWorkingDir) )
    {
        $absoluteWorkingDir = Join-Path -Path $testRoot -ChildPath $absoluteWorkingDir
    }

    if( -not $ThatDoesNotExist -and -not (Test-Path -Path $absoluteWorkingDir -PathType Container) )
    {
        New-Item -Path $absoluteWorkingDir -ItemType 'Directory'
    }

}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:failed = $false
    $script:scriptBlock = $null
    $script:scriptName = $null
    $script:workingDirectory = $null
}
function ThenFile
{
    param(
        $Path,
        $HasContent
    )

    $fullpath = Join-Path -Path $testRoot -ChildPath $Path
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
    $failed | Should -BeTrue
}

function ThenTheTaskPasses
{
    $failed | Should -BeFalse
    $Global:Error | Should -BeNullOrEmpty
}


function WhenTheTaskRuns
{
    [CmdletBinding()]
    param(
        [Object]$WithArgument,

        [switch]$InCleanMode,

        [switch]$InInitMode
    )

    $context = New-WhiskeyTestContext -ForDeveloper `
                                      -InCleanMode:$InCleanMode `
                                      -InInitMode:$InInitMode `
                                      -ForBuildRoot $testRoot

    $taskParameter = @{}

    if( $scriptName )
    {
        $taskParameter['Path'] = @( $scriptName )

        Get-Content -Path (Join-Path -Path $testRoot -ChildPath $scriptName) -Raw |
            Write-WhiskeyDebug -Context $context
    }

    if( $null -ne $scriptBlock )
    {
        $taskParameter['ScriptBlock'] = $scriptBlock
        $scriptBlock | Write-WhiskeyDebug -Context $context
    }

    if( $workingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $workingDirectory
    }

    if( $WithArgument )
    {
        $taskParameter['Argument'] = $WithArgument
    }

    $failed = $false

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

Describe 'PowerShell.when script passes' {
    It 'should pass build' {
        Init
        GivenAPassingScript
        GivenNoWorkingDirectory
        WhenTheTaskRuns
        ThenTheScriptRan
        ThenTheTaskPasses
    }
}

Describe 'PowerShell.when script fails due to non-zero exit code' {
    It 'should fail build' {
        Init
        GivenNoWorkingDirectory
        GivenAFailingScript
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheScriptRan
        ThenTheTaskFails
        ThenTheLastErrorMatches 'failed, exited with code'
    }
}

Describe 'PowerShell.when script passes after a previous command fails' {
    It 'should pass' {
        Init
        GivenNoWorkingDirectory
        GivenAPassingScript
        GivenLastExitCode 1
        WhenTheTaskRuns
        ThenTheScriptRan
        ThenTheTaskPasses
    }
}

Describe 'PowerShell.when script throws a terminating exception' {
    It 'should fail build' {
        Init
        GivenAScript @'
throw 'fubar!'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheScriptRan
        ThenTheLastErrorMatches 'threw a terminating exception'
    }
}

Describe 'PowerShell.when script''s error action preference is Stop' {
    It 'should fail build' {
        Init
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
}

Describe 'PowerShell.when script''s error action preference is Stop and script doesn''t complete successfully' {
    It 'should fail' {
        Init
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
}

Describe 'PowerShell.when working directory does not exist' {
    It 'should fail' {
        Init
        GivenWorkingDirectory 'C:\I\Do\Not\Exist' -ThatDoesNotExist
        GivenAPassingScript
        WhenTheTaskRuns  -ErrorAction SilentlyContinue
        ThenTheTaskFails
    }
}

Describe 'PowerShell.when passing positional parameters' {
    It 'should pass parameters' {
        Init
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
}

Describe 'PowerShell.when passing named parameters' {
    It 'should pass named parameters' {
        Init
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
}

Describe 'PowerShell.when script has TaskContext parameter' {
    It 'should pass context to script' {
        Init
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
}

Describe 'PowerShell.when script has Switch parameter' {
    It 'should pass as boolean' {
        Init
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

}

Describe 'PowerShell.when script has a common parameter that isn''t an argument' {
    It 'should pass' {
        Init
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
}

Describe 'PowerShell.when run in Clean mode' {
   It 'should run' {
       Init
        GivenAScript
        WhenTheTaskRuns -InCleanMode
        ThenTheTaskPasses
        ThenTheScriptRan
    }
}

Describe 'PowerShell.when run in Initialize mode' {
    It 'should run' {
        Init
        GivenAScript
        WhenTheTaskRuns -InInitMode
        ThenTheTaskPasses
        ThenTheScriptRan
    }
}

Describe 'PowerShell.when missing required properties' {
    It 'should fail' {
        Init
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches ([regex]::Escape('Missing required property. Task must use one of "Path" or "ScriptBlock".'))
    }
}

Describe 'PowerShell.when given both Path and ScriptBlock properties' {
    It 'should fail' {
        Init
        GivenAPassingScript
        GivenScriptBlock ''
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches ([regex]::Escape('Task uses both "Path" and "ScriptBlocK" properties. Only one of these properties is allowed.'))
    }
}

Describe 'PowerShell.when given ScriptBlock' {
    It 'should run the script block' {
        Init
        GivenScriptBlock @'
Set-Content -Path 'file.txt' -Value 'test content'
'@
        WhenTheTaskRuns
        ThenTheTaskPasses
        ThenFile 'file.txt' -HasContent 'test content'
    }
}

Describe 'PowerShell.when given ScriptBlock fails' {
    It 'should fail' {
        Init
        GivenScriptBlock @'
throw 'script block failed'
'@
        WhenTheTaskRuns -ErrorAction SilentlyContinue
        ThenTheTaskFails
        ThenTheLastErrorMatches 'threw a terminating exception'
    }
}

Describe 'PowerShell.when passing parameters to ScriptBlock' {
    It 'should pass the parameters' {
        Init
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
}

Describe 'PowerShell.when passing TaskContext to ScriptBlock' {
    It 'should pass TaskContext to ScriptBlock' {
        Init
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
}
