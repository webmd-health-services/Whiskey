
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$path = $null
$runMode = $null

function GivenClean
{
    $script:runMode = 'Clean'
}

function GivenItem
{
    param(
        [String[]]$Path,
        
        [ValidateSet('File','Directory')]
        $ItemType,

        [switch]$ReadOnly
    )

    foreach( $item in $Path )
    {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $item
        New-Item -Path $fullPath -Force -ItemType $ItemType
        if( $ReadOnly )
        {
            (Get-Item -Path $fullPath).IsReadOnly = $true
        }
    }
}

function GivenPath
{
    param(
        [String[]]$Path
    )

    $script:path = $Path
}

function Init
{
    $script:path = $null
    $script:runMode = $null
}

function ThenItemDoesNotExist
{
    param(
        [String[]]$Path
    )
    
    foreach( $item in $Path )
    {
        It ('should delete ''{0}''' -f $item) {
            Join-Path -Path $TestDrive.FullName -ChildPath $item | Should -Not -Exist
        }
    }
}

function ThenItemExists
{
    param(
        [String[]]$Path
    )

    foreach( $item in $Path )
    {
        It ('should not delete ''{0}''' -f $item) {
            Join-Path -Path $TestDrive.FullName -ChildPath $item | Should -Exist
        }
    }
}

function ThenThereAreNoErrors
{
    It ('should not write any errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function WhenDeleting
{
    $Global:Error.Clear()
    $context = New-WhiskeyTestContext -ForBuildServer

    if ($runMode)
    {
        $context.RunMode = $runMode
    }

    Invoke-WhiskeyTask -TaskContext $context -Name 'Delete' -Parameter @{ Path = $path }
}

Describe 'Delete.when run in Clean mode and item is a file' {
    Init
    GivenClean
    GivenItem 'dir1\file.txt' -ItemType 'File'
    GivenPath 'dir1\file.txt'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt'
}

Describe 'Delete.when item is a file' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File'
    GivenPath 'dir1\file.txt'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt'
}

Describe 'Delete.when item is a read-only file' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File' -ReadOnly
    GivenPath 'dir1\file.txt'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt'
}

Describe 'Delete.when item is adirectory' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File' -ReadOnly
    GivenPath 'dir1'
    WhenDeleting
    ThenItemDoesNotExist 'dir1'
}

Describe 'Delete.when file does not exist' {
    Init
    GivenPath 'somefile'
    WhenDeleting
    ThenItemDoesNotExist 'somefile'
    ThenThereAreNoErrors
}

Describe 'Delete.when deleting a file and a directory' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File'
    GivenItem 'dir2\file.txt' -ItemType 'File'
    GivenPath 'dir1\file.txt','dir2'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt','dir2'
}

Describe 'Delete.when deleting a using wildcards' {
    Init
    GivenItem 'file.txt' -ItemType 'File'
    GivenItem 'file.json' -ItemType 'File'
    GivenPath '*.txt'
    WhenDeleting
    ThenItemDoesNotExist 'file.txt'
    ThenItemExists 'file.json'
}

Describe 'Delete.when wildcards match multiple paths' {
    Init
    GivenItem 'Production\Source\Dir1\Bin' -ItemType 'Directory'
    GivenItem 'Production\Source\Dir2\Bin' -ItemType 'Directory'
    GivenItem 'Production\Source\Dir2\NotBin' -ItemType 'Directory'
    GivenPath 'Production\Source\*\Bin'
    WhenDeleting
    ThenItemDoesNotExist 'Production\Source\Dir1\Bin'
    ThenItemDoesNotExist 'Production\Source\Dir2\Bin'
    ThenItemExists 'Production\Source\Dir2\NotBin'
}
