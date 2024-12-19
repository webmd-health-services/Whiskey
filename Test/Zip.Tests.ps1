
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:threwException = $false
    $script:context = $null
    $script:expandPath = $null

    # Other modules have an Expand-Archive command, so make sure these tests are using the one we expect/want.
    Get-Command -Name 'Expand-Archive' |
        Select-Object -ExpandProperty 'Source' |
        Get-Module |
        Remove-Module

    Import-Module -Name 'Microsoft.PowerShell.Archive'

    function Get-BuildRoot
    {
        $buildRoot = (Join-Path -Path $script:testRoot -ChildPath 'Repo')
        New-Item -Path $buildRoot -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null
        return $buildRoot
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

    function ThenArchiveShouldInclude
    {
        param(
            $ArchivePath,

            [Parameter(Position=0)]
            [String[]]$Path
        )

        if( -not $Path )
        {
            Get-ChildItem -Path $script:expandPath | Should -BeNullOrEmpty
            return
        }

        foreach( $item in $Path )
        {
            $expectedPath = Join-Path -Path $script:expandPath -ChildPath $item
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
        Write-WhiskeyDebug -Context $script:context -Message ('Archive size: {0}' -f $archiveSize)
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
            (Join-Path -Path $script:expandPath -ChildPath $item) | Should -Not -Exist
        }
    }

    function ThenTaskFails
    {
        Param(
            [String]$error
        )

        $script:threwException | Should -BeTrue

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

        $taskParameter = $script:context.Configuration['Build'][0]['Zip']

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
            $ToFile = $script:context.Configuration['Build'][0]['Zip']['ArchivePath']
            $ToFile = Join-Path -Path (Get-BuildRoot) -ChildPath $ToFile
        }
        if( (Test-Path -Path $ToFile -PathType Leaf) )
        {
            Expand-Archive -Path $ToFile -DestinationPath $script:expandPath -Force
        }
    }
}

Describe 'Zip' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot

        $script:threwException = $false
        $script:context = $null
        $script:expandPath = Join-Path -Path $script:testRoot -ChildPath ([IO.Path]::GetRandomFileName())

        Remove-Module -Force -Name Zip -ErrorAction Ignore

        Reset-WhiskeyPSModulePath
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
        Reset-WhiskeyPSModulePath
    }

    It 'uses custom names in zip file' {
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

    It 'creates a zip file with no items' {
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

    It 'gets all the files that match the wildcards' {
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

    It 'packages the directory' {
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

    It 'packages only items that match the filter' {
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

    It 'handle spaces in paths' {
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

    It 'trims backslashes of directory paths' {
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

    It 'can customize compression level' {
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
        $optimalSize = Get-Item -Path (Join-Path -Path $script:context.BuildRoot -ChildPath 'Optimal.zip') | Select-Object -ExpandProperty 'Length'
        $fastestSize = Get-Item -Path (Join-Path -Path $script:context.BuildRoot -ChildPath 'Fastest.zip') | Select-Object -ExpandProperty 'Length'
        $noCompressionSize = Get-Item -Path (Join-Path -Path $script:context.BuildRoot -ChildPath 'NoCompression.zip') | Select-Object -ExpandProperty 'Length'
        $optimalSize | Should -BeLessThan $fastestSize
        $fastestSize | Should -BeLessthan $noCompressionSize
    }

    It 'uses Optimal compression by default' {
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
        $fastestSize = Get-Item -Path (Join-Path -Path $script:context.BuildRoot -ChildPath 'Fastest.zip') | Select-Object -ExpandProperty 'Length'
        ThenArchiveShouldBeCompressed 'Zip.zip' -LessThan $fastestSize
    }

    It 'validates compression level' {
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

    It 'excludes empty directories' {
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

    It 'includes JSON files' {
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

    It 'allows empty whitelist' {
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

    Context 'entry name encoding' {
        BeforeEach {
            Import-WhiskeyTestModule -Name 'Zip'
        }

        It 'supports custom entry name encoding' {
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

        It 'validates entry name encoding' {
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

        It 'allows code page ID' {
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

        It 'validates code page ID' {
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

    It 'allows changing source directory' {
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

    It 'supports full paths for archive path' {
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

    It 'creates destination directory' {
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

    It 'validats path property is mandatory' {
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
'@ -ErrorAction SilentlyContinue
        ThenTaskFails 'is required'
    }

    It 'replaces existing archive' {
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json', 'Zip.zip'
        WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path: dir
'@
        ThenArchiveShouldInclude 'dir/my.json','dir/yours.json'
    }

    Context 'when Zip module not installed' {
        AfterEach {
            $whiskeyZipPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Zip.MOVED' -Resolve -ErrorAction Ignore
            if( $whiskeyZipPath )
            {
                Rename-Item -Path $whiskeyZipPath -NewName 'Zip'
            }
        }

        It 'should install Zip module' {
            $whiskeyZipPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Zip' -Resolve -ErrorAction Ignore
            if( $whiskeyZipPath )
            {
                Rename-Item -Path $whiskeyZipPath -NewName 'Zip.MOVED'
            }
            GivenARepositoryWithItems 'fubar.txt' -AndModuleNotInstalled
            WhenPackaging @'
Build:
- Zip:
    ArchivePath: Zip.zip
    Path: fubar.txt
'@ -AndModuleNotInstalled
            $latestZip = Find-Module -Name 'Zip' | Select-Object -First 1
            Join-Path -Path $script:context.BuildRoot -ChildPath "PSModules\Zip\$($latestZip.Version)" | Should -Exist
        }
    }
}
