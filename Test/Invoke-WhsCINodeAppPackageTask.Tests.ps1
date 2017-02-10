
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
    $context = New-WhsCITestContext -WithMockToolData
    
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

    Mock -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -Verifiable

    Invoke-WhsCINodeAppPackageTask -TaskContext $context -TaskParameter $taskParameter
    
    It 'should pass parameters to Invoke-WhsCIAppPackageTask' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Name                expected  {0}' -f $packageName)
            Write-Debug -Message ('                    actual    {0}' -f $TaskParameter['Name'])
            Write-Debug -Message ('Description         expected  {0}' -f $packageDescription)
            Write-Debug -Message ('                    actual    {0}' -f $TaskParameter['Description'])
            
            $packagePath = $packagePath -join ';'
            $path = $TaskParameter['Path'] -join ';'
            Write-Debug -Message ('Path                expected  {0}' -f $packagePath)
            Write-Debug -Message ('                    actual    {0}' -f $path)

            $packageExclude = $packageExclude -join ';'
            $exclude = $TaskParameter['Exclude'] -join ';'
            Write-Debug -Message ('Exclude             expected  {0}' -f $packageExclude)
            Write-Debug -Message ('                    actual    {0}' -f $exclude)

            $contextsSame = [object]::ReferenceEquals($context,$TaskContext)
            Write-Debug -Message ('Context = TaskContext         {0}' -f $contextsSame)

            $contextsSame -and `
            [object]::ReferenceEquals($packageName,$TaskParameter['Name']) -and `
            [object]::ReferenceEquals($packageDescription,$TaskParameter['Description']) -and `
            $packagePath -eq $Path -and `
            $packageExclude -eq $Exclude
        }
    }

    It 'should pass default whitelist' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $missing = Invoke-Command { $WithExtraFile ; '*.js','*.css' } | Where-Object { $TaskParameter['Include'] -notcontains $_ }

            $packageInclude = $WithExtraFile -join ';'
            $include = $TaskParameter['Include'] -join ';'
            Write-Debug -Message ('Include  expected  {0}' -f $packageInclude)
            Write-Debug -Message ('         actual    {0}' -f $include)
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
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $packageThirdPartyPath = $WithThirdPartyPath -join ';'
            $thirdPartyPathCsv = $TaskParameter['ThirdPartyPath'] -join ';'
            Write-Debug -Message ('ThirdPartyPath                        expected  {0}' -f $packageThirdPartyPath)
            Write-Debug -Message ('                                      actual    {0}' -f $thirdPartyPathCsv)

            return ($TaskParameter['ThirdPartyPath'] -contains 'node_modules')
        }
    }

    It 'should pass node_modules as third party path once' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $nodeModulesCount = $TaskParameter['ThirdPartyPath'] | Where-Object { $_ -eq 'node_modules' } | Measure-Object | Select-Object -ExpandProperty 'Count'

            Write-Debug -Message ('ThirdPartyPath[''node_modules''].Count  expected  1')
            Write-Debug -Message ('                                      actual    {0}' -f $nodeModulesCount)

            return $nodeModulesCount -eq 1
        }
    }
}

Describe 'Invoke-WhsCINodeAppPackageTask.when called' {
    Assert-NodePackageCreated
}

Describe 'Invoke-WhsCINodeAppPackageTask.when called with extra files' {
    Assert-NodePackageCreated -WithExtraFile 'one','two'
}

Describe 'Invoke-WhsCINodeAppPackageTask.when called with duplicate third-party path' {
    Assert-NodePackageCreated -WithThirdPartyPath 'node_modules'
}

Describe 'Invoke-WhsCINodeAppPackageTask.when called with third-party path' {
    Assert-NodePackageCreated -WithThirdPartyPath 'thirdfirst','thirdsecond'
}