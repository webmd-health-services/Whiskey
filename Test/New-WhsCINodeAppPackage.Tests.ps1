
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function Assert-NodePackageCreated
{
    param(
        [string[]]
        $WithExtraFile,

        [string[]]
        $WithThirdPartyPath
    )

    $packageName = 'name'
    $packageDescription = 'description'
    $packagePath = 'path1','path2'
    $packageExclude = 'three','four'
    $taskContext = New-WhsCITestContext -WithMockToolData
    
    $taskParameter = @{
                            Name = $packageName;
                            Description = $packageDescription;
                            Path = $packagePath;
                            Exclude = $packageExclude;
                      }

    if( $WithThirdPartyPath )
    {
        $taskParameter['ThirdPartyPath'] = $WithThirdPartyPath
    }

    if( $WithExtraFile )
    {
        $taskParameter['Include'] = $WithExtraFile
    }

    Mock -CommandName 'New-WhsCIAppPackage' -ModuleName 'WhsCI' -Verifiable

    New-WhsCINodeAppPackage -TaskContext $taskContext -TaskParameter $taskParameter
    
    It 'should pass parameters to New-WhsCIAppPackage' {
        Assert-MockCalled -CommandName 'New-WhsCIAppPackage' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('RepositoryRoot      expected  {0}' -f $taskContext.TaskPathRoot)
            Write-Debug -Message ('                    actual    {0}' -f $RepositoryRoot)
            Write-Debug -Message ('Name                expected  {0}' -f $packageName)
            Write-Debug -Message ('                    actual    {0}' -f $Name)
            Write-Debug -Message ('Description         expected  {0}' -f $packageDescription)
            Write-Debug -Message ('                    actual    {0}' -f $Description)
            Write-Debug -Message ('Version             expected  {0}' -f $taskContext.Version)
            Write-Debug -Message ('                    actual    {0}' -f $Version)
            
            $packagePath = $packagePath -join ';'
            $Path = $Path -join ';'
            Write-Debug -Message ('Path                expected  {0}' -f $packagePath)
            Write-Debug -Message ('                    actual    {0}' -f $Path)

            Write-Debug -Message ('ProGetPackageUri    expected  {0}' -f $taskContext.ProGetAppFeedUri)
            Write-Debug -Message ('                    actual    {0}' -f $ProGetPackageUri)
            Write-Debug -Message ('ProGetCredential    expected  {0}' -f $taskContext.ProGetCredential)
            Write-Debug -Message ('                    actual    {0}' -f $ProGetCredential)
            Write-Debug -Message ('BuildMasterSession  expected  {0}' -f $taskContext.BuildMasterSession)
            Write-Debug -Message ('                    actual    {0}' -f $BuildMasterSession)

            $packageExclude = $packageExclude -join ';'
            $Exclude = $Exclude -join ';'
            Write-Debug -Message ('Exclude             expected  {0}' -f $packageExclude)
            Write-Debug -Message ('                    actual    {0}' -f $Exclude)

            [object]::ReferenceEquals($taskContext.TaskPathRoot,$RepositoryRoot) -and `
            [object]::ReferenceEquals($packageName,$Name) -and `
            [object]::ReferenceEquals($packageDescription,$Description) -and `
            [object]::ReferenceEquals($taskContext.Version,$Version) -and `
            [object]::ReferenceEquals($taskContext.ProGetAppFeedUri,$ProGetPackageUri) -and `
            [object]::ReferenceEquals($taskContext.ProGetCredential,$ProGetCredential) -and `
            [object]::ReferenceEquals($taskContext.BuildMasterSession,$BuildMasterSession) -and `
            $packagePath -eq $Path -and `
            $packageExclude -eq $Exclude
        }
    }

    It 'should pass default whitelist' {
        Assert-MockCalled -CommandName 'New-WhsCIAppPackage' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $missing = Invoke-Command { $WithExtraFile ; '*.js','*.css' } | Where-Object { $Include -notcontains $_ }

            $packageInclude = $WithExtraFile -join ';'
            $Include = $Include -join ';'
            Write-Debug -Message ('Include  expected  {0}' -f $packageInclude)
            Write-Debug -Message ('         actual    {0}' -f $Include)
            Write-Debug -Message ('         missing   {0}' -f ($missing -join ';'))
            if( $missing )
            {
                return $false
            }
            else
            {
                return $true
            }
        }
    }

    It 'should pass node_modules as third-party path' {
        Assert-MockCalled -CommandName 'New-WhsCIAppPackage' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $packageThirdPartyPath = $WithThirdPartyPath -join ';'
            $thirdPartyPathCsv = $ThirdPartyPath -join ';'
            Write-Debug -Message ('ThirdPartyPath                        expected  {0}' -f $packageThirdPartyPath)
            Write-Debug -Message ('                                      actual    {0}' -f $thirdPartyPathCsv)

            return ($ThirdPartyPath -contains 'node_modules')
        }
    }

    It 'should pass node_modules as third party path once' {
        Assert-MockCalled -CommandName 'New-WhsCIAppPackage' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $nodeModulesCount = $ThirdPartyPath | Where-Object { $_ -eq 'node_modules' } | Measure-Object | Select-Object -ExpandProperty 'Count'

            Write-Debug -Message ('ThirdPartyPath[''node_modules''].Count  expected  1')
            Write-Debug -Message ('                                      actual    {0}' -f $nodeModulesCount)

            return $nodeModulesCount -eq 1
        }
    }
}

Describe 'New-WhsCINodeAppPackage.when called' {
    Assert-NodePackageCreated
}

Describe 'New-WhsCINodeAppPackage.when called with extra files' {
    Assert-NodePackageCreated -WithExtraFile 'one','two'
}

Describe 'New-WhsCINodeAppPackage.when called with duplicate third-party path' {
    Assert-NodePackageCreated -WithThirdPartyPath 'node_modules'
}

Describe 'New-WhsCINodeAppPackage.when called with third-party path' {
    Assert-NodePackageCreated -WithThirdPartyPath 'thirdfirst','thirdsecond'
}