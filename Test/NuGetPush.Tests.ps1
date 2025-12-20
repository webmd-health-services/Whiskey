
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:context = $null
    $script:nugetUri = $null
    $script:apiKey = $null
    $script:defaultVersion = '1.2.3'
    $script:packageExists = $false
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:threwException = $false
    $script:path = $null
    $script:packageVersion = $null
    $script:version = $null

    function GivenANuGetPackage
    {
        param(
            [ValidatePattern('\.\d+\.\d+\.\d+(-.*)?(\.symbols)?\.nupkg')]
            [String[]]$Path
        )

        $outputRoot = Join-Path -Path $script:testRoot -ChildPath '.output'
        New-Item -Path $outputRoot -ItemType 'Directory'  -ErrorAction Ignore

        foreach( $item in $Path )
        {
            New-Item -Path (Join-Path -Path $outputRoot -ChildPath $item) -ItemType 'File' -Force
        }
    }

    function GivenNoApiKey
    {
        $script:apiKey = $null
    }

    function GivenNoUri
    {
        $script:nugetUri = $null
    }

    function GivenPath
    {
        param(
            $Path
        )

        $script:path = $Path
    }

    function GivenPackageAlreadyPublished
    {
        $script:packageExists = $true
    }

    function GivenPackagePublishFails
    {
        $script:publishFails = $true
    }

    function GivenTheCheckIfThePackageExistsFails
    {
        $script:packageExistsCheckFails = $true
    }

    function GivenPackageVersion
    {
        param(
            $PackageVersion
        )

        $script:packageVersion = $PackageVersion
    }

    function GivenVersion
    {
        param(
            $Version
        )

        $script:version = $Version
    }

    function WhenRunningNuGetPackTask
    {
        [CmdletBinding()]
        param(
            [switch]$ForProjectThatDoesNotExist,

            [switch]$ForMultiplePackages,

            [switch]$Symbols,

            [switch]$SkipUploadedCheck
        )

        $script:context = New-WhiskeyTestContext -ForVersion $script:packageVersion `
                                                 -ForBuildServer `
                                                 -ForBuildRoot $script:testRoot `
                                                 -IgnoreExistingOutputDirectory
        $taskParameter = @{ }

        if( $script:path )
        {
            $taskParameter['Path'] = $script:path
        }

        if( $script:apiKey )
        {
            $taskParameter['ApiKeyID'] = 'fubarsnafu'
            Add-WhiskeyApiKey -Context $script:context -ID 'fubarsnafu' -Value $script:apiKey
        }

        if( $script:nugetUri )
        {
            $taskParameter['Uri'] = $script:nugetUri
        }

        if( $Symbols )
        {
            $taskParameter['Symbols'] = $true
        }

        if( $script:version )
        {
            $taskParameter['Version'] = $script:version
        }

        if( $SkipUploadedCheck )
        {
            $taskParameter['SkipUploadedCheck'] = 'true'
        }

        Mock -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey'
        if( $script:packageExists )
        {
            Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
        }
        elseif( $script:publishFails )
        {
            Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith {
                Write-WhiskeyDebug -Message 'http://httpstat.us/404'
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri 'http://httpstat.us/404' -Headers @{ 'Accept' = 'text/html' } -UseBasicParsing
            } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
        }
        elseif( $script:packageExistsCheckFails )
        {
            Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith {
                Write-WhiskeyDebug -Message 'http://httpstat.us/500'
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri 'http://httpstat.us/500' -Headers @{ 'Accept' = 'text/html' } -UseBasicParsing
            } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
        }
        else
        {
            $global:counter = 0
            Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith {
                #$DebugPreference = 'Continue'
                Write-WhiskeyDebug $global:counter
                if($global:counter -eq 0)
                {
                    $global:counter++
                    Write-WhiskeyDebug $global:counter
                    Write-WhiskeyDebug -Message 'http://httpstat.us/404'
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri 'http://httpstat.us/404' `
                                      -Headers @{ 'Accept' = 'text/html' } `
                                      -UseBasicParsing
                }
                $global:counter = 0
                Write-WhiskeyDebug -Message 'http://httpstat.us/200'
            } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
        }

        $script:threwException = $false
        try
        {
            if( $ForProjectThatDoesNotExist )
            {
                $taskParameter['Path'] = 'I\do\not\exist.csproj'
            }

            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $script:context -Parameter $taskParameter -Name 'NuGetPush'

        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }

        Remove-Variable -Name 'counter' -Scope 'Global' -ErrorAction Ignore
    }

    function ThenSpecificNuGetVersionInstalled
    {
        $nugetVersion = 'NuGet.CommandLine.{0}' -f $script:version

        Join-Path -Path $script:context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
    }

    function ThenTaskThrowsAnException
    {
        param(
            $ExpectedErrorMessage
        )

        $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose

        $script:threwException | Should -BeTrue
        $Global:Error | Should -Not -BeNullOrEmpty
        $lastError = $Global:Error[0]
        $lastError | Should -Match $ExpectedErrorMessage
    }

    function ThenTaskSucceeds
    {
        $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose

        $script:threwException | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenPackagePublished
    {
        param(
            $Name,
            $PackageVersion,
            $Path,
            $Times = 1
        )

        $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose
        foreach( $item in $Path )
        {
            $script:testRoot = $script:testRoot
            Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter {
                #$DebugPreference = 'Continue'
                $expectedPath = Join-Path -Path '.' -ChildPath ('.output\{0}' -f $item)
                Write-WhiskeyDebug -Message ('Path  expected  {0}' -f $expectedPath)
                $Path | Where-Object {
                                        Write-WhiskeyDebug -Message ('      actual    {0}' -f $_)
                                        $_ -eq $expectedPath
                                        }
            }

            $expectedUriWildcard = '*/{0}/{1}' -f $Name,$PackageVersion
            Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -ParameterFilter {
                #$DebugPreference = 'Continue'
                Write-WhiskeyDebug -Message ('Uri   expected   {0}' -f $expectedUriWildcard)
                Write-WhiskeyDebug -Message ('      actual     {0}' -f $Uri)
                $Uri -like $expectedUriWildcard
                }
        }

        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $Url -eq $script:nugetUri }

        $expectedApiKey = $script:apiKey
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $ApiKey -eq $expectedApiKey }
    }

    function ThenPackageNotPublished
    {
        param(
            $Path
        )

        $expectedPath = $Path
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -Times 0 -ParameterFilter {
            #$DebugPreference = 'Continue'

            if( -not $expectedPath )
            {
                Write-WhiskeyDebug 'No Path'
                return $True
            }

            Write-WhiskeyDebug ('Path  expected  *\{0}' -f $expectedPath)
            Write-WhiskeyDebug ('      actual    {0}' -f $Path)
            return $Path -like ('*\{0}' -f $expectedPath)
        }
    }
}

Describe 'NuGetPush' {
    BeforeEach {
        $script:nugetUri = 'https://nuget.org'
        $script:apiKey = 'fubar:snafu'
        $script:packageExists = $false
        $script:publishFails = $false
        $script:packageExistsCheckFails = $false
        $script:path = $null
        $script:packageVersion = $script:defaultVersion
        $script:version = $null

        $script:testRoot = New-WhiskeyTestRoot
    }

    It 'should publish package' {
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        WhenRunningNuGetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
    }

    It 'should publish with prerelease metadata' {
        GivenPackageVersion '1.2.3-preleasee45'
        GivenANuGetPackage 'Fubar.1.2.3-preleasee45.nupkg'
        WhenRunningNuGetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3-preleasee45.nupkg' -PackageVersion '1.2.3-preleasee45'
        ThenTaskSucceeds
    }

    It 'should publish with symbols' {
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.symbols.nupkg'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        WhenRunningNuGetPackTask -Symbols
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.symbols.nupkg' -PackageVersion '1.2.3'
        ThenPackageNotPublished -Path 'Fubar.1.2.3.nupkg'
        ThenTaskSucceeds
    }

    It 'should publish multiple packages' {
        GivenPackageVersion '3.4.5'
        GivenANuGetPackage 'Fubar.3.4.5.nupkg','Snafu.3.4.5.nupkg'
        WhenRunningNugetPackTask -ForMultiplePackages
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.3.4.5.nupkg' -PackageVersion '3.4.5'
        ThenPackagePublished -Name 'Snafu' -Path 'Snafu.3.4.5.nupkg' -PackageVersion '3.4.5'
        ThenTaskSucceeds
    }

    It 'should fail' {
        GivenPackageVersion '9.0.1'
        GivenPackagePublishFails
        GivenANuGetPackage 'Fubar.9.0.1.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'failed to publish NuGet package'
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.9.0.1.nupkg' -PackageVersion '9.0.1'
    }

    It 'should check if package exists' {
        GivenPackageVersion '2.3.4'
        GivenPackageAlreadyPublished
        GivenANuGetPackage 'Fubar.2.3.4.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'already exists'
        ThenPackageNotPublished
    }

    It 'should fail if can''t check that package exists' {
        GivenPackageVersion '5.6.7'
        GivenTheCheckIfThePackageExistsFails
        GivenANuGetPackage 'Fubar.5.6.7.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'failure checking if'
        ThenPackageNotPublished
    }

    It 'should require URL' {
        GivenPackageVersion '8.9.0'
        GivenANuGetPackage 'Fubar.8.9.0.nupkg'
        GivenNoUri
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotPublished
        ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
    }

    It 'should require API key' {
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenNoApiKey
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotPublished
        ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
    }

    It 'should publish custom packages' {
        GivenPackageVersion '4.5.6'
        GivenANuGetPackage 'someotherdir\MyPack.4.5.6.nupkg'
        GivenPath '.output\someotherdir\MyPack.4.5.6.nupkg'
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackagePublished -Name 'MyPack' -Path 'someotherdir\MyPack.4.5.6.nupkg' -PackageVersion '4.5.6'
    }

    It 'should not publish just symbols package' {
        GivenANuGetPackage 'Package.1.2.3.symbols.nupkg'
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackageNotPublished
    }

    It 'should use specific version of NuGet' {
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenVersion '3.5.0'
        WhenRunningNuGetPackTask
        ThenSpecificNuGetVersionInstalled
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
    }

    It 'should not check if publish succeeded' {
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenPackagePublishFails
        WhenRunningNuGetPackTask -SkipUploadedCheck
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 1
    }

    It 'should publish multiple packages at different version numbers' {
        GivenANuGetPackage 'Fubar.1.0.0.nupkg','Snafu.2.0.0.nupkg'
        WhenRunningNugetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.0.0.nupkg' -PackageVersion '1.0.0'
        ThenPackagePublished -Name 'Snafu' -Path 'Snafu.2.0.0.nupkg' -PackageVersion '2.0.0'
        ThenTaskSucceeds
    }
}
