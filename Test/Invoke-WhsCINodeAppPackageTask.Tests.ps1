
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function Assert-NodePackageCreated
{
    param(
        [string[]]
        $WithExtraFile,

        [string[]]
        $WithThirdPartyPath,

        [Switch]
        $WhenIncludingArc,

        [Switch]
        $ThenArcIncluded,

        [string]
        $WithPath
    )

    $packageName = 'name'
    $packageDescription = 'description'
    if( -not $WithPath )
    {
        $WithPath = 'path1','path2'
    }
    $packageExclude = 'three','four'
    $context = New-WhsCITestContext -WithMockToolData
    
    $taskParameter = @{
                            Name = $packageName;
                            Description = $packageDescription;
                            Path = $WithPath;
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

    if( $WhenIncludingArc )
    {
        $taskParameter['IncludeArc'] = $true
    }

    Mock -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -Verifiable

    Invoke-WhsCINodeAppPackageTask -TaskContext $context -TaskParameter $taskParameter

    It 'should include Path paths in package' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            $missingPaths = $WithPath | Where-Object { $TaskParameter['Path'] -notcontains $_ }
            return -not $missingPaths
        }
    }
    
    It 'should include package.json in package' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            $count = $TaskParameter['Path'] | Where-Object { $_ -eq 'package.json' } | Measure-Object | Select-Object -ExpandProperty 'Count'
            $count -eq 1
        }
    }

    It 'should pass parameters to Invoke-WhsCIAppPackageTask' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Name                expected  {0}' -f $packageName)
            Write-Debug -Message ('                    actual    {0}' -f $TaskParameter['Name'])
            Write-Debug -Message ('Description         expected  {0}' -f $packageDescription)
            Write-Debug -Message ('                    actual    {0}' -f $TaskParameter['Description'])
            
            $packageExclude = $packageExclude -join ';'
            $exclude = $TaskParameter['Exclude'] -join ';'
            Write-Debug -Message ('Exclude             expected  {0}' -f $packageExclude)
            Write-Debug -Message ('                    actual    {0}' -f $exclude)

            $contextsSame = [object]::ReferenceEquals($context,$TaskContext)
            Write-Debug -Message ('Context = TaskContext         {0}' -f $contextsSame)

            $contextsSame -and `
            [object]::ReferenceEquals($packageName,$TaskParameter['Name']) -and `
            [object]::ReferenceEquals($packageDescription,$TaskParameter['Description']) -and `
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

    $excludeArc = $true
    $assertion = 'exclude'
    if( $ThenArcIncluded )
    {
        $excludeArc = $false
        $assertion = 'include'
    }
    It ('should {0} Arc' -f $assertion) {
        Assert-MockCalled -CommandName 'Invoke-WhsCIAppPackageTask' -ModuleName 'WhsCI' -ParameterFilter {
            return $TaskParameter['ExcludeArc'] -eq $excludeArc
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

Describe 'Invoke-WhsCINodeAppPackageTask.when including Arc' {
    Assert-NodePackageCreated -WhenIncludingArc -ThenArcIncluded
}

Describe 'Invoke-WhsCINodeAppPackageTask.when path includes package.json' {
    Assert-NodePackageCreated -WithPath 'package.json'
}