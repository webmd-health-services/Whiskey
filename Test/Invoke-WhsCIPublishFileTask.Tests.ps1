
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$Script:taskFailed = $false
$Script:taskException = $null

function Get-BuildRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Source'
}

function Get-DestinationRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Destination'
}

function GivenFiles
{
    param(
        [string[]]
        $Path
    )

    $sourceRoot = Get-BuildRoot
    foreach( $item in $Path )
    {
        New-Item -Path (Join-Path -Path $sourceRoot -ChildPath $item) -ItemType 'File' -Force | Out-Null
    }
}

function GivenNoFilesToPublish
{
}

function WhenPublishingFiles
{
    param(
        [Parameter(Position=0)]
        [string[]]
        $Path,

        [string[]]
        $To,

        [Switch]
        $ByADeveloper,

        [Switch]
        $UserCannotCreateDestinationDirectory
    )

    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith {return [SemVersion.SemanticVersion]'1.1.1-rc.1+build'}.GetNewClosure()

    $optionalParams = @{ }
    if( $ByADeveloper )
    {
        $optionalParams['ForDeveloper'] = $true
    }
    else
    {
        $optionalParams['ForBuildServer'] = $true
    }

    $taskContext = New-WhsCITestContext @optionalParams

    $taskParameter = @{ }
    $taskParameter['Path'] = $Path
    $destinationRoot = Get-DestinationRoot
    $To = $To | ForEach-Object { Join-Path -Path $destinationRoot -ChildPath $_ }
    if( -not $To )
    {
        $To = $destinationRoot
    }
    $taskParameter['DestinationDirectories'] = $To
    if( $UserCannotCreateDestinationDirectory )
    {
        $taskParameter['DestinationDirectories'] = 'BadDestinationDrive:\'
    }

    $taskContext.BuildRoot = Get-BuildRoot
    $Script:taskFailed = $false
    $Script:taskException = $null

    try
    {
        Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    }
    catch
    {
        $Script:taskException = $_
        $Script:taskFailed = $true
    }
}

function ThenNothingPublished
{
    param(
        [string[]]
        $To
    )

    $destinationRoot = Get-DestinationRoot
    It 'should copy nothing' {
        foreach( $item in $To )
        {
            Join-Path -Path $destinationRoot -ChildPath $item |
                Get-Item |
                Should BeNullOrEmpty
        }
    }
}

function ThenFilesPublished
{
    param(
        [string[]]
        $Path
    )

    $destinationRoot = Get-DestinationRoot

    It 'should copy files' {
        foreach( $item in $Path )
        {
            Join-Path -Path $destinationRoot -ChildPath $item  |
                Get-Item |
                Should Not BeNullOrEmpty
        }
    }
}

function ThenTaskFails
{
    param(
        $WithErrorMessage
    )

    It 'should throw an exception' {
        $Script:taskFailed | Should Be $true
        $Script:taskException | Should Match $WithErrorMessage
    }

}

Describe 'Invoke-WhsCIPublishFileTask when called by Developer' {
    GivenFiles 'file.txt'
    WhenPublishingFiles 'file.txt' -ByADeveloper
    ThenNothingPublished 
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing a single file' {
    GivenFiles 'one.txt'
    WhenPublishingFiles 'one.txt' 
    ThenFilesPublished 'one.txt'
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing multiple files to a single destination' {
    GivenFiles 'one.txt','two.txt'
    WhenPublishingFiles 'one.txt','two.txt'
    ThenFilesPublished 'one.txt','two.txt'
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing files from different directories' {
    GivenFiles 'dir1\one.txt','dir2\two.txt'
    WhenPublishingFiles 'dir1\one.txt','dir2\two.txt'
    ThenFilesPublished 'one.txt','two.txt'
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing to multiple destinations' {
    GivenFiles 'one.txt'
    WhenPublishingFiles 'one.txt' -To 'dir1','dir2'
    ThenFilesPublished 'dir1\one.txt','dir2\one.txt'
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing files and user can''t create destination directories' {
    GivenFiles 'one.txt'
    WhenPublishingFiles 'one.txt' -UserCannotCreateDestinationDirectory
    ThenTaskFails -WithErrorMessage 'Failed to create destination directory'
    ThenNothingPublished
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing nothing' {
    GivenNoFilesToPublish
    WhenPublishingFiles
    ThenTaskFails -WithErrorMessage '''Path'' property is missing'
    ThenNothingPublished
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing a directory' {
    GivenFiles 'dir1\file1.txt'
    WhenPublishingFiles 'dir1'
    ThenTaskFails 'File paths must resolve to individual files and not directories'
    ThenNothingPublished
}
