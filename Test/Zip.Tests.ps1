
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$threwException = $false
$context = $null
$expandPath = $null

# Other modules have an Expand-Archive command, so make sure these tests are using the one we expect/want.
Get-Command -Name 'Expand-Archive' |
    Select-Object -ExpandProperty 'Source' |
    Get-Module |
    Remove-Module

Import-Module -Name 'Microsoft.PowerShell.Archive'

function Get-BuildRoot
{
    $buildRoot = (Join-Path -Path $testRoot -ChildPath 'Repo')
    New-Item -Path $buildRoot -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null
    return $buildRoot
}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot

    $script:threwException = $false
    $script:context = $null
    $script:expandPath = Join-Path -Path $testRoot -ChildPath ([IO.Path]::GetRandomFileName())

    Remove-Module -Force -Name Zip -ErrorAction Ignore

    Reset-WhiskeyPSModulePath
}

function GivenARepositoryWithItems
{
    param(
        [String[]]$Path,

        $ItemType = 'File'
    )

    $buildRoot = Get-BuildRoot

    foreach( $item in $Path )
    {
        $parent = $item | Split-Path
        if( $parent )
        {
            New-Item -Path (Join-Path -Path $buildRoot -ChildPath $parent) -ItemType 'Directory' -Force -ErrorAction Ignore
        }

        $destinationPath = Join-Path -Path $buildRoot -ChildPath $item
        if( $ItemType -eq 'File' )
        {
            Copy-Item -Path $PSCommandPath -Destination $destinationPath
        }
        else
        {
            New-Item -Path $destinationPath -ItemType 'Directory'
        }
    }
}

function Reset
{
    Reset-WhiskeyTestPSModule
    Reset-WhiskeyPSModulePath
}

function ThenArchiveShouldInclude
{
    param(
        $ArchivePath,

        [Parameter(Position=0)]
        [String[]]$Path
    )

    if( -not $Path )
    {
        Get-ChildItem -Path $expandPath | Should -BeNullOrEmpty
        return
    }

    foreach( $item in $Path )
    {
        $expectedPath = Join-Path -Path $expandPath -ChildPath $item
        $expectedPath | Should -Exist
    }
}

function ThenArchiveShouldBeCompressed
{
    param(
        $Path,

        [int]$GreaterThan,

        [int]$LessThanOrEqualTo
    )

    $archivePath = Join-Path -Path (Get-BuildRoot) -ChildPath $Path
    $archiveSize = (Get-Item $archivePath).Length
    Write-WhiskeyDebug -Context $context -Message ('Archive size: {0}' -f $archiveSize)
    if( $GreaterThan )
    {
        $archiveSize | Should -BeGreaterThan $GreaterThan
    }

    if( $LessThanOrEqualTo )
    {
        $archiveSize | Should -Not -BeGreaterThan $LessThanOrEqualTo
    }

}

function ThenArchiveShouldNotInclude
{
    param(
        [String[]]$Path
    )

    foreach( $item in $Path )
    {
        (Join-Path -Path $expandPath -ChildPath $item) | Should -Not -Exist
    }
}

function ThenTaskFails
{
    Param(
        [String]$error
    )

    $threwException | Should -BeTrue

    $Global:Error | Should -Match $error
}

function ThenTaskSucceeds
{
    $Global:Error | Should -BeNullOrEmpty
}

function WhenPackaging
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$WithYaml,

        [String]$ToFile,

        [switch]$AndModuleNotInstalled
    )

    # Make sure the build root exists.
    Get-BuildRoot | Out-Null

    $contextParams = @{ 
        'ForBuildRoot' = (Get-BuildRoot);
        'ForBuildServer' = $true;
        'ForYaml' = $WithYaml;
        'IncludePSModule' = 'Zip'
    }
    
    if( $AndModuleNotInstalled )
    {
        $contextParams.Remove('IncludePSModule')
    }

    $script:context = $taskContext = New-WhiskeyTestContext @contextParams

    $taskParameter = $context.Configuration['Build'][0]['Zip']

    $Global:Error.Clear()

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'Zip'
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
        return
    }
    
    if( -not $ToFile )
    {
        $ToFile = $context.Configuration['Build'][0]['Zip']['ArchivePath']
        $ToFile = Join-Path -Path (Get-BuildRoot) -ChildPath $ToFile
    }
    if( (Test-Path -Path $ToFile -PathType Leaf) )
    {
        Expand-Archive -Path $ToFile -DestinationPath $expandPath -Force
    }
}

Describe 'Zip.when packaging items with custom destination names' {
    AfterEach { Reset }
    It 'should use custom names in zip file' {
        Init
        GivenARepositoryWithItems 'LICENSE.txt','dir1\some_file.txt','dir2\dir3\another_file.txt','dir4\dir5\last_file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir1: dirA
    - dir2\dir3: dir2\dirC
    - dir4\dir5: dirD\dir5
    - LICENSE.txt: somedir\LICENSE.txt
    Include:
    - "*.txt"
'@
        ThenTaskSucceeds
        ThenArchiveShouldInclude 'dirA/some_file.txt','dir2/dirC/another_file.txt','dirD/dir5/last_file.txt','somedir/LICENSE.txt'
    }
}

Describe 'Zip.when archive is empty' {
    AfterEach { Reset }
    It 'should create a zip file with no items' {
        Init
        GivenARepositoryWIthItems 'file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - .
    Include:
    - "*.fubar"
'@
        ThenArchiveShouldInclude
    }
}

Describe 'Zip.when path contains wildcards' {
    AfterEach { Reset }
    It 'should get all the files that match the wildcards' {
        Init
        GivenARepositoryWIthItems 'one.ps1','two.ps1','three.ps1'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - "*.ps1"
    Include:
    - "*.txt"
'@
        ThenArchiveShouldInclude 'one.ps1','two.ps1','three.ps1'
    }
}

Describe 'Zip.when packaging a directory' {
    AfterEach { Reset }
    It 'should package the directory' {
        Init
        GivenARepositoryWIthItems 'dir1\subdir\file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir1\subdir\
    Include:
    - "*.txt"
'@
        ThenArchiveShouldInclude 'dir1/subdir/file.txt'
    }
}

Describe 'Zip.when packaging a filtered directory' {
    AfterEach { Reset }
    It 'should package only items that match the filter' {
        Init
        GivenARepositoryWIthItems 'dir1\subdir\file.txt','dir1\one.ps1','dir1\dir2\file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir1\subdir\
    Include:
    - "*.txt"
    Exclude:
    - dir2
'@
        ThenArchiveShouldInclude 'dir1/subdir/file.txt'
        ThenArchiveShouldNotInclude 'dir1/one.ps1','dir1/dir2/file.txt'
    }
}

Describe 'Zip.when packaging a directory with a space' {
    AfterEach { Reset }
    It 'should handle spaces' {
        Init
        GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir 1\sub dir\
    Include:
    - "*.txt"
'@
        ThenArchiveShouldInclude 'dir 1/sub dir/file.txt'
    }
}

Describe 'Zip.when packaging a directory with a space and trailing backslash' {
    AfterEach { Reset }
    It 'should trim the backslash' {
        Init
        GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir 1\sub dir\
    Include:
    - "*.txt"
'@
        ThenArchiveShouldInclude 'dir 1/sub dir/file.txt'
    }
}

Describe ('Zip.when compression level is customized') {
    AfterEach { Reset }
    It 'should compress at selected compression level' {
        Init
        GivenARepositoryWithItems 'one.ps1'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Optimal.zip
    CompressionLevel: Optimal
    Path:
    - "*.ps1"
'@
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Fastest.zip
    CompressionLevel: Fastest
    Path:
    - "*.ps1"
'@
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: NoCompression.zip
    CompressionLevel: NoCompression
    Path:
    - "*.ps1"
'@
        ThenArchiveShouldBeCompressed 'Optimal.zip' 
        ThenArchiveShouldBeCompressed 'Fastest.zip' 
        ThenArchiveShouldBeCompressed 'NoCompression.zip' 
        $optimalSize = Get-Item -Path (Join-Path -Path $Context.BuildRoot -ChildPath 'Optimal.zip') | Select-Object -ExpandProperty 'Length'
        $fastestSize = Get-Item -Path (Join-Path -Path $Context.BuildRoot -ChildPath 'Fastest.zip') | Select-Object -ExpandProperty 'Length'
        $noCompressionSize = Get-Item -Path (Join-Path -Path $Context.BuildRoot -ChildPath 'NoCompression.zip') | Select-Object -ExpandProperty 'Length'
        $optimalSize | Should -BeLessThan $fastestSize
        $fastestSize | Should -BeLessthan $noCompressionSize
    }
}
Describe 'Zip.when compression level is not included' {
    AfterEach { Reset }
    It 'should use Optimal compression by default' {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging @"
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - "*.ps1"
"@
        WhenPackaging @"
Build:
- Zip:
    ArchivePath: Fastest.zip
    CompressionLevel: Fastest
    Path:
    - "*.ps1"
"@
        ThenArchiveShouldBeCompressed 'Fastest.zip' 
        $fastestSize = Get-Item -Path (Join-Path -Path $Context.BuildRoot -ChildPath 'Fastest.zip') | Select-Object -ExpandProperty 'Length'
        ThenArchiveShouldBeCompressed 'Zip.zip' -LessThan $fastestSize
    }
}

Describe 'Zip.when a bad compression level is included' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging -ErrorAction SilentlyContinue @'
Build:
- Zip:
    ArchivePath: Zip.zip
    CompressionLevel: this is no good
    Path:
    - "*.ps1"
'@
        ThenTaskFails 'is an invalid compression level'
    }
}

Describe 'Zip.when archive and source have empty directories' {
    AfterEach { Reset }
    It 'should not include empty directories' {
        Init
        GivenARepositoryWithItems 'root.ps1','dir1\one.ps1','dir1\emptyDir2\text.txt'
        GivenARepositoryWithItems 'dir1\emptyDir1' -ItemType 'Directory'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - .
    Include:
    - "*.ps1"
    Exclude:
    - .output
'@
        ThenArchiveShouldInclude 'root.ps1','dir1/one.ps1'
        ThenArchiveShouldNotInclude 'dir1/emptyDir1', 'dir1/emptyDir2'
    }
}

Describe 'Zip.when archive has JSON files' {
    AfterEach { Reset }
    It 'should include the JSON files' {
        Init
        GivenARepositoryWIthItems 'my.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - .
    Include:
    - "*.json"
    Exclude:
    - .output
'@
        ThenArchiveShouldInclude 'my.json'
    }
}

Describe 'Zip.when archive includes a directory but whitelist is empty' {
    AfterEach { Reset }
    It 'should include all the items' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path:
    - dir
'@
        ThenArchiveShouldInclude 'dir/my.json','dir/yours.json'
    }
}

Describe 'Zip.when customizing entry name encoding' {
    AfterEach { Reset }
    BeforeEach { 
        Init
        Import-WhiskeyTestModule -Name 'Zip'
    }
    Context ('using encoding name') {
        It 'should encode names in the custom encoding' {
            Mock -CommandName 'Add-ZipArchiveEntry' -ModuleName 'Whiskey'
            Mock -CommandName 'New-ZipArchive' -ModuleName 'Whiskey'
            GivenARepositoryWIthItems 'dir\file.txt'
            WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    EntryNameEncoding: ASCII
    Path:
    - dir
'@
            Assert-MockCalled -CommandName 'Add-ZipArchiveEntry' -ModuleName 'Whiskey' -ParameterFilter { $EntryNameEncoding -eq [Text.Encoding]::ASCII }
            Assert-MockCalled -CommandName 'New-ZipArchive' -ModuleName 'Whiskey' -ParameterFilter { $EntryNameEncoding -eq [Text.Encoding]::ASCII }
        }
    }
    Context ('using invalid encoding name') {
        It 'should fail' {
            GivenARepositoryWIthItems 'dir\file.txt'
            WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    EntryNameEncoding: fdsfsdfsdaf
    Path:
    - dir
'@ -ErrorAction SilentlyContinue
            ThenTaskFails 'fdsfsdfsdaf'
        }
    }
    Context ('using code page ID') {
        It 'should encode with that encoding' {
            Mock -CommandName 'Add-ZipArchiveEntry' -ModuleName 'Whiskey'
            Mock -CommandName 'New-ZipArchive' -ModuleName 'Whiskey'
            GivenARepositoryWIthItems 'dir\file.txt'
            WhenPackaging @"
Build:
- Zip:
    ArchivePath: Zip.zip
    EntryNameEncoding: $([Text.Encoding]::UTF32.CodePage)
    Path:
    - dir
"@
            Assert-MockCalled -CommandName 'Add-ZipArchiveEntry' -ModuleName 'Whiskey' -ParameterFilter { $EntryNameEncoding -eq [Text.Encoding]::UTF32 }
            Assert-MockCalled -CommandName 'New-ZipArchive' -ModuleName 'Whiskey' -ParameterFilter { $EntryNameEncoding -eq [Text.Encoding]::UTF32 }
        }
    }
    Context ('using invalid code page') {
        It 'should fail' {
            GivenARepositoryWIthItems 'dir\file.txt'
            WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    EntryNameEncoding: 65535
    Path:
    - dir
'@ -ErrorAction SilentlyContinue
            ThenTaskFails '65535'
        }
    }
}

Describe 'Zip.when changing archive''s source root' {
    AfterEach { Reset }
    It 'should remove that path from files in archive' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    SourceRoot: dir
    Path:
    - "*.json"
'@
        ThenArchiveShouldInclude 'my.json','yours.json'
    }
}

Describe 'Zip.when given full path to output file' {
    AfterEach { Reset }
    It 'should write to that file' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: $(WHISKEY_OUTPUT_DIRECTORY)\Zip.zip
    Path: dir
    Include: "*.json"
'@ -ToFile (Join-Path -Path (Get-BuildRoot) -ChildPath '.output\Zip.zip')
        ThenArchiveShouldInclude 'dir/my.json','dir/yours.json'
    }
}

Describe 'Zip.when absolute path to archive root outside repository' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        $systemRoot = 'C:\Windows\system32\'
        if( -not $IsWindows )
        {
            $systemRoot = '/sbin/'
        }
        WhenPackaging @"
Build:
- Zip:
    ArchivePath: $($systemRoot)Zip.zip
    Path: dir
    Include: "*.json"
"@ -ErrorAction SilentlyContinue
        ThenTaskFails 'outside the build root'
    }
}

Describe 'Zip.when relative path to archive root outside repository' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: ..\..\..\Zip.zip
    Path: dir
    Include: "*.json"
'@ -ErrorAction SilentlyContinue
        ThenTaskFails 'outside the build root'
    }
}

Describe 'Zip.when path to archive is in directory that doesn''t exist' {
    AfterEach { Reset }
    It 'should create destination directory' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: some\custom\directory\Zip.zip
    Path: dir
    Include: "*.json"
'@ -ToFile (Join-Path -Path (Get-BuildRoot) -ChildPath 'some\custom\directory\Zip.zip')
        ThenArchiveShouldInclude 'dir/my.json','dir/yours.json'
    }
}

Describe 'Zip.when Path property is missing' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
'@ -ErrorAction SilentlyContinue
        ThenTaskFails 'is required'
    }
}

Describe 'Zip.when ZIP archive already exists' {
    AfterEach { Reset }
    It 'should replace existing archive' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json', 'Zip.zip'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path: dir
'@
        ThenArchiveShouldInclude 'dir/my.json','dir/yours.json'
    }
}

Describe 'Zip.when Zip module not installed' {
    AfterEach {
        Reset
        Register-WhiskeyPSModulesPath
    }
    It 'should install Zip module' {
        Init
        Unregister-WhiskeyPSModulesPath
        GivenARepositoryWithItems 'fubar.txt' -AndModuleNotInstalled
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path: fubar.txt
'@ -AndModuleNotInstalled
        $latestZip = Find-Module -Name 'Zip' | Select-Object -First 1
        ThenModuleInstalled 'Zip' -AtVersion $latestZip.Version -InBuildRoot $context.BuildRoot
    }
}
