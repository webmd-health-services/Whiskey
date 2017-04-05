
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$taskfailed = $false
$taskException = $null

function Get-BuildRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Source'
}

function Get-DestinationRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Destination'
}

function GivenCurrentUserCanNotWriteToDestination
{
    Mock -CommandName 'New-Item' -MockWith { Write-Error 'You don''t have access!' }
}

function GivenDirectories
{
    param(
        [string[]]
        $Path
    )

    $sourceRoot = Get-BuildRoot
    foreach( $item in $Path )
    {
        New-Item -Path (Join-Path -Path $sourceRoot -ChildPath $item) -ItemType 'Directory' -Force | Out-Null
    }
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
        $ByADeveloper
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
    $taskParameter['SourceFiles'] = $Path
    $destinationRoot = Get-DestinationRoot
    $To = $To | ForEach-Object { Join-Path -Path $destinationRoot -ChildPath $_ }
    if( -not $To )
    {
        $To = $destinationRoot
    }
    $taskParameter['DestinationDirectories'] = $To

    $taskContext.BuildRoot = Get-BuildRoot
    $script:taskfailed = $false
    $script:taskException = $null

    try
    {
        Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter
    }
    catch
    {
        $taskException = $_
        $taskFailed = $true
        Write-Error -ErrorRecord $_
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
        $taskfailed | Should Be $true
        $taskException | Should Match $WithErrorMessage
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
    GivenCurrentUserCanNotWriteToDestination
    WhenPublishingFiles 'one.txt'
    ThenTaskFails -WithErrorMessage 'failed\ to\ create\ destination\ directory'
    ThenNothingPublished
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing nothing' {
    GivenNoFilesToPublish
    WhenPublishingFiles
    ThenTaskFails -WithErrorMessage 'is missing'
    ThenNothingPublished
}

Describe 'Invoke-WhsCIPublishFileTask.when publishing a directory' {
    GivenFiles 'dir1\file1.txt'
    WhenPublishingFiles 'dir1'
    ThenTaskFails 'must be a file'
    ThenNothingPublished
}