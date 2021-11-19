
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
$testRoot = $null

function Init
{
    param(
        [switch]$SkipInstall
    )

    $script:failed = $false
    $script:testRoot = New-WhiskeyTestRoot
    if( -not $SkipInstall )
    {
        Install-Node -BuildRoot $script:testRoot
    }
}

function ThenFile
{
    param(
        $Named,
        $Is
    )

    $path = Join-Path -Path $script:testRoot -ChildPath $Named
    $path | Should -Exist
    $path | Should -FileContentMatchMultiline $Is
}

function ThenTaskFails
{
    param(
        $WithError
    )

    $failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $WithError } | Should -Not -BeNullOrEmpty
}

function ThenTaskSucceeds
{
    param(
    )

    $failed | Should -BeFalse
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
                        

    $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $script:testRoot
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
    It 'should not fail the build' {
        Init -SkipInstall
        WhenRunningCommand 'config' -WithArguments 'set','fubar','snafu','--userconfig','.npmrc'
        ThenFile '.npmrc' -Is @'
fubar=snafu
'@
    }
}

Describe 'Npm.when command fails' {
    It 'should fail the build' {
        Init
        $configPath = (Get-Item -Path $PSScriptRoot).PSDrive.Root
        $configPath = Join-Path -Path $configPath -ChildPath ([IO.Path]::GetRandomFileName())
        $configPath = Join-Path -Path $configPath -ChildPath ([IO.Path]::GetRandomFileName())
        WhenRunningCommand 'k4bphelohjx' -ErrorAction SilentlyContinue
        ThenTaskFails -WithError 'NPM\ command\ "npm\ k4bphelohjx.*"\ failed\ with\ exit\ code\ '
    }
}

Describe 'Npm.when command not given' {
    It 'should fail' {
        Init
        WhenRunningCommand -ErrorAction SilentlyContinue
        ThenTaskFails -WithError 'Property\ "Command\" is required'
    }
}

Describe 'Npm.when command has no arguments' {
    It 'should not fail' {
        Init
        WhenRunningCommand 'version'
        ThenTaskSucceeds
    }
}