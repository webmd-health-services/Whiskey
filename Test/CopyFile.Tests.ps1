
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$taskFailed = $false
$taskException = $null

function Get-BuildRoot
{
    $buildRoot = Join-Path -Path $testRoot -ChildPath 'Source'
    if( -not (Test-Path -Path $buildRoot -PathType Container) )
    {
        New-Item -Path $buildRoot -ItemType 'Directory' | Out-Null
    }
    return $buildRoot
}

function Get-DestinationRoot
{
    Join-Path -Path $testRoot -ChildPath 'Destination'
}

function GivenFiles
{
    param(
        [string[]]$Path
    )

    $sourceRoot = Get-BuildRoot
    foreach( $item in $Path )
    {
        New-Item -Path (Join-Path -Path $sourceRoot -ChildPath $item) -ItemType 'File' -Force | Out-Null
    }
}

function GivenNoFilesToCopy
{
}

function GivenDirectories
{
    param(
        [string[]]$Path
    )

    foreach( $item in $Path )
    {
        if( -not ([IO.Path]::IsPathRooted($item)) )
        {
            $item = Join-Path -Path $testRoot -ChildPath $item
        }
        New-Item -Path $item -ItemType 'Directory' -Force | Out-Null
    }
}

function GivenUserCannotCreateDestination
{
    param(
        [string[]]$To
    )

    $destinationRoot = Get-BuildRoot
    foreach( $item in $To )
    {
        $destinationPath = Join-Path -Path $destinationRoot -ChildPath $item
        Mock -CommandName 'New-Item' `
             -ModuleName 'Whiskey' `
             -MockWith { Write-Error ('Access to the path ''{0}'' is denied.' -f $item) -ErrorAction SilentlyContinue }.GetNewClosure() `
             -ParameterFilter ([scriptblock]::Create("`$Path -eq '$destinationPath'"))
    }
}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
}

function WhenCopyingFiles
{
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string[]]$Path,

        [string[]]$To
    )

    $taskContext = New-WhiskeyTestContext -ForBuildServer

    $taskParameter = @{ }
    $taskParameter['Path'] = $Path

    if( -not $To )
    {
        $To = Get-BuildRoot
    }
    $taskParameter['DestinationDirectory'] = $To

    $taskContext.BuildRoot = Get-BuildRoot
    $Script:taskFailed = $false
    $Script:taskException = $null

    try
    {
        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'CopyFile'
    }
    catch
    {
        $Script:taskException = $_
        $Script:taskFailed = $true
    }
}

function ThenNothingCopied
{
    param(
        [string[]]$To
    )

    $destinationRoot = Get-DestinationRoot
    foreach( $item in $To )
    {
        $fullPath = Join-Path -Path $destinationRoot -ChildPath $item 
        if( (Test-Path -Path $fullPath -PathType Container) )
        {
            Get-ChildItem -Path $fullPath | Should -BeNullOrEmpty
        }
    }
}

function ThenFilesCopied
{
    param(
        [string[]]$Path,

        [string[]]$To
    )

    if( -not $To )
    {
        $To = Get-BuildRoot
    }
    else
    {
        $To = $To | ForEach-Object { 
            if( [IO.Path]::IsPathRooted($_) )
            {
                return $_
            }
            Join-Path -Path (Get-BuildRoot) -ChildPath $_ 
        }
    }

    foreach( $item in $Path )
    {
        foreach( $destItem in $To )
        {
            Join-Path -Path $To -ChildPath $item  |
                Get-Item |
                Should -Not -BeNullOrEmpty
        }
    }
}

function ThenTaskFails
{
    param(
        $WithErrorMessage
    )

    $Script:taskFailed | Should -BeTrue
    $Script:taskException | Should -Match $WithErrorMessage
}

Describe 'CopyFile.when given a single file' {
    It 'should copy that file' {
        Init
        GivenFiles 'one.txt'
        WhenCopyingFiles 'one.txt' -To 'Destination'
        ThenFilesCopied 'one.txt' -To 'Destination'
    }
}

Describe 'CopyFile.when given multiple files to a single destination' {
    It 'should copy multiple files' {
        Init
        GivenFiles 'one.txt','two.txt'
        WhenCopyingFiles 'one.txt','two.txt' -To 'Destination'
        ThenFilesCopied 'one.txt','two.txt' -To 'Destination'
    }
}

Describe 'CopyFile.when given files from different directories' {
    It 'it should copy files from different source directories' {
        Init
        GivenFiles 'dir1\one.txt','dir2\two.txt'
        WhenCopyingFiles 'dir1\one.txt','dir2\two.txt' -To 'Destination'
        ThenFilesCopied 'one.txt','two.txt' -To 'Destination'
    }
}

Describe 'CopyFile.when given multiple destinations' {
    It 'should copy to the multiple destinations' {
        Init
        GivenFiles 'one.txt'
        WhenCopyingFiles 'one.txt' -To 'dir1','dir2'
        ThenFilesCopied 'one.txt' -To 'dir1','dir2'
    }
}

Describe 'CopyFile.when user can''t create one of the destination directories' {
    It 'should fail' {
        Init
        GivenFiles 'one.txt'
        GivenUserCannotCreateDestination 'dir2'
        WhenCopyingFiles 'one.txt' -To 'dir1','dir2' -ErrorAction SilentlyContinue
        ThenTaskFails -WithErrorMessage 'Failed to create destination directory'
        ThenNothingCopied -To 'dir1','dir2'
    }
}

Describe 'CopyFile.when given no files' {
    It 'should fail' {
        Init
        GivenNoFilesToCopy
        WhenCopyingFiles -ErrorAction SilentlyContinue
        ThenTaskFails -WithErrorMessage '''Path'' property is missing'
        ThenNothingCopied
    }
}

Describe 'CopyFile.when given a directory' {
    It 'it should fail' {
        Init
        GivenFiles 'dir1\file1.txt'
        WhenCopyingFiles 'dir1' -ErrorAction SilentlyContinue
        ThenTaskFails 'only copies files'
        ThenNothingCopied
    }
}

Describe 'CopyFile.when destination directory contains wildcards' {
    It 'should copy files to destinations that  match the wildcard' {
        Init
        GivenFiles 'file1.txt'
        GivenDirectories 'Destination','OtherDestination','Destination2'
        WhenCopyingFiles 'file1.txt' -To '..\Dest*'
        ThenFilesCopied 'file1.txt'
        ThenFilesCopied 'file1.txt' -To '..\Destination2','..\Destination'
        ThenNothingCopied -To '..\OtherDestination'
    }
}

Describe 'CopyFile.when destination directory contains wildcards and doesn''t exist' {
    It 'should fail' {
        Init
        GivenFiles 'file1.txt'
        WhenCopyingFiles 'file1.txt' -To '..\Dest*'
        ThenTaskFails -WithErrorMessage 'Wildcard\ pattern\ "\.\.\\Dest\*"\ doesn''t'
    }
}

Describe 'CopyFile.when destination directory is an absolute path inside the build root' {
    It 'it should still copy the file' {
        Init
        GivenFiles 'file1.txt'
        $destination = Join-Path -Path $testRoot -ChildPath 'Absolute'
        GivenDirectories $destination
        WhenCopyingFiles 'file1.txt' -To $destination
        ThenFilesCopied 'file1.txt' -To $destination
    }
}
