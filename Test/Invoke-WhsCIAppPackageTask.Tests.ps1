Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$defaultPackageName = 'WhsCITest'
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
        $Version,

        [Switch]
        $WithNoProGetParameters,

        [string[]]
        $HasDirectories,

        [string[]]
        $HasFiles,

        [string[]]
        $NotHasFiles,

        [string]
        $ShouldFailWithErrorMessage,
        
        [Switch]
        $ShouldNotCreatePackage,

        [Switch]
        $ShouldReallyUploadToProGet,

        [Switch]
        $ShouldNotUploadPackage,

        [Switch]
        $ShouldUploadPackage,

        [string[]]
        $HasThirdPartyDirectory,

        [string[]]
        $HasThirdPartyFile
    )

    if( -not $Version )
    {
        $now = [DateTime]::Now
        $midnight = [DateTime]::Today

        $Version = '{0}.{1}.{2}-final+80.feature-fubarsnafu.deadbee' -f $now.Year,$now.DayOfYear,($now - $midnight).TotalMilliseconds.ToInt32($null)
        Start-Sleep -Milliseconds 1
    }

    $taskParameter = @{
                            Name = $Name;
                            Description = $Description;
                            Path = $ForPath;
                            Include = $ThatIncludes;
                        }
    if( $ThatExcludes )
    {
        $taskParameter['Exclude'] = $ThatExcludes
    }
    if( $HasThirdPartyDirectory )
    {
        $taskParameter['ThirdPartyPath'] = $HasThirdPartyDirectory
    }

    $taskContext = New-WhsCITestContext -WithMockToolData -ForBuildRoot 'Repo'
    $taskContext.Version = $Version

    $mock = { return $false }
    if( $ShouldUploadPackage )
    {
        $mock = { return $true }
    }
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith $mock

    $packagesAtStart = @()
    if( $ShouldReallyUploadToProGet )
    {
        $taskContext.ProGetAppFeedUri = $UploadedTo = Get-ProGetUri -Environment 'Dev' -Feed 'upack/Test'
        $taskContext.ProGetCredential = $UploadedBy = Get-WhsSecret -Environment 'Dev' -Name 'svc-prod-lcsproget' -AsCredential
        $packagesAtStart = @()
        try
        {
            $packagesAtStart = Invoke-RestMethod -Uri ('{0}/packages?name={1}' -f $UPloadedTo,$Name) -ErrorAction Ignore
        }
        catch
        {
            $packagesAtStart = @()
        }
    }


    $threwException = $false
    $At = $null
    $taskContext.BuildMasterSession = $bmSession = New-BMSession -Uri 'http://buildmaster.example.com' -ApiKey 'fubarnsafu'

    $Global:Error.Clear()

    try
    {
        $At = New-WhsCIAppPackage -TaskContext $taskContext -TaskParameter $taskParameter
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }

    if( $ShouldFailWithErrorMessage )
    {
        It 'should fail with a terminating error' {
            $threwException | Should Be $true
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
            $threwException | Should Be $false
        }

        It 'should return package info' {
            $At | Should Exist
        }
    }

    #region
    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,($Version -replace '[\\/]','-')
    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $taskContext.BuildRoot
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

            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should not include {0}\{1} file' -f $dirName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Not Exist
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

        foreach( $dirName in $HasThirdPartyDirectory )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $dirName
            It ('should include {0} third-party directory' -f $dirName) {
                 $dirpath | Should Exist
            }
            
            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should include {0}\{1} third-party file' -f $dirName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }
    }

    if( $ShouldNotUploadPackage )
    {
        It 'should not upload package to ProGet' {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -Times 0
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -Times 0
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
        }
    }

    if( $ShouldUploadPackage )
    {
        It 'should upload package to ProGet' {
            if( $ShouldReallyUploadToProGet )
            {
                $packageInfo = Invoke-RestMethod -Uri ('{0}/packages?name={1}' -f $UploadedTo,$Name)
                $packageInfo | Should Not BeNullOrEmpty
                $packageInfo.latestVersion | Should Not Be $packagesAtStart.latestVersion
                $packageInfo.versions.Count | Should Be ($packagesAtStart.versions.Count + 1)
            }
            else
            {
                Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -ParameterFilter { 
                    #$DebugPreference = 'Continue'

                    $expectedMethod = 'Put'
                    Write-Debug -Message ('Method         expected  {0}' -f $expectedMethod)
                    Write-Debug -Message ('               actual    {0}' -f $Method)

                    Write-Debug -Message ('Uri            expected  {0}' -f $taskContext.ProGetAppFeedUri)
                    Write-Debug -Message ('               actual    {0}' -f $Uri)

                    $expectedContentType = 'application/octet-stream'
                    Write-Debug -Message ('ContentType    expected  {0}' -f $expectedContentType)
                    Write-Debug -Message ('               actual    {0}' -f $ContentType)

                    $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $UploadedBy.UserName,$UploadedBy.GetNetworkCredential().Password))
                    $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
                    Write-Debug -Message ('Authorization  expected  {0}' -f $creds)
                    Write-Debug -Message ('               actual    {0}' -f $Headers['Authorization'])

                    return $expectedMethod -eq $Method -and `
                           $taskContext.ProGetAppFeedUri -eq $Uri -and `
                           $expectedContentType -eq $ContentType -and `
                           $creds -eq $Headers['Authorization']
                }
            }
        }

        $expectedReleaseName = (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
        $expectedReleaseName = $expectedReleaseName -replace '/.*$',''
        $expectedAppName = $Name

        if( $ShouldFailWithErrorMessage )
        {
            It 'should not talk to BuildMaster' {
                Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -Times 0
                Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
                Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
            }
        }
        else
        {
            It 'should get release from BuildMaster' {
            
                Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    Write-Debug -Message ('Session.Uri     expected  {0}' -f $bmSession.Uri)
                    Write-Debug -Message ('                actual    {0}' -f $Session.Uri)
                    Write-Debug -Message ('Session.ApiKey  expected  {0}' -f $bmSession.ApiKey)
                    Write-Debug -Message ('                actual    {0}' -f $Session.ApiKey)
                    Write-Debug -Message ('Application     expected  {0}' -f $expectedAppName)
                    Write-Debug -Message ('                actual    {0}' -f $Application)
                    Write-Debug -Message ('Name            expected  {0}' -f $expectedReleaseName)
                    Write-Debug -Message ('                actual    {0}' -f $Name)
                    return $bmSession.Uri -eq $Session.Uri -and `
                           $bmSession.ApiKey -eq $Session.ApiKey -and `
                           $expectedAppName -eq $Application -and `
                           $expectedReleaseName -eq $Name
                }
            }

            It 'should create release package in BuildMaster' {
                Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    Write-Debug -Message ('Session.Uri                 expected  {0}' -f $bmSession.Uri)
                    Write-Debug -Message ('                            actual    {0}' -f $Session.Uri)
                    Write-Debug -Message ('Session.ApiKey              expected  {0}' -f $bmSession.ApiKey)
                    Write-Debug -Message ('                            actual    {0}' -f $Session.ApiKey)
                    Write-Debug -Message ('Release.id                  expected  get-bmrelease')
                    Write-Debug -Message ('                            actual    {0}' -f $Release.id)
                    $semVersion = [SemVersion.SemanticVersion]$Version
                    $expectedPackageNumber = '{0}.{1}.{2}' -f $semVersion.Major,$semVersion.Minor,$semVersion.Patch
                    Write-Debug -Message ('PackageNumber               expected  {0}' -f $expectedPackageNumber)
                    Write-Debug -Message ('                            actual    {0}' -f $PackageNumber)
                    Write-Debug -Message ('Variable.ProGetPackageName  expected  {0}' -f $Version)
                    Write-Debug -Message ('                            actual    {0}' -f $Variable['ProGetPackageName'])
                    return $bmSession.Uri -eq $Session.Uri -and `
                           $bmSession.ApiKey -eq $Session.ApiKey -and `
                           $Release.id -eq 'get-bmrelease' -and
                           $expectedPackageNumber -eq $PackageNumber -and
                           $Variable['ProGetPackageName'] -eq $Version
                }
            }

            It 'should start deploy in BuildMaster' {
                Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    Write-Debug -Message ('Session.Uri                 expected  {0}' -f $bmSession.Uri)
                    Write-Debug -Message ('                            actual    {0}' -f $Session.Uri)
                    Write-Debug -Message ('Session.ApiKey              expected  {0}' -f $bmSession.ApiKey)
                    Write-Debug -Message ('                            actual    {0}' -f $Session.ApiKey)
                    Write-Debug -Message ('Package.id                  expected  new-bmreleasepackage')
                    Write-Debug -Message ('                            actual    {0}' -f $Package.id)
                    return $bmSession.Uri -eq $Session.Uri -and `
                            $bmSession.ApiKey -eq $Session.ApiKey -and `
                            $Package.id -eq 'new-bmreleasepackage'
                }
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
        $WhenUploadFails,

        [Switch]
        $WhenReallyUploading,

        [Switch]
        $OnFeatureBranch,

        [Switch]
        $OnMasterBranch,

        [Switch]
        $OnReleaseBranch,

        [Switch]
        $OnPermanentReleaseBranch,

        [Switch]
        $OnDevelopBranch,

        [Switch]
        $OnHotFixBranch,

        [Switch]
        $OnBugFixBranch
    )

    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    Install-Directory -Path $repoRoot

    if( -not $WithoutArc )
    {
        $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc'
        $arcDestinationPath = Join-Path -Path $repoRoot -ChildPath 'Arc'
        robocopy $arcSourcePath $arcDestinationPath '/MIR' | Write-Verbose
    }

    $DirectoryName | ForEach-Object { 
        $dirPath = $_
        $dirPath = Join-Path -Path $repoRoot -ChildPath $_
        Install-Directory -Path $dirPath
        foreach( $file in $FileName )
        {
            New-Item -Path (Join-Path -Path $dirPath -ChildPath $file) -ItemType 'File' | Out-Null
        }
    }

    if( -not $WhenReallyUploading )
    {
        $result = 201
        if( $WhenUploadFails )
        {
            $result = 1
        }
        Mock -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ StatusCode = $result; } }.GetNewClosure()
    }

    Mock -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -Verifiable -MockWith { [pscustomobject]@{ 'id' = 'get-bmrelease'; } }
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -Verifiable -MockWith { [pscustomobject]@{ id = 'new-bmreleasepackage'; } }
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -Verifiable

    $gitBranch = 'origin/develop'
    if( $OnFeatureBranch )
    {
        $gitBranch = 'origin/feature/fubar'
    }
    if( $OnMasterBranch )
    {
        $gitBranch = 'origin/master'
    }
    if( $OnReleaseBranch )
    {
        $gitBranch = 'origin/release/5.1'
    }
    if( $OnPermanentReleaseBranch )
    {
        $gitBranch = 'origin/release'
    }
    if( $OnHotFixBranch )
    {
        $gitBranch = 'origin/hotfix/snafu'
    }
    if( $OnBugFixBranch )
    {
        $gitBranch = 'origin/bugfix/fubarnsafu'
    }

    $filter = { $Path -eq 'env:GIT_BRANCH' }
    $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -ParameterFilter $filter -MockWith $mock
    Mock -CommandName 'Get-Item' -ParameterFilter $filter -MockWith $mock

    return $repoRoot
}

Describe 'New-WhsCIAppPackage.when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs' `
                              -ShouldUploadPackage 
}

Describe 'New-WhsCIAppPackage.when whitelist includes items that need to be excluded' {    
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'html2.html','sub' `
                              -HasDirectories 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'html2.html','sub' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when paths don''t exist' {

    $Global:Error.Clear()

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*' `
                              -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                              -ShouldNotCreatePackage `
                              -ShouldNotUploadPackage `
                              -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIAppPackage.when path contains known directories to exclude' {
    $dirNames = @( 'dir1', 'dir1/.hg', 'dir1/.git', 'dir1/obj', 'dir1/sub/.hg', 'dir1/sub/.git', 'dir1/sub/obj' )
    $filenames = 'html.html'
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $filenames
    
    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles '.git','.hg','obj' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when repository doesn''t use Arc' {
    $dirNames = @( 'dir1' )
    $fileNames = @( 'index.aspx' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WithoutArc

    $Global:Error.Clear()

    Assert-NewWhsCIAppPackage -ForPath $dirNames `
                              -ThatIncludes $fileNames `
                              -ShouldFailWithErrorMessage 'does not exist' `
                              -ShouldNotCreatePackage `
                              -ShouldNotUploadPackage `
                              -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIAppPackage.when package upload fails' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WhenUploadFails

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage `
                              -ShouldFailWithErrorMessage 'failed to upload' `
                              -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIAppPackage.when really uploading package' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WhenReallyUploading

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldReallyUploadToProGet 
}

Describe 'New-WhsCIAppPackage.when not uploading to ProGet' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -WithNoProGetParameters `
                              -ShouldNotUploadPackage
}

Describe 'New-WhsCIAppPackage.when using WhatIf switch' {
    $Global:Error.Clear()

    $dirNames = @( 'dir1' )
    $fileNames = @( 'html.html' )
    $repoRoot = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    $context = New-WhsCITestContext -ForBuildRoot 'Repo'
    $parameters = @{
                        Name = 'Package';
                        Description = 'Description';
                        Path = $dirNames;
                        Include = '*.html'
                   }
    $result = New-WhsCIAppPackage -TaskContext $context -TaskParameter $parameters -WhatIf

    It 'should write no errors' {
        $Global:Error | Should BeNullOrEmpty
    }

    It 'should return nothing' {
        $result | Should BeNullOrEmpty
    }

    It 'should not create package' {
        Get-ChildItem -Path $TestDrive.FullName -Filter '*.upack' -Recurse | Should BeNullOrEmpty
    }

    It 'should not upload to ProGet' {
        Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -Times 0
    }
}

Describe 'New-WhsCIAppPackage.when building on master branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnMasterBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage 
}

Describe 'New-WhsCIAppPackage.when building on feature branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnFeatureBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldNotUploadPackage
}

Describe 'New-WhsCIAppPackage.when building on release branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnReleaseBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when building on long-lived release branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnPermanentReleaseBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when building on develop branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnDevelopBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage
}

Describe 'New-WhsCIAppPackage.when building on hot fix branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnHotFixBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldNotUploadPackage
}

Describe 'New-WhsCIAppPackage.when building on bug fix branch' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -OnBugFixBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasDirectories $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldNotUploadPackage
}

Describe 'New-WhsCIAppPackage.when including third-party items' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'thirdparty.txt' `
                              -HasDirectories 'dir1' `
                              -HasFiles 'html.html' `
                              -HasThirdPartyDirectory 'thirdparty','thirdpart2' `
                              -HasThirdPartyFile 'thirdparty.txt'
}

foreach( $parameterName in @( 'Name', 'Description', 'Path', 'Include' ) )
{
    Describe ('New-WhsCIAppPackage.when {0} property is omitted' -f $parameterName) {
        $parameter = @{
                        Name = 'Name';
                        Include = 'Include';
                        Description = 'Description';
                        Path = 'Path' 
                      }
        $parameter.Remove($parameterName)

        $context = New-WhsCITestContext
        $Global:Error.Clear()
        $threwException = $false
        try
        {
            New-WhsCIAppPackage -TaskContext $context -TaskParameter $parameter
        }
        catch
        {
            $threwException = $true
            Write-Error -ErrorRecord $_ -ErrorAction SilentlyContinue
        }

        It 'should fail' {
            $threwException | Should Be $true
            $Global:Error | Should BeLike ('*Element ''{0}'' is mandatory.' -f $parameterName)
        }
    }
}

Describe 'New-WhsCIAppPackage.when path to package doesn''t exist' {
    $context = New-WhsCITestContext

    $Global:Error.Clear()

    It 'should throw an exception' {
        { New-WhsCIAppPackage -TaskContext $context -TaskParameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = 'fubar' } } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* Path`[0`] ''{0}'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}


Describe 'New-WhsCIAppPackage.when path to third-party item doesn''t exist' {
    $context = New-WhsCITestContext

    $Global:Error.Clear()

    It 'should throw an exception' {
        { New-WhsCIAppPackage -TaskContext $context -TaskParameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = '.' ; ThirdPartyPath = 'fubar' } } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* ThirdPartyPath`[0`] ''{0}'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }

}