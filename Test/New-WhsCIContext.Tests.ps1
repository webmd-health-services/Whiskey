
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$buildServerContext = @{
                            BBServerCredential = (New-Credential -UserName 'bitbucket' -Password 'snafu');
                            BBServerUri = 'http://bitbucket.example.com/';
                            BuildMasterUri = 'http://buildmaster.example.com/';
                            BuildMasterApiKey = 'deadbeef';
                            ProGetCredential = (New-Credential -UserName 'proget' -Password 'snafu');
                        }
$progetUri = [uri]'https://proget.example.com/'


function Assert-Context
{
    param(
        $Context,

        $SemanticVersion,

        [Switch]
        $ByBuildServer,

        $DownloadRoot,

        $ApplicationName,

        $ReleaseName,

        $WithProGetAppFeed = 'upack/Apps', 

        $WithProGetNpmFeed = 'npm/npm',

        $WithProGetNuGetFeed = 'nuget/NuGet'
    )

    It 'should set configuration path' {
        $Context.ConfigurationPath | Should Be (Join-Path -Path $TestDrive.FullName -ChildPath 'whsbuild.yml')
    }

    It 'should set build root' {
        $Context.BuildRoot | Should Be ($Context.ConfigurationPath | Split-Path)
    }

    It 'should set output directory' {
        $Context.OutputDirectory | Should Be (Join-Path -Path $Context.BuildRoot -ChildPath '.output')
    }

    It 'should create output directory' {
        $Context.OutputDirectory | Should Exist
    }

    It 'should have TaskName property' {
        $Context.TaskName | Should BeNullOrEmpty
    }

    It 'should have TaskIndex property' {
        $Context.TaskIndex | Should Be -1
    }

    It 'should have PackageVariables property' {
        $Context.PackageVariables | Should BeOfType ([hashtable])
        $Context.PackageVariables.Count | Should Be 0
    }

    It 'should set version' {
        $Context.Version | Should Be $SemanticVersion
        $Context.Version | Should BeOfType ([SemVersion.SemanticVersion])
    }

    $expectedVersion = ('{0}.{1}.{2}' -f $SemanticVersion.Major,$SemanticVersion.Minor,$SemanticVersion.Patch)
    It 'should set .NET version' {
        $Context.Version.Version | Should Be $expectedVersion
        $Context.Version.Version | Should BeOfType ([version])
    }

    $expectedReleaseVersion = $expectedVersion
    if( $SemanticVersion.Prerelease )
    {
        $expectedReleaseVersion = '{0}-{1}' -f $expectedVersion,$SemanticVersion.Prerelease
    }

    It 'should set NuGet version' {
        $Context.Version.ReleaseVersion | Should Be $expectedReleaseVersion
        $Context.Version.ReleaseVersion | Should BeOfType ([SemVersion.SemanticVersion])
    }

    It 'should set raw configuration hashtable' {
        $Context.Configuration | Should BeOfType ([hashtable])
        $Context.Configuration.ContainsKey('SomProperty') | Should Be $true
        $Context.Configuration['SomProperty'] | Should Be 'SomeValue'
    }

    if( -not $DownloadRoot )
    {
        $DownloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    }
    It 'should set download root' {
        $Context.DownloadRoot | Should Be $DownloadRoot
    }

    It 'should set build configuration' {
        $Context.BuildConfiguration | Should Be 'fubar'
    }

    It 'should set build server flag' {
        $Context.ByBuildServer | Should Be $ByBuildServer
        $Context.ByDeveloper | Should Be (-not $ByBuildServer)
    }


    It 'should set ProGet URIs' {
        $Context.ProGetSession | Should Not BeNullOrEmpty
        $Context.ProGetSession.Uri | Should Be $progetUri
        $Context.ProGetSession.AppFeed | Should Be $WithProGetAppFeed
        $Context.ProGetSession.NpmFeed | Should Be $WithProGetNpmFeed
        $Context.ProGetSession.AppFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetAppFeed)
        $Context.ProGetSession.NpmFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetNpmFeed)
        $Context.ProGetSession.NuGetFeed | Should Be $WithProGetNuGetFeed
        $Context.ProGetSession.NuGetFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetNuGetFeed)
    }
}

function GivenConfiguration
{
    param(
        [string]
        $WithVersion,

        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $ForBuildServer,

        [String]
        $OnBranch = 'origin/develop',

        $ForApplicationName,

        $ForReleaseName,

        [string[]]
        $PublishingOn
    )

    if( $ThatDoesNotExist )
    {
        return 'I\do\not\exist'
    }

    $config = @{
                 'SomProperty' = 'SomeValue'
               }

    if( $WithVersion )
    {
        $config['Version'] = $WithVersion
    }

    if( $ForApplicationName )
    {
        $config['ApplicationName'] = $ForApplicationName
    }

    if( $ForReleaseName )
    {
        $config['ReleaseName'] = $ForReleaseName
    }

    if( $PublishingOn )
    {
        $config['PublishOn'] = $PublishingOn
    }
    
    if( $ForBuildServer )
    {
        $gitBranch = $OnBranch
        $filter = { $Path -eq 'env:GIT_BRANCH' }
        $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -ParameterFilter $filter -MockWith $mock
        Mock -CommandName 'Get-Item' -ParameterFilter $filter -MockWith $mock
        Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    }
    

    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { 
        [SemVersion.SemanticVersion]$semVersion = $null
        if( -not [SemVersion.SemanticVersion]::TryParse($WithVersion,[ref]$semVersion) )
        {
            return 
        }
        return $semVersion
    }.GetNewClosure()

    $whsBuildYmlPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whsbuild.yml'
    $config | ConvertTo-Yaml | Set-Content -Path $whsBuildYmlPath
    return $whsBuildYmlPath
}

function WhenCreatingContext
{
    param(
        [Parameter(ValueFromPIpeline=$true)]
        $ConfigurationPath,

        [string]
        $ThenCreationFailsWithErrorMessage,

        [Switch]
        $ByDeveloper,

        [Switch]
        $ByBuildServer,

        $WithProGetAppFeed = 'upack/Apps', 

        $WithProGetNpmFeed = 'npm/npm',

        $WithProGetNuGetFeed = 'nuget/NuGet',

        $WithDownloadRoot,

        [Switch]
        $WithNoToolInfo
    )

    process
    {
        if( $ByDeveloper )
        {
            Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $false }
        }

        $optionalArgs = @{ }
        if( $ByBuildServer )
        {
            Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
            if( -not $WithNoToolInfo )
            {
                $optionalArgs = $buildServerContext.Clone()
                if( $WithProGetAppFeed )
                {
                    $optionalArgs['ProGetAppFeed'] = $WithProGetAppFeed
                }
                if( $WithProGetNpmFeed )
                {
                    $optionalArgs['ProGetNpmFeed'] = $WithProGetNpmFeed
                }
                if( $WithProGetNuGetFeed )
                {
                    $optionalArgs['ProGetNuGetFeed'] = $WithProGetNuGetFeed
                }
            }
        }

        if( $WithDownloadRoot )
        {
            $optionalArgs['DownloadRoot'] = $WithDownloadRoot
        }

        $Global:Error.Clear()
        $threwException = $false
        try
        {
            New-WhsCIContext -ConfigurationPath $ConfigurationPath -BuildConfiguration 'fubar' -ProGetUri 'https://proget.example.com/' @optionalArgs
        }
        catch
        {
            $threwException = $true
            $_ | Write-Error 
        }

        if( $ThenCreationFailsWithErrorMessage )
        {
            It 'should throw an exception' {
                $threwException | Should Be $true
            }

            It 'should write an error' {
                $Global:Error | Should Match $ThenCreationFailsWithErrorMessage
            }
        }
        else
        {
            It 'should not throw an exception' {
                $threwException | Should Be $false
            }

            It 'should not write an error' {
                $Global:Error | Should BeNullOrEmpty
            }
        }
    }
}

function ThenBuildServerContextCreated
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [SemVersion.SemanticVersion]
        $WithSemanticVersion,

        [String]
        $WithReleaseName = $null,

        $WithProGetAppFeed, 

        $WithProGetNpmFeed,

        $WithProGetNuGetFeed,

        $WithDownloadRoot
    )

    begin
    {
        $iWasCalled = $false
    }

    process
    {
        $optionalArgs = @{}
        if( $WithProGetAppFeed )
        {
            $optionalArgs['WithProGetAppFeed'] = $WithProGetAppFeed
        }
        if( $WithProGetNpmFeed )
        {
            $optionalArgs['WithProGetNpmFeed'] = $WithProGetNpmFeed
        }
        if( $WithProGetNuGetFeed )
        {
            $optionalArgs['WithProGetNuGetFeed'] = $WithProGetNuGetFeed
        }
            

        $iWasCalled = $true
        Assert-Context -Context $Context -SemanticVersion $WithSemanticVersion -ByBuildServer -DownloadRoot $WithDownloadRoot @optionalArgs

        It 'should set Bitbucket Server connection' {
            $Context.BBServerConnection | Should Not BeNullOrEmpty
            $Context.BBServerConnection.Uri | Should Be $buildServerContext['BBServerUri']
            [object]::ReferenceEquals($Context.BBServerConnection.Credential,$buildServerContext['BBServerCredential']) | Should Be $true
        }

        It 'should set BuildMaster session' {
            $Context.BuildMasterSession | Should Not BeNullOrEmpty
            $Context.BuildMasterSession.Uri | Should Be $buildServerContext['BuildMasterUri']
            $Context.BuildMasterSession.ApiKey | Should Be $buildServerContext['BuildMasterApiKey']
        }

        It 'should set ProGet session' {
            $Context.ProGetSession | Should Not BeNullOrEmpty
            [object]::ReferenceEquals($Context.ProGetSession.Credential,$buildServerContext['ProGetCredential']) | Should Be $true
        }
        if( $WithReleaseName )
        {
            It 'should set publish' {
                $Context.Publish | Should Be $True
            }

            It 'should set release name' {
                $Context.ReleaseName | Should Be $WithReleaseName
            }
        }
        else
        {
            It 'should not set publish' {
                $Context.Publish | Should Be $False
            }

            It 'should not set release name' {
                $Context.ReleaseName | Should BeNullOrEmpty
            }
        }
    }

    end
    {
        It 'should return a context' {
            $iWasCalled | Should Be $true
        }
    }
}

function ThenDeveloperContextCreated
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [SemVersion.SemanticVersion]
        $WithSemanticVersion,

        $WithApplicationName = $null,

        $WithReleaseName = $null
    )

    begin
    {
        $iWasCalled = $false
    }

    process
    {
        $iWasCalled = $true

        Assert-Context -Context $Context -SemanticVersion $WithSemanticVersion

        It 'should not set Bitbucket Server connection' {
            $Context.BBServerConnection | Should BeNullOrEmpty
        }

        It 'should not set BuildMaster session' {
            $Context.BuildMasterSession| Should BeNullOrEmpty
        }

        It 'should set application name' {
            $Context.ApplicationName | Should Be $WithApplicationName
        }

        It 'should set release name' {
            $Context.ReleaseName | Should Be $WithReleaseName
        }
        
        It 'should not set publish' {
            $Context.Publish | Should Be $false
        }
    }

    end
    {
        It 'should return a context' {
            $iWasCalled | Should Be $true
        }
    }
}

Describe 'New-WhsCIContext.when run by a developer for an application' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' |
        WhenCreatingContext -ByDeveloper | 
        ThenDeveloperContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
}

Describe 'New-WhsCIContext.when run by developer for a library' {
    GivenConfiguration -WithVersion '1.2.3' |
        WhenCreatingContext -ByDeveloper  | 
        ThenDeveloperContextCreated -WithSemanticVersion ('1.2.3+{0}.{1}' -f $env:USERNAME,$env:COMPUTERNAME)
}

Describe 'New-WhsCIContext.when run by developer and configuration file does not exist' {
    GivenConfiguration -ThatDoesNotExist |
        WhenCreatingContext -ByDeveloper  -ThenCreationFailsWithErrorMessage 'does not exist'-ErrorAction SilentlyContinue
}

Describe 'New-WhsCIContext.when run by developer and configuration file does not exist' {
    GivenConfiguration -ThatDoesNotExist |
        WhenCreatingContext -ByDeveloper  -ThenCreationFailsWithErrorMessage 'does not exist'-ErrorAction SilentlyContinue
}

Describe 'New-WhsCIContext.when run by developer and version is not a semantic version' {
    GivenConfiguration -WithVersion 'fubar' |
        WhenCreatingContext -ByDeveloper  -ThenCreationFailsWithErrorMessage 'not a valid semantic version' -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIContext.when run by the build server' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer |
        WhenCreatingContext -ByBuildServer | 
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'develop'
}

Describe 'New-WhsCIContext.when run by the build server and customizing ProGet feed names' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer |
        WhenCreatingContext -ByBuildServer -WithProgetAppFeed 'fubar' -WithProGetNpmFeed 'snafu' -WithProGetNuGetFeed 'fubarsnafu' | 
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithProGetAppFeed 'fubar' -WithProGetNpmFeed 'snafu' -WithReleaseName 'develop' -WithProGetNuGetFeed 'fubarsnafu'
}

Describe 'New-WhsCIContext.when run by the build server and customizing download root' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer |
        WhenCreatingContext -ByBuildServer -WithDownloadRoot $TestDrive.FullName | 
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithDownloadRoot $TestDrive.FullName -WithReleaseName 'develop'
}

Describe 'New-WhsCIContext.when run by build server called with developer parameter set' {
    GivenConfiguration -WithVersion '1.2.3' -ForBuildServer |
        WhenCreatingContext -ByBuildServer -WithNoToolInfo -ThenCreationFailsWithErrorMessage 'developer parameter set' -ErrorAction SilentlyContinue
}

Describe 'New-WhsCIContext.when application name in configuration file' {
    GivenConfiguration -WithVersion '1.2.3' -ForApplicationName 'fubar' |
        WhenCreatingContext -ByDeveloper |
        ThenDeveloperContextCreated -WithApplicationName 'fubar' -WithSemanticVersion '1.2.3'
}

Describe 'New-WhsCIContext.when release name in configuration file' {
    GivenConfiguration -WithVersion '1.2.3' -ForReleaseName 'fubar' |
        WhenCreatingContext -ByDeveloper |
        ThenDeveloperContextCreated -WithReleaseName 'fubar' -WithSemanticVersion '1.2.3'
}


Describe 'New-WhsCIContext.when building on master branch' {
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/master' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'master'
}

Describe 'New-WhsCIContext.when building on feature branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/feature/fubar' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/feature/fubar'
}

Describe 'New-WhsCIContext.when building on release branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/release/5.1' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'release'
        return
}

Describe 'New-WhsCIContext.when building on long-lived release branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/release' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'release'
        return
}

Describe 'New-WhsCIContext.when building on develop branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/develop' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'develop'
}

Describe 'New-WhsCIContext.when building on hot fix branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/hotfix/snafu' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/hotfix/snafu'
}

Describe 'New-WhsCIContext.when building on bug fix branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'origin/bugfix/fubarnsafu' |
            WhenCreatingContext -ByBuildServer | 
            ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/bugfix/fubarnsafu'
}

Describe 'New-WhsCIContext.when publishing on custom branch' {
    GivenConfiguration -WithVersion '1.2.3' -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3\.0' |
        WhenCreatingContext -ByBuildServer |
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3' -WithReleaseName 'feature/3.0'
}