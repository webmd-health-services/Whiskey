Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$defaultPackageName = 'WhsCITest'
$defaultDescription = 'A package created to test the Invoke-WhsCIAppPackageTask function in the WhsCI module.'
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
        $Name = $defaultPackageName,

        [string]
        $ForApplicationName,

        [string]
        $Description = $defaultDescription,

        [string]
        $Version,

        [Switch]
        $WithNoProGetParameters,

        [string[]]
        $HasRootItems,

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

        [Switch]
        $ShouldWriteNoErrors,

        [Switch]
        $ShouldReturnNothing,

        [string[]]
        $HasThirdPartyRootItem,

        [string[]]
        $WithThirdPartyRootItem,

        [string[]]
        $HasThirdPartyFile,

        [string]
        $FromSourceRoot,

        [string[]]
        $MissingRootItems,

        [Switch]
        $WhenExcludingArc,

        [Switch]
        $ThenArcNotInPackage,

        [Switch]
        $WhenRunByDeveloper,

        [Switch]
        $ShouldNotSetPackageVariables
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
    if( $HasThirdPartyRootItem )
    {
        $taskParameter['ThirdPartyPath'] = $WithThirdPartyRootItem
    }
    if( $FromSourceRoot )
    {
        $taskParameter['SourceRoot'] = $FromSourceRoot
    }
    if( $WhenExcludingArc )
    {
        $taskParameter['ExcludeArc'] = $true
    }

    $byWhoArg = @{ 'ByDeveloper' = $true }
    if( $ShouldUploadPackage )
    {
        $byWhoArg = @{ 'ByBuildServer' = $true }
    }

    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $Version }.GetNewClosure()

    $taskContext = New-WhsCITestContext -WithMockToolData -ForBuildRoot 'Repo' @byWhoArg
    $taskContext.Version = $Version
    if( $ForApplicationName )
    {
        $taskContext.ApplicationName = $ForApplicationName
    }

    $packagesAtStart = @()
    if( $ShouldReallyUploadToProGet )
    {
        $progetUri = 'https://proget.dev.webmd.com/'
        $appFeedUri = [string](New-Object 'Uri' ([uri]$progetUri),'upack/Tests')
        $credential = New-Credential -UserName 'aaron-admin' -Password 'aaron'

        $taskContext.ProGetSession = [pscustomobject]@{
                                                        Uri = $progetUri;
                                                        AppFeedUri = $appFeedUri;
                                                        Credential = $credential;
                                                        AppFeed = 'upack/Test'
                                                      }
        $packagesAtStart = @()
        try
        {
            $packagesAtStart = Invoke-RestMethod -Uri ('{0}/packages?name={1}' -f $appFeedUri,$Name) -ErrorAction Ignore
        }
        catch
        {
            $packagesAtStart = @()
        }
    }


    $threwException = $false
    $At = $null

    $Global:Error.Clear()

    $whatIfParam = @{ }
    if( $WhenRunByDeveloper )
    {
        $whatIfParam['WhatIf'] = $true
    }
        
    function Get-TempDirCount
    {
        Get-ChildItem -Path $env:TEMP -Filter 'WhsCI+Invoke-WhsCIAppPackageTask+*' | 
            Measure-Object | 
            Select-Object -ExpandProperty Count
    }

    $preTempDirCount = Get-TempDirCount
    try
    {
        $At = Invoke-WhsCIAppPackageTask -TaskContext $taskContext -TaskParameter $taskParameter @whatIfParam
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }
    $postTempDirCount = Get-TempDirCount

    if( $ShouldReturnNothing -or $ShouldFailWithErrorMessage )
    {
        It 'should not return package info' {
            $At | Should BeNullOrEmpty
        }
    }
    else
    {
        It 'should return package info' {
            $At | Should Exist
        }
    }

    if( $ShouldWriteNoErrors )
    {
        It 'should not write any errors' {
            $Global:Error | Should BeNullOrEmpty
        }
    }

    if( $ShouldFailWithErrorMessage )
    {
        It 'should fail with a terminating error' {
            $threwException | Should Be $true
        }

        It ('should fail with error message that matches ''{0}''' -f $ShouldFailWithErrorMessage) {
            $Global:Error | Should Match $ShouldFailWithErrorMessage
        }
    }
    else
    {
        It 'should not fail' {
            $threwException | Should Be $false
        }
    }

    #region
    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,($Version -replace '[\\/]','-')
    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $taskContext.BuildRoot
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    It 'should cleanup temporary directories' {
        $postTempDirCount | Should Be $preTempDirCount
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
        foreach( $itemName in $MissingRootItems )
        {
            It ('should not include {0} item' -f $itemName) {
                Join-Path -Path $packageContentsPath -ChildPath $itemName | Should Not Exist
            }
        }

        foreach( $itemName in $HasRootItems )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} item' -f $itemName) {
                 $dirpath | Should Exist
            }
            foreach( $fileName in $HasFiles )
            {
                It ('should include {0}\{1} file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }

            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should not include {0}\{1} file' -f $itemName,$fileName) {
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

        $arcPath = Join-Path -Path $packageContentsPath -ChildPath 'Arc'
        if( $ThenArcNotInPackage )
        {
            It 'should not include Arc' {
                $arcPath | Should Not Exist
            }
        }
        else
        {
            $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc' -Resolve

            It 'should include Arc' {
                $arcPath | Should Exist
            }

            It ('should include all files in Arc') {
                foreach( $sourceItem in (Get-ChildItem -Path $arcSourcePath -File -Recurse) )
                {
                    $destinationItem = $sourceItem.FullName -replace ([regex]::Escape($arcSourcePath),$arcPath)
                    $destinationItem | Should Exist
                }
            }
        }

        foreach( $itemName in $HasThirdPartyRootItem )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} third-party root item' -f $itemName) {
                 $dirpath | Should Exist
            }
            
            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should include {0}\{1} third-party file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }
    }

    if( $ShouldNotUploadPackage )
    {
        It 'should not upload package to ProGet' {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -Times 0
        }
    }

    if( $ShouldUploadPackage )
    {
        It 'should upload package to ProGet' {
            if( $ShouldReallyUploadToProGet )
            {
                $packageInfo = Invoke-RestMethod -Uri ('{0}/packages?name={1}' -f $appFeedUri,$Name)
                $packageInfo | Should Not BeNullOrEmpty
                $packageInfo.latestVersion | Should Not Be $packagesAtStart.latestVersion
                $packageInfo.versions.Count | Should Be ($packagesAtStart.versions.Count + 1)
            }
            else
            {
                Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'WhsCI' -ParameterFilter { 
                    $DebugPreference = 'Continue'

                    $expectedMethod = 'Put'
                    Write-Debug -Message ('Method         expected  {0}' -f $expectedMethod)
                    Write-Debug -Message ('               actual    {0}' -f $Method)

                    $expectedUri = $taskContext.ProGetSession.AppFeedUri
                    Write-Debug -Message ('Uri            expected  {0}' -f $expectedUri)
                    Write-Debug -Message ('               actual    {0}' -f $Uri)

                    $expectedContentType = 'application/octet-stream'
                    Write-Debug -Message ('ContentType    expected  {0}' -f $expectedContentType)
                    Write-Debug -Message ('               actual    {0}' -f $ContentType)

                    $credential = $taskContext.ProGetSession.Credential
                    $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $credential.UserName,$credential.GetNetworkCredential().Password))
                    $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
                    Write-Debug -Message ('Authorization  expected  {0}' -f $creds)
                    Write-Debug -Message ('               actual    {0}' -f $Headers['Authorization'])

                    return $expectedMethod -eq $Method -and `
                           $expectedUri -eq $Uri -and `
                           $expectedContentType -eq $ContentType -and `
                           $creds -eq $Headers['Authorization']
                }
            }
        }

        if( $ShouldNotSetPackageVariables )
        {
            It 'should not set package version package variable' {
                $taskContext.PackageVariables.ContainsKey('ProGetPackageVersion') | Should Be $false
            }

            It 'should not set legacy package version package variable' {
                $taskContext.PackageVariables.ContainsKey('ProGetPackageName') | Should Be $false
            }
            It 'should not set package Application name' {
                $taskContext.ApplicationName | Should BeNullOrEmpty
            }         
        }
        else
        {
            It 'should set package version package variable' {
                $taskContext.PackageVariables.ContainsKey('ProGetPackageVersion') | Should Be $true
                $taskContext.PackageVariables['ProGetPackageVersion'] | Should Be $Version.ToString()
            }

            It 'should set legacy package version package variable' {
                $taskContext.PackageVariables.ContainsKey('ProGetPackageName') | Should Be $true
                $taskContext.PackageVariables['ProGetPackageName'] | Should Be $Version.ToString()
            }
            if( $ForApplicationName )
            {
                It 'should not set package Application Name' {
                    $taskContext.ApplicationName | Should Be $ForApplicationName
                }            
            }
            else
            {           
                It 'should set package application name' {
                    $taskContext.ApplicationName | Should Be $Name
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

        [string[]]
        $RootFileName,

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
        $OnBugFixBranch,

        [string]
        $SourceRoot,

        [Switch]
        $AsDeveloper
    )

    $repoRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Repo'
    Install-Directory -Path $repoRoot
    if( -not $SourceRoot )
    {
        $SourceRoot = $repoRoot
    }
    else
    {
        $SourceRoot = Join-Path -Path $repoRoot -ChildPath $SourceRoot
    }
    Install-Directory -Path $repoRoot

    $arcDestinationPath = Join-Path -Path $repoRoot -ChildPath 'Arc'
    if( -not $WithoutArc )
    {
        $arcSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Arc'
        robocopy $arcSourcePath $arcDestinationPath '/MIR' | Write-Verbose
    }
    else
    {
        Get-Item -Path $arcDestinationPath -ErrorAction Ignore | Remove-Item -Recurse -WhatIf
    }

    $DirectoryName | ForEach-Object { 
        $dirPath = $_
        $dirPath = Join-Path -Path $SourceRoot -ChildPath $_
        Install-Directory -Path $dirPath
        foreach( $file in $FileName )
        {
            New-Item -Path (Join-Path -Path $dirPath -ChildPath $file) -ItemType 'File' | Out-Null
        }
    }

    foreach( $itemName in $RootFileName )
    {
        New-Item -Path (Join-Path -Path $SourceRoot -ChildPath $itemName) -ItemType 'File' | Out-Null
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

    if( -not $AsDeveloper )
    {
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
    }

    return $repoRoot
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when excluding Arc' {
    $file = 'project.json'
    $outputFilePath = Initialize-Test -RootFileName $file
    Assert-NewWhsCIAppPackage -ForPath $file `
                              -WhenExcludingArc `
                              -HasRootItems $file `
                              -ThenArcNotInPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging root files' {
    $file = 'project.json'
    $thirdPartyFile = 'thirdparty.txt'
    $outputFilePath = Initialize-Test -RootFileName $file,$thirdPartyFile
    Assert-NewWhsCIAppPackage -ForPath $file `
                              -WithThirdPartyRootItem $thirdPartyFile `
                              -HasThirdPartyRootItem $thirdPartyFile `
                              -HasRootItems $file
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging everything in a directory as a developer' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames `
                                      -AsDeveloper

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldNotUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs' `
                              -ShouldUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'code.cs' `
                              -ShouldUploadPackage 
}

Describe 'Invoke-WhsCIAppPackageTask.when whitelist includes items that need to be excluded' {    
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'html2.html','sub' `
                              -HasRootItems 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles 'html2.html','sub' `
                              -ShouldUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when paths don''t exist' {

    $Global:Error.Clear()

    Initialize-Test

    Assert-NewWhsCIAppPackage -ForPath 'dir1','dir2' `
                              -ThatIncludes '*' `
                              -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                              -ShouldNotCreatePackage `
                              -ShouldNotUploadPackage `
                              -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIAppPackageTask.when path contains known directories to exclude' {
    $dirNames = @( 'dir1', 'dir1/.hg', 'dir1/.git', 'dir1/obj', 'dir1/sub/.hg', 'dir1/sub/.git', 'dir1/sub/obj' )
    $filenames = 'html.html'
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $filenames
    
    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems 'dir1' `
                              -HasFiles 'html.html' `
                              -NotHasFiles '.git','.hg','obj' `
                              -ShouldUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when repository doesn''t use Arc' {
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

Describe 'Invoke-WhsCIAppPackageTask.when repository doesn''t use Arc and ExcludeArc flag is set' {
    $dirNames = @( 'dir1' )
    $fileNames = @( 'index.aspx' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WithoutArc

    $Global:Error.Clear()

    Assert-NewWhsCIAppPackage -ForPath $dirNames `
                              -ThatIncludes $fileNames `
                              -WhenExcludingArc `
                              -ShouldWriteNoErrors `
                              -ShouldUploadPackage `
                              -ThenArcNotInPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when package upload fails' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WhenUploadFails

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage `
                              -ShouldFailWithErrorMessage 'failed to upload' `
                              -ShouldNotSetPackageVariables `
                              -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIAppPackageTask.when really uploading package' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -WhenReallyUploading

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldReallyUploadToProGet 
}

Describe 'Invoke-WhsCIAppPackageTask.when not uploading to ProGet' {
    $dirNames = @( 'dir1'  )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -WithNoProGetParameters `
                              -ShouldNotUploadPackage
}

Describe 'Invoke-WhsCIAppPackageTask.when using WhatIf switch' {
    $dirNames = @( 'dir1' )
    $fileNames = @( 'html.html' )
    $repoRoot = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    Assert-NewWhsCIAppPackage -ForPath $dirNames `
                              -ThatIncludes '*.html' `
                              -WhenRunByDeveloper `
                              -ShouldNotCreatePackage `
                              -ShouldNotUploadPackage `
                              -ShouldWriteNoErrors `
                              -ShouldReturnNothing
}

Describe 'Invoke-WhsCIAppPackageTask.when using WhatIf switch and not including Arc' {
    $Global:Error.Clear()

    $dirNames = @( 'dir1' )
    $fileNames = @( 'html.html' )
    $repoRoot = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    Assert-NewWhsCIAppPackage -ForPath $dirNames `
                              -ThatIncludes '*.html' `
                              -WhenRunByDeveloper `
                              -WhenExcludingArc `
                              -ThenArcNotInPackage `
                              -ShouldNotCreatePackage `
                              -ShouldNotUploadPackage `
                              -ShouldWriteNoErrors `
                              -ShouldReturnNothing

}

Describe 'Invoke-WhsCIAppPackageTask.when including third-party items' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'thirdparty.txt' `
                              -HasRootItems 'dir1' `
                              -HasFiles 'html.html' `
                              -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                              -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                              -HasThirdPartyFile 'thirdparty.txt'
}

foreach( $parameterName in @( 'Name', 'Description', 'Path', 'Include' ) )
{
    Describe ('Invoke-WhsCIAppPackageTask.when {0} property is omitted' -f $parameterName) {
        $parameter = @{
                        Name = 'Name';
                        Include = 'Include';
                        Description = 'Description';
                        Path = 'Path' 
                      }
        $parameter.Remove($parameterName)

        $context = New-WhsCITestContext -ForDeveloper
        $Global:Error.Clear()
        $threwException = $false
        try
        {
            Invoke-WhsCIAppPackageTask -TaskContext $context -TaskParameter $parameter
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

Describe 'Invoke-WhsCIAppPackageTask.when path to package doesn''t exist' {
    $context = New-WhsCITestContext -ForDeveloper

    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhsCIAppPackageTask -TaskContext $context -TaskParameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = 'fubar' } } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* Path`[0`] ''{0}'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}

function New-TaskParameter
{
     @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = '.' ; ThirdPartyPath = 'fubar' }
}

Describe 'Invoke-WhsCIAppPackageTask.when path to third-party item doesn''t exist' {
    $context = New-WhsCITestContext -ForDeveloper

    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhsCIAppPackageTask -TaskContext $context -TaskParameter (New-TaskParameter) } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* ThirdPartyPath`[0`] ''{0}'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}

Describe 'Invoke-WhsCIAppPackageTask.when application root isn''t the root of the repository' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -SourceRoot 'app'

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -ThatExcludes 'thirdparty.txt' `
                              -HasRootItems 'app\dir1' `
                              -HasFiles 'html.html' `
                              -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                              -HasThirdPartyRootItem 'app\thirdparty','app\thirdpart2' `
                              -HasThirdPartyFile 'thirdparty.txt' `
                              -FromSourceRoot 'app'
}

Describe 'Invoke-WhsCIAppPackageTask.when custom application root doesn''t exist' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    $context = New-WhsCITestContext -ForDeveloper

    $Global:Error.Clear()

    $parameter = New-TaskParameter
    $parameter['SourceRoot'] = 'app'

    { Invoke-WhsCIAppPackageTask -TaskContext $context -TaskParameter $parameter } | Should Throw

    It 'should fail to resolve the path' {
        $Global:Error | Should Match 'SourceRoot\b.*\bapp\b.*\bdoes not exist'
    }
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging everything with a custom application name' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )

    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames `
                                      -OnDevelopBranch

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatIncludes '*.html' `
                              -HasRootItems $dirNames `
                              -HasFiles 'html.html' `
                              -ShouldUploadPackage `
                              -ForApplicationName 'foo' `
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging given a full relative path' {
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))
    $forPath = @{ $path = $file }

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhsCIAppPackage -ForPath $path -HasRootItems $file 
}

Describe 'Invoke-WhsCIAppPackageTask.when packaging given a full relative path with override syntax' {
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))
    $forPath = @{ $path = $file }

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhsCIAppPackage -ForPath $forPath -HasRootItems $file 
}

Describe 'Invoke-WhsCIAppPackageTask.when including third-party items with override syntax' {
    $dirNames = @( 'dir1', 'app\thirdparty')
    $fileNames = @( 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhsCIAppPackage -ForPath 'dir1' `
                              -ThatExcludes 'thirdparty.txt' `
                              -HasRootItems 'dir1' `
                              -WithThirdPartyRootItem @{ 'app\thirdparty' = 'thirdparty' } `
                              -HasThirdPartyRootItem 'thirdparty' `
                              -HasThirdPartyFile 'thirdparty.txt' 
}