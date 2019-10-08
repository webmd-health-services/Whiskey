& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function GivenFileOrDirectory
{
    param(
        $Path,

        [switch]$Directory
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    if( $Directory )
    {
        New-Item -Path $fullPath -ItemType 'Directory' -Force | Out-Null
    }
    else
    {
        New-Item -Path $fullPath -ItemType 'File' -Force | Out-Null
    }
}

function WhenRemovingFileOrDirectory
{
    [CmdletBinding()]
    param(
        $Path,

        [switch]$Piped
    )

    $Global:Error.Clear()
    $Global:Path = $Path
    if( $Piped )
    {
        InModuleScope 'Whiskey' { ($Global:Path | Remove-WhiskeyFileSystemItem) }
    }
    else
    {
        InModuleScope 'Whiskey' { & Remove-WhiskeyFileSystemItem -Path $Global:Path }
    }
    Remove-Variable -Name 'Path' -Scope 'Global'
}

function ThenFileOrDirectoryShouldNotExist
{
    param(
        $Path
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    $fullPath | Should -Not -Exist
}

function ThenFileOrDirectoryShouldExist
{
    param(
        $Path
    )
    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    $fullPath | Should -Exist
}

function ThenShouldThrowErrors
{
    param(
        $ExpectedError
    )
    $Global:Error | Should -Not -beNullOrEmpty

    if( $ExpectedError )
    {
        $Global:Error[0] | Should -Match $ExpectedError
    }
}

function ThenRanSuccessfully
{
    $Global:Error[0] | Should -beNullOrEmpty
}


Describe 'Remove-WhiskeyFileSystemItem.when given a valid file' {
    It 'should remove the file' {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath 'file.txt'
        GivenFileOrDirectory -Path 'file.txt'
        WhenRemovingFileOrDirectory -Path $fullPath 
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid files' {
    It 'should remove all files' {
        GivenFileOrDirectory -Path 'file.txt'
        GivenFileOrDirectory -Path 'file1.txt'
        GivenFileOrDirectory -Path 'file2.txt'
        $pathList = @(
            (Join-Path -Path $TestDrive.FullName -ChildPath 'file.txt'),
            (Join-Path -Path $TestDrive.FullName -ChildPath 'file1.txt'),
            (Join-Path -Path $TestDrive.FullName -ChildPath 'file2.txt')
        )
        WhenRemovingFileOrDirectory -Path $pathList -Piped
        ThenFileOrDirectoryShouldNotExist -Path 'file.txt'
        ThenFileOrDirectoryShouldNotExist -Path 'file2.txt'
        ThenFileOrDirectoryShouldNotExist -Path 'file3.txt'
        ThenRanSuccessfully

    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid directory' {
    It 'should remove the directory' {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath 'dir'
        GivenFileOrDirectory -Path 'dir' -Directory
        WhenRemovingFileOrDirectory -Path $fullPath
        ThenFileOrDirectoryShouldNotExist 'dir'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid directories' {
    It 'should remove all directories' {
        GivenFileOrDirectory -Path 'dir' -Directory
        GivenFileOrDirectory -Path 'dir1' -Directory
        GivenFileOrDirectory -Path 'dir2' -Directory
        $pathList = @(
            (Join-Path -Path $TestDrive.FullName -ChildPath 'dir'),
            (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'),
            (Join-Path -Path $TestDrive.FullName -ChildPath 'dir2')
        )
        WhenRemovingFileOrDirectory -Path $pathList -Piped
        ThenFileOrDirectoryShouldNotExist -Path 'dir'
        ThenFileOrDirectoryShouldNotExist -Path 'dir1'
        ThenFileOrDirectoryShouldNotExist -Path 'dir2'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a file that doesn''t exist' {
    It 'should throw errors' {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath 'file.txt'
        WhenRemovingFileOrDirectory -Path $fullPath -ErrorAction SilentlyContinue
        ThenShouldThrowErrors -ExpectedError 'Could\ not\ find'
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid files and one that doesn''t exist' {
    It 'should remove all valid files and throw an error' {
        GivenFileOrDirectory -Path 'file.txt'
        GivenFileOrDirectory -Path 'file2.txt'
        $pathList = @(
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'file.txt'),
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'file1.txt'),
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'file2.txt')
                )
        WhenRemovingFileOrDirectory -Path $pathList -Piped -ErrorAction SilentlyContinue
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenFileOrDirectoryShouldNotExist 'file2.txt'
        ThenShouldThrowErrors -ExpectedError 'Could\ not\ find' 
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a directory that doesn''t exist' {
    It 'should throw errors' {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath 'dir'
        WhenRemovingFileOrDirectory -Path $fullPath -ErrorAction SilentlyContinue
        ThenShouldThrowErrors -ExpectedError 'Could\ not\ find'
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid directories and one that doesn''t exist' {
    It 'should remove all valid directories and throw and error' {
        GivenFileOrDirectory -Path 'dir'
        GivenFileOrDirectory -Path 'dir2'
        $pathList = @(
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'dir'),
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'dir1'),
                    (Join-Path -Path $TestDrive.FullName -ChildPath 'dir2')
                )
        WhenRemovingFileOrDirectory -Path $pathList -Piped -ErrorAction SilentlyContinue
        ThenFileOrDirectoryShouldNotExist 'dir'
        ThenFileOrDirectoryShouldNotExist 'dir2'
        ThenShouldThrowErrors -ExpectedError 'Could\ not\ find' 
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid file in a directory with other valid files' {
    It 'should remove the file without removing the other files' {
        GivenFileOrDirectory -Path 'file.txt'
        GivenFileOrDirectory -Path 'file1.txt'
        GivenFileOrDirectory -Path 'file2.txt'
        WhenRemovingFileOrDirectory -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'file.txt')
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenFileOrDirectoryShouldExist 'file1.txt'
        ThenFileOrDirectoryShouldExist 'file2.txt'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid nested file' {
    It 'should remove the file but not the directory' {
        $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath 'dir/file.txt'
        GivenFileOrDirectory 'dir/file.txt'
        WhenRemovingFileOrDirectory -Path $fullPath
        ThenFileOrDirectoryShouldNotExist 'dir/file.txt'
        ThenFileOrDirectoryShouldExist 'dir'
        ThenRanSuccessfully
    }
}