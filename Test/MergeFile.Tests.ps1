
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false

function GivenFile
{
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [object]$WithContent
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    if( $WithContent )
    {
        if( $WithContent -is [string] )
        {
            [IO.File]::WriteAllText($fullPath,$WithContent)
        }
        elseif( $WithContent -is [byte[]] )
        {
            [IO.File]::WriteAllBytes($fullPath,$WithContent)
        }
        else
        {
            throw ('GivenFile: parameter "WithContent" must be a string or an array of bytes but got a [{0}].' -f $WithContent.GetType().FullName)
        }
    }
    else
    {
        New-Item -Path $fullPath
    }
}

function Get-RandomByte
{
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
    )

    1..(4kb * 3) | ForEach-Object { Get-Random -Minimum 0 -Maximum 255 }
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
        [object]$HasContent
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    if( $PSCmdlet.ParameterSetName -eq 'Exists' )
    {
        $fullPath | Should -Exist
        if( $PSBoundParameters.ContainsKey('HasContent') )
        {
            if( $HasContent -is [string] )
            {
                [IO.File]::ReadAllText($fullPath) | Should -Be $HasContent
            }
            elseif( $HasContent -is [byte[]] )
            {
                [byte[]]$content = [IO.File]::ReadAllBytes($fullPath)
                $content | Should -Be $HasContent
            }
            else
            {
                throw ('ThenFile: parameter "HasContent" must be a [string] or [byte[]] but got a [{0}]' -f $HasContent.GetType().FullName)
            }
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

        [string]$WithTextSeparator,

        [byte[]]$WithBinarySeparator,

        [switch]$Clear
    )

    $context = New-WhiskeyTestContext -ForBuildServer

    $parameters = @{ 'Path' = $Path ; 'DestinationPath' = $Into }
    if( $AndDeletingSourceFiles )
    {
        $parameters['DeleteSourceFiles'] = 'true'
    }
    
    if( $WithTextSeparator )
    {
        $parameters['TextSeparator'] = $WithTextSeparator
    }

    if( $WithBinarySeparator )
    {
        $parameters['BinarySeparator'] = $WithBinarySeparator | ForEach-Object { $_.ToString() }
    }

    if( $Clear )
    {
        $parameters['Clear'] = $Clear
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
    It 'should keep existing contents' {
        Init
        GivenFile 'merged.txt' -WithContent 'i should not disappear'
        GivenFile 'one.txt' -WithContent 'snafu'
        WhenMerging 'one.txt' -Into 'merged.txt'
        ThenFile 'one.txt' -Exists
        ThenFile 'merged.txt' -HasContent 'i should not disappearsnafu'
    }
}

Describe 'MergeFile.when destination file exists and user wants to clear it' {
    It 'should clear existing contents' {
        Init
        GivenFile 'merged.txt' -WithContent 'i should disappear'
        GivenFile 'one.txt' -WithContent 'snafu'
        WhenMerging 'one.txt' -Into 'merged.txt' -Clear
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
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -WithTextSeparator ('$(NewLine)') 
        ThenFile 'merged.txt' -HasContent ('one{0}two' -f [Environment]::NewLine)
    }
}

Describe 'MergeFile.when customizing separator and keeping destination file content' {
    It 'should add separator after existing contents' {
        Init
        GivenFile 'one.txt' -WithContent 'one'
        GivenFile 'two.txt' -WithContent 'two'
        GivenFile 'merged.txt' -WithContent 'i was here first'
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -WithTextSeparator ('$(NewLine)') 
        ThenFile 'merged.txt' -HasContent ('i was here first{0}one{0}two' -f [Environment]::NewLine)
    }
}

Describe 'MergeFile.when customizing separator and clearing destination file content' {
    It 'should not add separator to beginning of file' {
        Init
        GivenFile 'one.txt' -WithContent 'one'
        GivenFile 'two.txt' -WithContent 'two'
        GivenFile 'merge.tst' -WithContent 'gone gone gone'
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -WithTextSeparator ('$(NewLine)') -Clear
        ThenFile 'merged.txt' -HasContent ('one{0}two' -f [Environment]::NewLine)
    }
}

Describe 'MergeFile.when files are empty' {
    It 'should separate file contents with separator' {
        Init
        GivenFile 'one.txt' 
        GivenFile 'two.txt' 
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' 
        ThenFile 'merged.txt' -HasContent ('')
    }
}

Describe 'MergeFile.when files are binary' {
    It 'should concatenate files' {
        Init
        [byte[]]$content = Get-RandomByte
        GivenFile 'one.txt' -WithContent $content 
        [byte[]]$content2 = Get-RandomByte
        GivenFile 'two.txt' -WithContent ($content2)
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt'
        ThenFile 'merged.txt' -HasContent ([byte[]]($content + $content2))
    }
}

Describe 'MergeFile.when separator and files are binary' {
    It 'should concatenate files with separator' {
        Init
        [byte[]]$content = Get-RandomByte
        GivenFile 'one.txt' -WithContent $content 
        [byte[]]$content2 = Get-RandomByte
        GivenFile 'two.txt' -WithContent ($content2)
        WhenMerging 'one.txt','two.txt' -Into 'merged.txt' -WithBinarySeparator ([byte[]]@( 28 ))
        ThenFile 'merged.txt' -HasContent ([byte[]]($content + 28 + $content2))
    }
}

Describe 'MergeFile.when text and binary separators given' {
    It 'should fail' {
        Init
        GivenFile 'one.txt' -WithContent 'abc'
        WhenMerging 'one.txt' -Into 'merged.txt' -WithTextSeparator 'def' -WithBinarySeparator @( 28, 29, 30 )
        ThenFailed 'use\ only\ the\ TextSeparator\ or\ BinarySeparator\ property'
    }
}