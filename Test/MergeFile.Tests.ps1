
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false

function GivenFile
{
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$WithContent
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    [IO.File]::WriteAllText($fullPath,$WithContent)
}

function Init
{
    $script:failed = $false
}

function ThenFailed
{
    param(
        [Parameter(Mandatory)]
        [string]$WithError
    )

    $Global:Error | Should -Not -BeNullOrEmpty
    $failed | Should -BeTrue
    $Global:Error | Should -Match $WithError
}
function ThenFile
{
    [CmdletBinding(DefaultParameterSetName='Exists')]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]$Path,

        [Parameter(Mandatory,ParameterSetName='DoesNotExist')]
        [Switch]$DoesNotExist,

        [Parameter(ParameterSetName='Exists')]
        [switch]$Exists,

        [Parameter(ParameterSetName='Exists')]
        [string]$HasContent
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    if( $PSCmdlet.ParameterSetName -eq 'Exists' )
    {
        $fullPath | Should -Exist
        if( $PSBoundParameters.ContainsKey('HasContent') )
        {
            [IO.File]::ReadAllText($fullPath) | Should -Be $HasContent
        }
    }
    else
    {
        $fullPath | Should -Not -Exist
    }
}

function WhenMerging
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,

        [Parameter(Mandatory)]
        [string]$Into,

        [switch]$AndDeletingSourceFiles,

        [string]$WithSeparator
    )

    $context = New-WhiskeyTestContext -ForBuildServer

    $parameters = @{ 'Path' = $Path ; 'DestinationPath' = $Into }
    if( $AndDeletingSourceFiles )
    {
        $parameters['DeleteSourceFiles'] = 'true'
    }
    
    if( $WithSeparator )
    {
        $parameters['Separator'] = $WithSeparator
    }

    try
    {
        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Name 'MergeFile' -Parameter $parameters
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'MergeFile.when there is one file' {
    It 'should merge the file and leave the original' {
        Init
        GivenFile 'one.txt' -WithContent ("1`n2`n3")
        WhenMerging 'one.txt' -Into 'newfile.txt'
        ThenFile 'one.txt' -Exists
        ThenFile 'newfile.txt' -HasContent ("1`n2`n3")
    }
}

Describe 'MergeFile.when there are multiple files' {
    It 'should merge the files and leave the originals' {
        Init
        GivenFile 'one.txt' -WithContent ("1`n2`n3")
        GivenFile 'two.txt' -WithContent ("6`n5`n4")
        WhenMerging 'one.txt','two.txt' -Into 'newfile.txt'
        ThenFile 'one.txt' -Exists
        ThenFile 'two.txt' -Exists
        ThenFile 'newfile.txt' -HasContent ("1`n2`n36`n5`n4")
    }
}

Describe 'MergeFile.when destination path directory doesn''t exist' {
    It 'should create the destination directory' {
        Init
        GivenFile 'one.txt' -WithContent 'fubar'
        WhenMerging 'one.txt' -Into 'dir\newfile.txt'
        ThenFile 'one.txt' -Exists
        ThenFile 'dir\newfile.txt' -HasContent 'fubar'
    }
}

Describe 'MergeFile.when destination file exists and has stuff in it' {
    It 'should clear existing contents' {
        Init
        GivenFile 'merged.txt' -WithContent 'i should disappear'
        GivenFile 'one.txt' -WithContent 'snafu'
        WhenMerging 'one.txt' -Into 'merged.txt'
        ThenFile 'one.txt' -Exists
        ThenFile 'merged.txt' -HasContent 'snafu'
    }
}

Describe 'MergeFile.when destination file is outside the build root' {
    It 'should fail' {
        Init
        GivenFile 'one.txt' -WithContent 'failed!'
        WhenMerging 'one.txt' -Into '..\somefile.txt' -ErrorAction SilentlyContinue
        ThenFailed -WithError 'which\ is\ outside\ the\ build\ root' 
    }
}

Describe 'MergeFile.when deleting originals' {
    It 'should delete source files' {
        Init
        GivenFile 'one.txt' -WithContent 'one'
        GivenFile 'two.txt' -WithContent 'two'
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -AndDeletingSourceFiles
        ThenFile 'one.txt' -DoesNotExist
        ThenFile 'two.txt' -DoesNotExist
        ThenFile 'merged.txt' -HasContent 'onetwo'
    }
}

Describe 'MergeFile.when customizing separator' {
    It 'should separate file contents with separator' {
        Init
        GivenFile 'one.txt' -WithContent 'one'
        GivenFile 'two.txt' -WithContent 'two'
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -WithSeparator ('$(NewLine)') 
        ThenFile 'merged.txt' -HasContent ('one{0}two' -f [Environment]::NewLine)
    }
}