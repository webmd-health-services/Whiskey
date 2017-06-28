#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function GivenADecoupledWindowsService
{
    param(
        [String]
        $WithPath,

        [Switch]
        $ExcludingBinPath,

        [Switch]
        $WithServicesJsonInBuildRoot,

        [Switch]
        $WithoutNadAndRabbitMQ
    )
    $resourcesPath = New-Item -Name 'Resources' -Path $TestDrive.FullName -ItemType 'Directory'

    $servicesPath = $TestDrive.FullName
    if ( -not $WithServicesJsonInBuildRoot )
    {
        $servicesPath = $resourcesPath
    }
    New-Item -Name 'Services.json' -Path $servicesPath -ItemType 'file' | Out-Null
    if( -not $WithoutNadAndRabbitMQ )
    {
        New-Item -name 'Nad' -Path $resourcesPath -ItemType 'Directory' | Out-Null
        New-Item -name 'RabbitMQ' -Path $resourcesPath -ItemType 'Directory' | Out-Null
    }
    
    $packageName = 'name'
    $packageDescription = 'description'
    if( -not $WithPath )
    {
        $WithPath = 'path1','path2'
    }
    $packageExclude = 'three','four'

    $taskParameter = @{
                            Name = $packageName;
                            Description = $packageDescription;
                            Path = $WithPath;
                            Exclude = $packageExclude;
                      }
    if( -not $ExcludingBinPath )
    {
        $binPath = Join-Path -Path $TestDrive.FullName -ChildPath 'bin'
        $taskParameter.add('BinPath', $binPath)
    }
    return $taskParameter
}

function WhenPackagingTheService
{
    param(
        [Object]
        $TaskContext,

        [HashTable]
        $TaskParameter,

        [Switch]
        $WithCleanSwitch
    )

    $optionalParams = @{}
    if( $WithCleanSwitch )
    {
        $optionalParams['Clean'] = $true
    }
    
    Mock -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -Verifiable
    $global:Error.Clear()
    try
    {
        Invoke-WhiskeyDecoupledWindowsServicePackageTask -TaskContext $context -TaskParameter $taskParameter @optionalParams
    }
    catch
    {
        return
    } 
}

function ThenTheServiceShouldBePackaged
{
    param(
        [String]
        $WithPath,

        [Object]
        $TaskContext,

        [HashTable]
        $TaskParameter,

        [Switch]
        $WithServicesJsonInBuildRoot,

        [Switch]
        $WithoutNadAndRabbitMQ
    )

    $packageName = 'name'
    $packageDescription = 'description'
    if( -not $WithPath )
    {
        $WithPath = 'path1','path2'
    }
    $packageExclude = 'three','four'
    $binPath = Join-Path -Path $TestDrive.FullName -ChildPath 'bin'

    $servicesPath = Join-Path -Path $TestDrive -ChildPath 'services.json'
    if( -not $WithServicesJsonInBuildRoot )
    {
        $resourcesPath = Join-Path -path $TestDrive -ChildPath 'Resources'
        $servicesPath = Join-Path -Path $resourcesPath -ChildPath 'services.json'
    }

    It 'should not exit with error' {
        $Global:Error | should BeNullOrEmpty 
    }

    It 'should include Path paths in package' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
            $missingPaths = $WithPath | Where-Object { $TaskParameter['Path'] -notcontains $_ }
            return -not $missingPaths
        }
    }
    It 'should include services.json in package' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
            $count = $TaskParameter['Path'] | Where-Object { $_ -eq $servicesPath } | Measure-Object | Select-Object -ExpandProperty 'Count'
            $count -eq 1
        }
    }
    if( -not $WithoutNadAndRabbitMQ )
    {
        It 'should include resources/nad in package' {
            Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
                $count = $TaskParameter['Path'] | Where-Object { $_ -eq "$TestDrive\resources\nad" } | Measure-Object | Select-Object -ExpandProperty 'Count'
                $count -eq 1
            }
        }
        It 'should include resources/rabbitmq in package' {
            Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
                $count = $TaskParameter['Path'] | Where-Object { $_ -eq "$TestDrive\resources\rabbitmq" } | Measure-Object | Select-Object -ExpandProperty 'Count'
                $count -eq 1
            }
        }
    }
    else
    {
        It 'should not include resources/nad in package' {
            Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
                $count = $TaskParameter['Path'] | Where-Object { $_ -eq "$TestDrive\resources\nad" } | Measure-Object | Select-Object -ExpandProperty 'Count'
                $count -eq 0
            }
        }
        It 'should not include resources/rabbitmq in package' {
            Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
                $count = $TaskParameter['Path'] | Where-Object { $_ -eq "$TestDrive\resources\rabbitmq" } | Measure-Object | Select-Object -ExpandProperty 'Count'
                $count -eq 0
            }
        }
    }

    It 'should include the path to the Bin Directory in the package' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
            $count = $TaskParameter['Path'] | Where-Object { $_ -eq $binPath } | Measure-Object | Select-Object -ExpandProperty 'Count'
            $count -eq 1
        }
    }

    It 'should pass parameters to Invoke-WhiskeyAppPackageTask' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
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
            $packageName -eq $TaskParameter['Name'] -and `
            $packageDescription -eq $TaskParameter['Description'] -and `
            $packageExclude -eq $Exclude
        }
    }

    It 'should pass default whitelist' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'

            $missing = Invoke-Command { '*.js','*.json' } | Where-Object { $TaskParameter['Include'] -notcontains $_ }

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
}

function ThenTheServiceShouldNotBePackaged
{
    param(
        [String]
        $WithErrorMessage
    )

    It 'should not package the Decoupled Windows Service' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyAppPackageTask' -ModuleName 'Whiskey' -Times 0
    }

    if( $WithErrorMessage )
    {
        It 'should exit and write an error' {
            $Global:Error | should match $WithErrorMessage
        }
    }
}

#regular run
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when called' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $taskParameter = GivenADecoupledWindowsService -WithServicesJsonInBuildRoot
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter
    ThenTheServiceShouldBePackaged -TaskContext $context -TaskParameter $taskParameter -WithServicesJsonInBuildRoot
}

#without Resources
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when called without any additional resources' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $taskParameter = GivenADecoupledWindowsService -WithServicesJsonInBuildRoot -WithoutNadAndRabbitMQ
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter
    ThenTheServiceShouldBePackaged -TaskContext $context -TaskParameter $taskParameter -WithServicesJsonInBuildRoot -WithoutNadAndRabbitMQ
}

#no BinPath
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when BinPath is not included' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $error = 'BinPath is mandatory.'
    $taskParameter = GivenADecoupledWindowsService -WithServicesJsonInBuildRoot -ExcludingBinPath
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter
    ThenTheServiceShouldNotBePackaged -WithErrorMessage $error
}

#services.json
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when services.json is in BuildRoot' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $taskParameter = GivenADecoupledWindowsService -WithServicesJsonInBuildRoot
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter
    ThenTheServiceShouldBePackaged -TaskContext $context -TaskParameter $taskParameter -WithServicesJsonInBuildRoot
}

#resources/services.json
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when services.json is in resources DIR' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $taskParameter = GivenADecoupledWindowsService
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter
    ThenTheServiceShouldBePackaged -TaskContext $context -TaskParameter $taskParameter
}

#clean switch
Describe 'Invoke-WhiskeyDecoupledWindowsServicePackageTask. when run with clean switch' {
    $context = New-WhiskeyTestContext -WithMockToolData -ForDeveloper
    $taskParameter = GivenADecoupledWindowsService
    WhenPackagingTheService -TaskContext $context -TaskParameter $taskParameter -WithCleanSwitch
    ThenTheServiceShouldNotBePackaged 
}
