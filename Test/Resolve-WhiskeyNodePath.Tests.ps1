
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$resolvedPath = $null

function Init
{
    $Global:Error.Clear()
    $script:resolvedPath = $null
}

function GivenNodeInstalled
{
    Install-Node
}

function ThenError
{
    param(
        [String]$Matches
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Matches
    }
}

function ThenPathIsNotResolved
{
    param(
    )

    It ('should resolve path') {
        $resolvedPath | Should -BeNullOrEmpty
    }
}

function ThenPathIsResolved
{
    param(
    )

    $nodeRoot = Join-Path -Path $TestDrive.FullName -ChildPath '.node'
    if( $IsWindows )
    {
        $nodePath = Join-Path -Path $nodeRoot -ChildPath 'node.exe'
    }
    else
    {
        $nodePath = Join-Path -Path $nodeRoot -ChildPath 'bin/node'
    }

    It ('should resolve path') {
        $resolvedPath | Should -Be $nodePath
    }
}

function WhenResolving
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='WithBuildRoot')]
        [String]$BuildRootPath,

        [Parameter(Mandatory,ParameterSetName='WithNodeRoot')]
        [String]$NodeRootPath
    )

    if( $BuildRootPath )
    {
        $script:resolvedPath = Resolve-WhiskeyNodePath -BuildRootPath $BuildRootPath
    }

    if( $NodeRootPath )
    {
        $script:resolvedPath = Resolve-WhiskeyNodePath -NodeRootPath $NodeRootPath
    }
}

Describe 'Resolve-WhiskeyNodePath.when resolving from build root' {
    try
    {
        Init
        GivenNodeInstalled
        WhenResolving -BuildRootPath $TestDrive.FullName
        ThenPathIsResolved
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodePath.when resolving from a Node root' {
    try
    {
        Init
        GivenNodeInstalled
        WhenResolving -NodeRootPath (Join-Path -Path $TestDrive.FullName -ChildPath '.node')
        ThenPathIsResolved
    }
    finally
    {
        Remove-Node
    }
}


Describe 'Resolve-WhiskeyNodePath.when resolving from a relative build root' {
    Push-Location $TestDrive.FullName
    try
    {
        Init
        GivenNodeInstalled
        WhenResolving -BuildRootPath '.'
        ThenPathIsResolved
    }
    finally
    {
        Pop-Location
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodePath.when resolving from a relative Node root' {
    Push-Location $TestDrive.FullName
    try
    {
        Init
        GivenNodeInstalled
        WhenResolving -NodeRootPath '.node'
        ThenPathIsResolved
    }
    finally
    {
        Pop-Location
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodePath.when Node doesn''t exist in Node root' {
    try
    {
        Init
        WhenResolving -NodeRootPath (Join-Path -Path $TestDrive.FullName -Childpath '.node') -ErrorAction SilentlyContinue
        ThenPathIsNotResolved
        ThenError -Matches 'doesn''t exist'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodePath.when Node doesn''t exist in build root' {
    try
    {
        Init
        WhenResolving -BuildRootPath $TestDrive.FullName -ErrorAction SilentlyContinue
        ThenPathIsNotResolved
        ThenError -Matches 'doesn''t exist'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodePath.when ignoring errors' {
    try
    {
        Init
        WhenResolving -BuildRootPath $TestDrive.FullName -ErrorAction Ignore
        ThenPathIsNotResolved
        ThenError -IsEmpty
    }
    finally
    {
        Remove-Node
    }
}

