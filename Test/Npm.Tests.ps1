
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false

function Init
{
    $script:failed = $false
}

function ThenFile
{
    param(
        $Named,
        $Is
    )

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $Named

    It ('should run command') {
        $path | Should -Exist
        $path | Should -FileContentMatchMultiline $Is
    }
}

function ThenTaskFails
{
    param(
        $WithError
    )

    It ('should fail') {
        $failed | Should -BeTrue
        $Global:Error | Where-Object { $_ -match $WithError } | Should -Not -BeNullOrEmpty
    }
}

function ThenTaskSucceeds
{
    param(
    )

    It ('should succeed') {
        $failed | Should -BeFalse
    }
}

function WhenRunningCommand
{
    [CmdletBinding()]
    param(
        $Name,
        $WithArguments
    )

    $parameters = @{ }
    if( $Name )
    {
        $parameters['Command'] = $Name
    }

    if( $WithArguments )
    {
        $parameters['Argument'] = $WithArguments
    }
                        

    $context = New-WhiskeyTestContext -ForBuildServer
    $script:failed = $false

    try
    {
        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Name 'Npm' -Parameter $parameters
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Npm.when command succeeds' {
    try
    {
        Init
        WhenRunningCommand 'config' -WithArguments 'set','fubar','snafu','--userconfig','.npmrc'
        ThenFile '.npmrc' -Is @'
fubar=snafu
'@
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Npm.when command fails' {
    try
    {
        Init
        WhenRunningCommand 'config' -WithArguments 'set','fubar','snafu','--userconfig','\\server\share\does\not\exist' -ErrorAction SilentlyContinue
        ThenTaskFails -WithError 'NPM\ command\ ''npm config\b.*\ failed\ with\ exit\ code\ '
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Npm.when command not given' {
    try
    {
        Init
        WhenRunningCommand
        ThenTaskFails -WithError 'Property\ "Command\" is required'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Npm.when command has no arguments' {
    try
    {
        Init
        WhenRunningCommand 'install'
        ThenTaskSucceeds
    }
    finally
    {
        Remove-Node
    }
}