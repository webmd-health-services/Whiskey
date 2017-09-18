
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$path = $null

function GivenItem
{
    param(
        [string[]]
        $Path,
        
        [ValidateSet('File','Directory')]
        $ItemType,

        [Switch]
        $ReadOnly
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
        [string[]]
        $Path
    )

    $script:path = $Path
}

function Init
{
    $script:path = $null
}

function ThenItemDoesNotExist
{
    param(
        [string[]]
        $Path
    )

    It 'should delete' {
        foreach( $item in $Path )
        {
            Join-Path -Path $TestDrive.FullName -ChildPath $item | Should -Not -Exist
        }
    }
}

function ThenItemExists
{
    param(
        [string[]]
        $Path
    )

    It 'should not delete' {
        foreach( $item in $Path )
        {
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
    Invoke-WhiskeyTask -TaskContext $context -Name 'Delete' -Parameter @{ Path = $path }
}

Describe 'Remove-WhiskeyItem.when item is a file' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File'
    GivenPath 'dir1\file.txt'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt'
}

Describe 'Remove-WhiskeyItem.when item is a read-only file' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File' -ReadOnly
    GivenPath 'dir1\file.txt'
    WhenDeleting
    ThenItemDoesNotExist 'dir1\file.txt'
}

Describe 'Remove-WhiskeyItem.when item is adirectory' {
    Init
    GivenItem 'dir1\file.txt' -ItemType 'File' -ReadOnly
    GivenPath 'dir1'
    WhenDeleting
    ThenItemDoesNotExist 'dir1'
}

Describe 'Remove-WhiskeyItem.when file does not exist' {
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