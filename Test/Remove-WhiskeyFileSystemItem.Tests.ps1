& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Init {
    $script:testRoot = New-WhiskeyTestRoot
}

function GivenFileOrDirectory
{
    param(
        $Path,

        [String]$PathType
    )

    $fullPath = Join-Path -Path $testRoot -ChildPath $Path
    New-Item -Path $fullPath -ItemType $PathType -Force | Out-Null
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
    try
    {
        if( $Piped )
        {
            InModuleScope 'Whiskey' { ($Global:Path | Remove-WhiskeyFileSystemItem) }
        }
        else
        {
            InModuleScope 'Whiskey' { & Remove-WhiskeyFileSystemItem -Path $Global:Path }
        }
    }
    finally
    {
        Remove-Variable -Name 'Path' -Scope 'Global'
    }
}

function ThenFileOrDirectoryShouldNotExist
{
    param(
        $Path
    )

    $fullPath = Join-Path -Path $testRoot -ChildPath $Path
    $fullPath | Should -Not -Exist
}

function ThenFileOrDirectoryShouldExist
{
    param(
        $Path
    )
    $fullPath = Join-Path -Path $testRoot -ChildPath $Path
    $fullPath | Should -Exist
}

function ThenShouldThrowErrors
{
    param(
        $ExpectedError
    )
    $Global:Error | Should -Not -BeNullOrEmpty

    if( $ExpectedError )
    {
        $Global:Error[0] | Should -Match $ExpectedError
    }
}

function ThenRanSuccessfully
{
    $Global:Error[0] | Should -BeNullOrEmpty
}


Describe 'Remove-WhiskeyFileSystemItem.when given a valid file' {
    It 'should remove the file' {
        Init
        $fullPath = Join-Path -Path $testRoot -ChildPath 'file.txt'
        GivenFileOrDirectory -Path 'file.txt' -PathType 'file'
        WhenRemovingFileOrDirectory -Path $fullPath 
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid files' {
    It 'should remove all files' {
        Init
        GivenFileOrDirectory -Path 'file.txt' -PathType 'file'
        GivenFileOrDirectory -Path 'file1.txt' -PathType 'file'
        GivenFileOrDirectory -Path 'file2.txt' -PathType 'file'
        $pathList = @(
            (Join-Path -Path $testRoot -ChildPath 'file.txt'),
            (Join-Path -Path $testRoot -ChildPath 'file1.txt'),
            (Join-Path -Path $testRoot -ChildPath 'file2.txt')
        )
        WhenRemovingFileOrDirectory -Path $pathList -Piped
        ThenFileOrDirectoryShouldNotExist -Path 'file.txt' -PathType 'file'
        ThenFileOrDirectoryShouldNotExist -Path 'file2.txt' -PathType 'file'
        ThenFileOrDirectoryShouldNotExist -Path 'file3.txt' -PathType 'file'
        ThenRanSuccessfully

    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid directory' {
    It 'should remove the directory' {
        Init
        $fullPath = Join-Path -Path $testRoot -ChildPath 'dir'
        GivenFileOrDirectory -Path 'dir' -PathType 'container'
        WhenRemovingFileOrDirectory -Path $fullPath
        ThenFileOrDirectoryShouldNotExist 'dir'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid directories' {
    It 'should remove all directories' {
        Init
        GivenFileOrDirectory -Path 'dir' -PathType 'container'
        GivenFileOrDirectory -Path 'dir1' -PathType 'container'
        GivenFileOrDirectory -Path 'dir2' -PathType 'container'
        $pathList = @(
            (Join-Path -Path $testRoot -ChildPath 'dir'),
            (Join-Path -Path $testRoot -ChildPath 'dir1'),
            (Join-Path -Path $testRoot -ChildPath 'dir2')
        )
        WhenRemovingFileOrDirectory -Path $pathList -Piped
        ThenFileOrDirectoryShouldNotExist -Path 'dir'
        ThenFileOrDirectoryShouldNotExist -Path 'dir1'
        ThenFileOrDirectoryShouldNotExist -Path 'dir2'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a file that doesn''t exist' {
    It 'should do nothing' {
        Init
        $fullPath = Join-Path -Path $testRoot -ChildPath 'file.txt'
        WhenRemovingFileOrDirectory -Path $fullPath -ErrorAction SilentlyContinue
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid files and one that doesn''t exist' {
    It 'should remove all valid files' {
        Init
        GivenFileOrDirectory -Path 'file.txt' -PathType 'file'
        GivenFileOrDirectory -Path 'file2.txt' -PathType 'file'
        $pathList = @(
                    (Join-Path -Path $testRoot -ChildPath 'file.txt'),
                    (Join-Path -Path $testRoot -ChildPath 'file1.txt'),
                    (Join-Path -Path $testRoot -ChildPath 'file2.txt')
                )
        WhenRemovingFileOrDirectory -Path $pathList -Piped -ErrorAction SilentlyContinue
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenFileOrDirectoryShouldNotExist 'file2.txt'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a directory that doesn''t exist' {
    It 'should do nothing' {
        Init
        $fullPath = Join-Path -Path $testRoot -ChildPath 'dir'
        WhenRemovingFileOrDirectory -Path $fullPath -ErrorAction SilentlyContinue
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given multiple valid directories and one that doesn''t exist' {
    It 'should remove all valid directories' {
        Init
        GivenFileOrDirectory -Path 'dir' -PathType 'container'
        GivenFileOrDirectory -Path 'dir2' -PathType 'container'
        $pathList = @(
                    (Join-Path -Path $testRoot -ChildPath 'dir'),
                    (Join-Path -Path $testRoot -ChildPath 'dir1'),
                    (Join-Path -Path $testRoot -ChildPath 'dir2')
                )
        WhenRemovingFileOrDirectory -Path $pathList -Piped -ErrorAction SilentlyContinue
        ThenFileOrDirectoryShouldNotExist 'dir'
        ThenFileOrDirectoryShouldNotExist 'dir2'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid file in a directory with other valid files' {
    It 'should remove the file without removing the other files' {
        Init
        GivenFileOrDirectory -Path 'file.txt' -PathType 'file'
        GivenFileOrDirectory -Path 'file1.txt' -PathType 'file'
        GivenFileOrDirectory -Path 'file2.txt' -PathType 'file'
        WhenRemovingFileOrDirectory -Path (Join-Path -Path $testRoot -ChildPath 'file.txt')
        ThenFileOrDirectoryShouldNotExist 'file.txt'
        ThenFileOrDirectoryShouldExist 'file1.txt'
        ThenFileOrDirectoryShouldExist 'file2.txt'
        ThenRanSuccessfully
    }
}

Describe 'Remove-WhiskeyFileSystemItem.when given a valid nested file' {
    It 'should remove the file but not the directory' {
        Init
        $fullPath = Join-Path -Path $testRoot -ChildPath 'dir/file.txt'
        GivenFileOrDirectory 'dir/file.txt' -PathType 'file'
        WhenRemovingFileOrDirectory -Path $fullPath
        ThenFileOrDirectoryShouldNotExist 'dir/file.txt'
        ThenFileOrDirectoryShouldExist 'dir'
        ThenRanSuccessfully
    }
}