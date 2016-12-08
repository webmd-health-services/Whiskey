
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)

function Assert-Package
{
    param(
        [string]
        $At,
        [string[]]
        $ContainsDirectories,
        [string[]]
        $WithFiles,
        [string[]]
        $WithoutFiles
   )

    Context 'the package' {
        It 'should exist' {
            $At | Should Exist
        }

        $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
        Expand-Item -Path $At -OutDirectory $expandPath

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
    }

    It 'should cleanup temporary directories' {
        Get-ChildItem -Path $env:TEMP -Filter 'WhsCI+New-WhsAppPackage+*' |
            Should BeNullOrEmpty
    }
}

function Initialize-Test
{
    param(
        [string[]]
        $DirectoryName,

        [string[]]
        $FileName
    )

    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    Install-Directory -Path $repoRoot

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
    param(
        [string[]]
        $Path,
        [string[]]
        $Whitelist
    )

    $outFile = Join-Path -Path $TestDrive.Fullname -ChildPath 'package.upack'
    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    $Path = $Path | ForEach-Object { Join-Path -Path $repoRoot -ChildPath $_ }
    New-WhsAppPackage -OutputFile $outFile -Path $Path -Whitelist $Whitelist
}

Describe 'New-WhsAppPackage when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Whitelist '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html'
}

Describe 'New-WhsAppPackage when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1' -Whitelist '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html' `
                   -WithoutFiles 'code.cs'
}

Describe 'New-WhsAppPackage when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    $packagePath = Invoke-NewWhsAppPackage -Path 'dir1','dir2' -Whitelist '*.html'

    Assert-Package -At $packagePath.FullName `
                   -ContainsDirectories $dirNames `
                   -WithFiles 'html.html' `
                   -WithoutFiles 'code.cs'    
}