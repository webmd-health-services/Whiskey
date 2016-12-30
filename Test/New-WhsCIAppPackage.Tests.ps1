
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)

$defaultPackageName = 'WhsCITest'
$defaultVersion = '1.2.3-final'
$defaultDescription = 'A package created to test the New-WhsCIAppPackage function in the WhsCI module.'

function Assert-Package
{
    param(
        [string]
        $At,

        [string]
        $Name = $defaultPackageName,

        [string]
        $Description = $defaultDescription,

        [string]
        $Version = $defaultVersion,

        [string[]]
        $ContainsDirectories,

        [string[]]
        $WithFiles,

        [string[]]
        $WithoutFiles
   )

    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageName = '{0}.{1}.upack' -f $Name,$Version
    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $repoRoot
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    It 'should create a package' {
        $packagePath | Should Exist
    }

    Expand-Item -Path $At -OutDirectory $expandPath

    $upackJsonPath = Join-Path -Path $expandPath -ChildPath 'upack.json'

    Context 'the package' {
        foreach( $dirName in $ContainsDirectories )
        {
            $dirPath = Join-Path -Path $expandPath -ChildPath $dirName
            It ('should include {0} directory' -f $dirName) {
                 $dirpath | Should Exist
            }
            foreach( $fileName in $WithFiles )
            {
                It ('should include {0}\{1} file' -f $dirName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }

        if( $WithoutFiles )
        {
            foreach( $item in $WithoutFiles )
            {
                It ('should exclude {0} files' -f $item ) {
                    Get-ChildItem -Path $expandPath -Filter $item -Recurse | Should BeNullOrEmpty
                }
            }
        }

        It 'should include ProGet universal package metadata (upack.json)' {
            $upackJsonPath | Should Exist
        }

        $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc' -Resolve
        $arcPath = Join-Path -Path $expandPath -ChildPath 'Arc'

        It 'should include Arc' {
            $arcPath | Should Exist
        }

        $arcComponentsToExclude = @(
                                        'BitbucketServerAutomation', 
                                        'Blade', 
                                        'LibGit2', 
                                        'LibGit2Adapter', 
                                        'MSBuild',
                                        'Pester', 
                                        'PsHg',
                                        'ReleaseTrain',
                                        'WhsArtifacts',
                                        'WhsHg',
                                        'WhsPipeline'
                                    )
        It ('should exclude Arc CI components') {
            foreach( $name in $arcComponentsToExclude )
            {
                Join-Path -Path $arcPath -ChildPath $name | Should Not Exist
            }

            foreach( $item in (Get-ChildItem -Path $arcSourcePath -File) )
            {
                $relativePath = $item.FullName -replace [regex]::Escape($arcSourcePath),''
                $itemPath = Join-Path -Path $arcPath -ChildPath $relativePath
                $itemPath | Should Not Exist
            }
        }

        It ('should include Arc installation components') {
            foreach( $item in (Get-ChildItem -Path $arcSourcePath -Directory -Exclude $arcComponentsToExclude))
            {
                $relativePath = $item.FullName -replace [regex]::Escape($arcSourcePath),''
                $itemPath = Join-Path -Path $arcPath -ChildPath $relativePath
                $itemPath | Should Exist
            }
        }
    }

    Context 'upack.json' {
        $upackInfo = Get-Content -Raw -Path $upackJsonPath | ConvertFrom-Json
        It 'should be valid json' {
            $upackInfo | Should Not BeNullOrEmpty
        }

        It 'should contain name' {
            $upackInfo.Name | Should Be $Name
        }

        It 'should contain title' {
            $upackInfo.title | Should Be $Name
        }

        It 'should contain version' {
            $upackInfo.Version | Should Be $Version
        }

        It 'should contain description' {
            $upackInfo.Description | Should Be $Description
        }
    }

    It 'should cleanup temporary directories' {
        Get-ChildItem -Path $env:TEMP -Filter 'WhsCI+New-WhsCIAppPackage+*' |
            Should BeNullOrEmpty
    }
}

function Initialize-Test
{
    param(
        [string[]]
        $DirectoryName,

        [string[]]
        $FileName,

        [Switch]
        $WithoutArc
    )

    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    Install-Directory -Path $repoRoot

    if( -not $WithoutArc )
    {
        $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc'
        $arcDestinationPath = Join-Path -Path $repoRoot -ChildPath 'Arc'
        robocopy $arcSourcePath $arcDestinationPath '/MIR'
    }

    $DirectoryName | ForEach-Object { 
        $dirPath = $_
        $dirPath = Join-Path -Path $repoRoot -ChildPath $_
        Install-Directory -Path $dirPath
        foreach( $file in $FileName )
        {
            New-Item -Path (Join-Path -Path $dirPath -ChildPath $file) -ItemType 'File'
        }
    }

    return $repoRoot
}

function Invoke-NewWhsAppPackage
{
    [CmdletBinding()]
    param(
        [string]
        $Name = $defaultPackageName,
        [string]
        $Description = $defaultDescription,
        [string]
        $Version = $defaultVersion,
        [string[]]
        $Path,
        [string[]]
        $Include,
        [string[]]
        $Exclude
    )

    $excludeParam = @{ }
    if( $Exclude )
    {
        $excludeParam['Exclude'] = $Exclude
    }
    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    $Path = $Path | ForEach-Object { Join-Path -Path $repoRoot -ChildPath $_ }
    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    New-WhsCIAppPackage -RepositoryRoot $repoRoot `
                        -Name $Name `
                        -Description $Description `
                        -Version $Version `
                        -Path $Path `
                        -Include $Include `
                        @excludeParam
}

Describe 'New-WhsCIAppPackage when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Include '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html'
}

Describe 'New-WhsCIAppPackage when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Include '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html' `
                   -WithoutFiles 'code.cs'
}

Describe 'New-WhsCIAppPackage when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1','dir2' -Include '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html' `
                   -WithoutFiles 'code.cs'    
}

Describe 'New-WhsCIAppPackage when whitelist includes items that need to be excluded' {    
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Include '*.html' -Exclude 'html2.html','sub'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories 'dir1' `
                   -WithFiles 'html.html' `
                   -WithoutFiles 'html2.html','sub'
}

Describe 'New-WhsCIAppPackage when paths don''t exist' {

    $Global:Error.Clear()

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1','dir2' -Include '*' -ErrorAction SilentlyContinue

    It 'should write an error' {
        $Global:Error.Count | Should Be 2
        $Global:Error | Should Match 'does not exist'
    }

    It 'should not return anything' {
        $packagePath | Should BeNullOrEmpty
    }
}

Describe 'New-WhsCIAppPackage when path contains known directories to exclude' {
    $dirNames = @( 'dir1', 'dir1/.hg', 'dir1/.git', 'dir1/obj', 'dir1/sub/.hg', 'dir1/sub/.git', 'dir1/sub/obj' )
    $filenames = 'html.html'
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $filenames
    
    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Include '*.html'

    Assert-Package -At $packagePath `
                   -ContainsDirectories 'dir1' `
                   -WithFiles 'html.html' `
                   -WithoutFiles '.git','.hg','obj'
}

Describe 'New-WhsCIAppPackage when repository doesn''t use Arc' {
    $dirNames = @( 'dir1' )
    $fileNames = @( 'index.aspx' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WithoutArc

    $Global:Error.Clear()

    $packagePath = Invoke-NewWhsAppPackage -Path $dirNames -Include $fileNames -ErrorAction SilentlyContinue

    it 'should write an error' {
        $Global:Error.Count | Should Be 1
        $Global:Error | Should Match 'does not exist'
    }

    It 'should return nothing' {
        $packagePath | Should BeNullOrEmpty
    }

}