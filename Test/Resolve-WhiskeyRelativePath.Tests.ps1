4
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$script:testRoot = ''
$script:testContext = ''

function GivenDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Path
    )

    New-Item -Path (Join-Path -Path $script:testRoot -ChildPath $Path) -ItemType 'Directory' -Force
}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:testContext = New-WhiskeyTestContext -ForBuildRoot $script:testRoot -ForBuildServer
}

function Merge-Path
{
    [CmdletBinding()]
    param(
        [String[]] $Path
    )

    $result = ''
    foreach( $item in $Path )
    {
        if( -not $result )
        {
            $result = $item
            continue
        }

        $result = Join-Path -Path $result -ChildPath $item
    }
    return $result
}

function ThenPathIs
{
    [CmdletBinding()]
    param(
        [String[]] $Path
    )

    $result | Should -Be (Merge-Path $Path)
}

function WhenResolving
{
    [CmdletBinding()]
    param(
        [String[]] $Path,

        [String] $In
    )

    $context = $script:testContext
    Mock -CommandName 'Get-WhiskeyContext' -ModuleName 'Whiskey' -MockWith { return $context }.GetNewClosure()

    $pathArg = Merge-Path $Path

    if( $In )
    {
        Push-Location -Path (Join-Path -Path $script:testRoot -ChildPath $In)
    }

    try
    {
        $script:result = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyRelativePath' -Parameter @{ 'Path' = $pathArg }
    }
    finally
    {
        if( $In )
        {
            Pop-Location
        }
    }
}

Describe 'Resolve-WhiskeyRelativePath.when current directory is build root and path does not exist' {
    It 'should return relative path' {
        Init
        WhenResolving @($script:testRoot, 'dir1','dir2','dir3','dir4') -In '.'
        ThenPathIs @('.', 'dir1', 'dir2', 'dir3', 'dir4')
    }
}

Describe 'Resolve-WhiskeyRelativePath.when current directory is not build root and path does not exist' {
    It 'should return absolute path' {
        Init
        GivenDirectory 'dir5\dir6'
        WhenResolving @($script:testRoot, 'dir7', 'dir8') -In 'dir5\dir6'
        ThenPathIs @($script:testRoot, 'dir7', 'dir8')
    }
}

Describe 'Resolve-WhiskeyRelativePath.when resolving relative path from build root' {
    It 'should return path relative to build root' {
        Init
        WhenResolving @('dir9', 'dir10') -In '.'
        ThenPathIs @('.', 'dir9', 'dir10')
    }
}

Describe 'Resolve-WhiskeyRelativePath.when resolving relative path from outside build root' {
    It 'should return path relative to build root' {
        Init
        WhenResolving @('dir11', 'dir12')
        ThenPathIs @($script:testRoot, 'dir11', 'dir12')
    }
}
