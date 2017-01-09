
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)

$defaultPackageName = 'WhsCITest'
$defaultVersion = '1.2.3-final'
$defaultDescription = 'A package created to test the New-WhsCIAppPackage function in the WhsCI module.'
$feedUri = 'snafufurbar'
$feedCredential = New-Credential -UserName 'fubar' -Password 'snafu'

function Assert-NewWhsCIAppPackage
{
    [CmdletBinding()]
    param(
        [string[]]
        $ForPath,

        [string[]]
        $ThatIncludes,

        [string[]]
        $ThatExcludes,

        [string]
        $UploadedTo = $feedUri,

        [pscredential]
        $UploadedBy = $feedCredential,

        [string]
        $Name = $defaultPackageName,

        [string]
        $Description = $defaultDescription,

        [string]
        $Version = $defaultVersion,

        [string[]]
        $HasDirectories,

        [string[]]
        $HasFiles,

        [string[]]
        $NotHasFiles,

        [string]
        $ShouldFailWithErrorMessage,
        
        [Switch]
        $ShouldNotCreatePackage
    )

    $Global:Error.Clear()
    $excludeParam = @{ }
    if( $ThatExcludes )
    {
        $excludeParam['Exclude'] = $ThatExcludes
    }

    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    $ForPath = $ForPath | ForEach-Object { Join-Path -Path $repoRoot -ChildPath $_ }
    $failed = $false
    $At = $null
    try
    {
        $At = New-WhsCIAppPackage -RepositoryRoot $repoRoot `
                                  -Name $Name `
                                  -Description $Description `
                                  -Version $Version `
                                  -Path $ForPath `
                                  -Include $ThatIncludes `
                                  -ProGetPackageUri $UploadedTo `
                                  -ProGetCredential $UploadedBy `
                                  @excludeParam
    }
    catch
    {
        $failed = $true
        Write-Error -ErrorRecord $_
    }

    if( $ShouldFailWithErrorMessage )
    {
        It 'should fail with a terminating error' {
            $failed | Should Be $true
        }

        It ('should fail with error message that matches ''{0}''' -f $ShouldFailWithErrorMessage) {
            $Global:Error | Should Match $ShouldFailWithErrorMessage
        }

        It 'should not return package info' {
            $At | Should BeNullOrEmpty
        }
    }
    else
    {
        It 'should not fail' {
            $failed | Should Be $false
        }

        It 'should return package info' {
            $At | Should Exist
        }
    }

    #region
    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,$Version
    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $repoRoot
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName


    It 'should cleanup temporary directories' {
        Get-ChildItem -Path $env:TEMP -Filter 'WhsCI+New-WhsCIAppPackage+*' |
            Should BeNullOrEmpty
    }

    if( $ShouldNotCreatePackage )
    {
        It 'should not create a package' {
            $packagePath | Should Not Exist
        }
        return
    }
    else
    {
        It 'should create a package' {
            $packagePath | Should Exist
        }
    }

    Expand-Item -Path $packagePath -OutDirectory $expandPath

    $upackJsonPath = Join-Path -Path $expandPath -ChildPath 'upack.json'

    Context 'the package' {
        foreach( $dirName in $HasDirectories )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $dirName
            It ('should include {0} directory' -f $dirName) {
                 $dirpath | Should Exist
            }
            foreach( $fileName in $HasFiles )
            {
                It ('should include {0}\{1} file' -f $dirName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }

        if( $NotHasFiles )
        {
            foreach( $item in $NotHasFiles )
            {
                It ('should exclude {0} files' -f $item ) {
                    Get-ChildItem -Path $packageContentsPath -Filter $item -Recurse | Should BeNullOrEmpty
                }
            }
        }

        It 'should include ProGet universal package metadata (upack.json)' {
            $upackJsonPath | Should Exist
        }

        $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc' -Resolve
        $arcPath = Join-Path -Path $packageContentsPath -ChildPath 'Arc'

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

    It 'should upload package to ProGet' {
        Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -ParameterFilter { 
            #$DebugPreference = 'Continue'

            $expectedMethod = 'Put'
            Write-Debug -Message ('Method         expected  {0}' -f $expectedMethod)
            Write-Debug -Message ('               actual    {0}' -f $Method)

            Write-Debug -Message ('Uri            expected  {0}' -f $UploadedTo)
            Write-Debug -Message ('               actual    {0}' -f $Uri)

            $expectedContentType = 'application/octet-stream'
            Write-Debug -Message ('ContentType    expected  {0}' -f $expectedContentType)
            Write-Debug -Message ('               actual    {0}' -f $ContentType)

            $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $UploadedBy.UserName,$UploadedBy.GetNetworkCredential().Password))
            $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
            Write-Debug -Message ('Authorization  expected  {0}' -f $creds)
            Write-Debug -Message ('               actual    {0}' -f $Headers['Authorization'])

            return $expectedMethod -eq $Method -and $UploadedTo -eq $Uri -and $expectedContentType -eq $ContentType -and $creds -eq $Headers['Authorization']
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
    #endregion
}

function Initialize-Test
{
    param(
        [string[]]
        $DirectoryName,

        [string[]]
        $FileName,

        [Switch]
        $WithoutArc,

        [Switch]
        $WhenUploadFails
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

    $result = 201
    if( $WhenUploadFails )
    {
        $result = 1
    }
    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ StatusCode = $result; } }.GetNewClosure()

    return $repoRoot
}

Describe 'New-WhsCIAppPackage when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html'
}

Describe 'New-WhsCIAppPackage when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs'
}

Describe 'New-WhsCIAppPackage when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs'    
}

Describe 'New-WhsCIAppPackage when whitelist includes items that need to be excluded' {    
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'html2.html','sub' `
                              -HasDirectories 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'html2.html','sub'
}

Describe 'New-WhsCIAppPackage when paths don''t exist' {

    $Global:Error.Clear()

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*' `
                              -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                              -ShouldNotCreatePackage `
                              -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIAppPackage when path contains known directories to exclude' {
    $dirNames = @( 'dir1', 'dir1/.hg', 'dir1/.git', 'dir1/obj', 'dir1/sub/.hg', 'dir1/sub/.git', 'dir1/sub/obj' )
    $filenames = 'html.html'
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $filenames
    
    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles '.git','.hg','obj'
}

Describe 'New-WhsCIAppPackage when repository doesn''t use Arc' {
    $dirNames = @( 'dir1' )
    $fileNames = @( 'index.aspx' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WithoutArc

    $Global:Error.Clear()

    Assert-NewWhsCIAppPackage -ForPath $dirNames `
                              -ThatIncludes $fileNames `
                              -ShouldFailWithErrorMessage 'does not exist' `
                              -ShouldNotCreatePackage `
                              -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIAppPackage when package upload fails' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WhenUploadFails

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldFailWithErrorMessage 'failed to upload' `
                              -ErrorAction SilentlyContinue
}
