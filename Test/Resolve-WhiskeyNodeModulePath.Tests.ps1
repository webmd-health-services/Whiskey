
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$resolvedPath = $null

function Init
{
    $Global:Error.Clear()
    $script:resolvedPath = $null
}

function GivenNodeModuleInstalled
{
    param(
        $Name,

        [Switch]
        $Global
    )

    $nodeModulesPath = $TestDrive.FullName
    if( $Global )
    {
        $nodeModulesPath = Join-Path -Path $nodeModulesPath -ChildPath '.node'
        if( -not $IsWindows )
        {
            $nodeModulesPath = Join-Path -Path $nodeModulesPath -ChildPath 'lib'
        }
    }

    $nodeModulesPath = Join-Path -Path $nodeModulesPath -ChildPath 'node_modules'
        
    $modulePath = Join-Path -Path $nodeModulesPath -ChildPath $Name
    New-Item -Path $modulePath -ItemType 'Directory' -Force
}

function ThenError
{
    param(
        [string]
        $Matches
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

function ThenPathIsGlobal
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Name
    )

    $nodeRoot = Join-Path -Path $TestDrive.FullName -ChildPath '.node'
    if( $IsWindows )
    {
        $nodePath = Join-Path -Path $nodeRoot -ChildPath 'node_modules'
    }
    else
    {
        $nodePath = Join-Path -Path $nodeRoot -ChildPath 'lib/node_modules'
    }
    $nodePath = Join-Path -Path $nodePath -ChildPath $Name


    It ('should resolve path') {
        $resolvedPath | Should -Be $nodePath
    }
}


function ThenPathIsLocal
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Name
    )

    It ('should resolve path') {
        $resolvedPath | Should -Be (Join-Path -Path $TestDrive.FullName -ChildPath ('node_modules\{0}' -f $Name))
    }
}

function WhenResolving
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]
        $Name,

        [Parameter(Mandatory,ParameterSetName='WithBuildRoot')]
        [string]
        $BuildRootPath,

        [Parameter(ParameterSetName='WithBuildRoot')]
        [Switch]
        $Global,

        [Parameter(Mandatory,ParameterSetName='WithNodeRoot')]
        [string]
        $NodeRootPath
    )

    if( $BuildRootPath )
    {
        $script:resolvedPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $BuildRootPath -Global:$Global
    }

    if( $NodeRootPath )
    {
        $script:resolvedPath = Resolve-WhiskeyNodeModulePath -Name $Name -NodeRootPath $NodeRootPath
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when resolving from build root' {
    try
    {
        Init
        GivenNodeModuleInstalled 'fubar'
        WhenResolving 'fubar' -BuildRootPath $TestDrive.FullName
        ThenPathIsLocal 'fubar'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when resolving global node modules directory from build root' {
    try
    {
        Init
        GivenNodeModuleInstalled 'fubar' -Global
        WhenResolving 'fubar'-BuildRootPath $TestDrive.FullName -Global
        ThenPathIsGlobal 'fubar'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when resolving from a Node root' {
    try
    {
        Init
        GivenNodeModuleInstalled 'fubar' -Global
        WhenResolving 'fubar' -NodeRootPath (Join-Path -Path $TestDrive.FullName -ChildPath '.node')
        ThenPathIsGlobal 'fubar'
    }
    finally
    {
        Remove-Node
    }
}


Describe 'Resolve-WhiskeyNodeModulePath.when resolving from a relative build root' {
    Push-Location $TestDrive.FullName
    try
    {
        Init
        GivenNodeModuleInstalled 'fubar'
        WhenResolving 'fubar' -BuildRootPath '.'
        ThenPathIsLocal 'fubar'
    }
    finally
    {
        Pop-Location
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when resolving from a relative Node root' {
    Push-Location $TestDrive.FullName
    try
    {
        Init
        GivenNodeModuleInstalled 'fubar' -Global
        WhenResolving 'fubar' -NodeRootPath '.node'
        ThenPathIsGlobal 'fubar'
    }
    finally
    {
        Pop-Location
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when Node doesn''t exist in Node root' {
    try
    {
        Init
        WhenResolving 'fubar' -NodeRootPath (Join-Path -Path $TestDrive.FullName -Childpath '.node') -ErrorAction SilentlyContinue
        ThenPathIsNotResolved
        ThenError -Matches 'doesn''t exist'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when Node doesn''t exist in build root' {
    try
    {
        Init
        WhenResolving 'fubar' -BuildRootPath $TestDrive.FullName -ErrorAction SilentlyContinue
        ThenPathIsNotResolved
        ThenError -Matches 'doesn''t exist'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Resolve-WhiskeyNodeModulePath.when ignoring errors' {
    try
    {
        Init
        WhenResolving 'fubar' -BuildRootPath $TestDrive.FullName -ErrorAction Ignore
        ThenPathIsNotResolved
        ThenError -IsEmpty
    }
    finally
    {
        Remove-Node
    }
}

