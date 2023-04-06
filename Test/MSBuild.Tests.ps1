
#Require -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    # Load this module here so that it's assemblies get loaded into memory. Otherwise, the test will load
    # the module from the test drive, and Pester will complain that it can't delete the test drive.
    Import-WhiskeyTestModule -Name 'VSSetup' -Force
    Remove-Module -Name 'VSSetup' -Force

    $script:testRoot = $null
    $script:output = $null
    $script:path = $null
    $script:threwException = $null
    $script:assembly = $null
    $script:version = $null
    $script:nuGetVersion = $null
    $script:use32Bit = $null
    $script:exitCode = $null
    $script:procArchProject = @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
        <Message Text="PROCESSOR_ARCHITECTURE = `$(PROCESSOR_ARCHITECTURE)" Importance="High" />
    </Target>
</Project>
"@


    $script:assemblyRoot = Join-Path -Path $PSScriptRoot 'Assemblies'
    foreach( $item in @( 'bin', 'obj', 'packages' ) )
    {
        Get-ChildItem -Path $script:assemblyRoot -Filter $item -Recurse -Directory |
            Remove-Item -Recurse -Force
    }

    function Get-BuildRoot
    {
        return (Join-Path -Path $script:testRoot -ChildPath 'BuildRoot')
    }

    function GivenCustomMSBuildScriptWithMultipleTargets
    {
        New-MSBuildProject -FileName 'fubar.msbuild' -BuildRoot (Get-BuildRoot)
        $script:path = 'fubar.msbuild'
    }

    function GivenAProjectThatCompiles
    {
        param(
            [String]$ProjectName = 'NUnit2PassingTest'
        )

        $source = Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\{0}' -f $ProjectName)
        $destination = Get-BuildRoot
        $destination = Join-Path -Path $destination -ChildPath $ProjectName
        Copy-Item -Path $source -Destination $destination -Recurse
        $script:path = '{0}\{0}.sln' -f $ProjectName
        $script:assembly = '{0}.dll' -f $ProjectName
    }

    function GivenProject
    {
        param(
            $Project
        )

        $script:path = Join-Path -Path (Get-BuildRoot) -ChildPath 'project.msbuild'
        New-Item -Path $script:path -ItemType 'File' -Force
        $Project | Set-Content -Path $script:path -Force
        $script:path = $script:path | Split-Path -Leaf
    }

    function GivenAProjectThatDoesNotCompile
    {
        GivenAProjectThatCompiles
        Get-ChildItem -Path (Get-BuildRoot) -Filter 'AssemblyInfo.cs' -Recurse |
            ForEach-Object { Add-Content -Path $_.FullName -Value '>' }
    }

    function GivenAProjectThatDoesNotExist
    {
        GivenAProjectThatCompiles
        $script:path = 'I\do\not\exist.csproj'
        $script:assembly = 'exist.dll'
    }

    function GivenNoPathToBuild
    {
        GivenAProjectThatCompiles
        $script:path = $null
    }

    function GivenProjectsThatCompile
    {
        GivenAProjectThatCompiles 'NUnit2PassingTest'
        GivenAProjectThatCompiles 'NUnit2FailingTest'
        $script:path = @( 'NUnit2PassingTest\NUnit2PassingTest.sln', 'NUnit2FailingTest\NUnit2FailingTest.sln' )
        $script:assembly = @( 'NUnit2PassingTest.dll', 'NUnit2FailingTest.dll' )
        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.yml') -Destination (Get-BuildRoot)
    }

    function GivenUse32BitIs
    {
        param(
            $Value
        )

        $script:use32Bit = $value
    }

    function GivenVersion
    {
        param(
            $Version
        )

        $script:version = $Version
    }

    function GivenNuGetVersion
    {
        param(
            $NuGetVersion
        )

        $script:nuGetVersion = $NuGetVersion
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
            [hashtable]$WithParameter = @{},

            [Parameter(Mandatory,ParameterSetName='AsDeveloper')]
            [switch]$AsDeveloper,

            [Parameter(Mandatory,ParameterSetName='AsBuildServer')]
            [switch]$AsBuildServer,

            [switch]$InCleanMode,

            [SemVersion.SemanticVersion]$AtVersion,

            [switch]$WithNoPath
        )

        $optionalParams = @{ }
        if( $AsDeveloper )
        {
            $optionalParams['ForDeveloper'] = $true
        }

        if( $AsBuildServer )
        {
            $optionalParams['ForBuildServer'] = $true
        }

        if( $AtVersion )
        {
            $optionalParams['ForVersion'] = $AtVersion
        }

        $context = New-WhiskeyTestContext @optionalParams -ForBuildRoot (Get-BuildRoot) -IncludePSModule 'VSSetup'

        if( -not $WithNoPath )
        {
            $WithParameter['Path'] = $script:path
        }

        $script:threwException = $false
        $script:output = $null
        if( $InCleanMode )
        {
            $context.RunMode = 'Clean'
        }

        if( $script:version )
        {
            $WithParameter['Version'] = $script:version
        }

        if( $script:nuGetVersion )
        {
            $WithParameter['NuGetVersion'] = $script:nuGetVersion
        }

        if( $script:use32Bit )
        {
            $WithParameter['Use32Bit'] = $script:use32Bit
        }

        $Global:Error.Clear()
        try
        {
            $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameter -Name 'MSBuild'
            $script:exitCode = $LASTEXITCODE
            $script:output | Write-WhiskeyDebug
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }

    function ThenAssembliesAreVersioned
    {
        param(
            [String]$ProductVersion,

            [String]$FileVersion
        )

        Get-ChildItem -Path (Get-BuildRoot) -Filter $script:assembly -File -Recurse |
            Select-Object -ExpandProperty 'VersionInfo' |
            ForEach-Object {
                $_.ProductVersion | Should -Be $ProductVersion
                $_.FileVersion | Should -Be $FileVersion
            }
    }

    function ThenAssembliesAreNotVersioned
    {
        Get-ChildItem -Path (Get-BuildRoot) -Include $script:assembly -File -Recurse |
            Select-Object -ExpandProperty 'VersionInfo' |
            ForEach-Object {
                $_.ProductVersion | Should -Be '0.0.0.0'
                $_.FileVersion | Should -Be '0.0.0.0'
            }
    }

    function ThenSucceeded
    {
        ThenNoErrors
        $script:exitCode | Should -Be 0
    }

    function ThenOutputLogged
    {
        $buildRoot = Get-BuildRoot
        Join-Path -Path $buildRoot -ChildPath ('.output\msbuild.NUnit2PassingTest.sln.log') | Should -Exist
    }

    function ThenBinsAreEmpty
    {
        Get-ChildItem -Path (Get-BuildRoot) -Filter $script:assembly -File -Recurse | Should -BeNullOrEmpty
        foreach ($project in $script:path) {
            $projectPath = Join-Path -Path (Get-BuildRoot) -ChildPath ($project | Split-Path)
            Get-ChildItem -Path $projectPath -Include 'packages' -Directory | Should -BeNullOrEmpty
        }
    }

    function ThenBothTargetsRun
    {
        Join-Path -Path (Get-BuildRoot) -ChildPath '*.clean' | Should -Exist
        Join-Path -Path (Get-BuildRoot) -ChildPath '*.build' | Should -Exist
    }

    function ThenNoErrors
    {
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenNuGetPackagesRestored
    {
        foreach( $item in $script:path )
        {
            $item = $item | Split-Path
            $packagesRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
            $packagesRoot = Join-Path -Path $packagesRoot -ChildPath 'packages'
            $packagesRoot | Should -Exist
        }
    }

    function ThenNuGetPackagesNotRestored
    {
        Get-ChildItem -Path (Get-BuildRoot) -Filter 'packages' -Recurse |
            ForEach-Object { Get-ChildItem -Path $_.FullName -Exclude 'NuGet.CommandLine.*' } | Should -BeNullOrEmpty
    }

    function ThenOutputNotLogged
    {
        $buildRoot = Get-BuildRoot
        Join-Path -Path $buildRoot -ChildPath ('.output\*.log') | should -Not -Exist
    }

    function ThenProjectsCompiled
    {
        param(
            [String]$To
        )

        if( $To )
        {
            $script:outputRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $To
            foreach( $item in $script:assembly )
            {
                (Join-Path -Path $script:outputRoot -ChildPath $item) | Should -Exist
            }
            Get-ChildItem -Path (Get-BuildRoot) -Include 'bin' -Directory -Recurse |
                Get-ChildItem -Include $script:assembly -File -Recurse |
                Should -BeNullOrEmpty
        }
        else
        {
            foreach( $item in $script:path )
            {
                $item = $item | Split-Path
                $solutionRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
                Get-ChildItem -Path $solutionRoot -Directory -Include 'bin','obj' -Recurse | Should -Not -BeNullOrEmpty
                Get-ChildItem -Path $solutionRoot -Include $script:assembly -File -Recurse | Should -Not -BeNullOrEmpty
            }
        }
    }

    function ThenProjectsNotCompiled
    {
        Get-ChildItem -Path (Get-BuildRoot) -Include $script:assembly -File -Recurse | Should -BeNullOrEmpty
    }

    function ThenOutput
    {
        param(
            [String[]]$Contains,

            [String[]]$DoesNotContain,

            [String]$Is
        )

        # remove the NuGet output
        $fullOutput = $script:output -join [Environment]::NewLine #($script:output | Where-Object { $_ -notmatch ('^(Installing|Successfully installed)\b') }) -join [Environment]::NewLine
        $needle = " to packages.config projects"
        $indexOfNeedle = $fullOutput.IndexOf($needle, [StringComparison]::InvariantCultureIgnoreCase)
        if( $indexOfNeedle -ge 0 )
        {
            $startIndex = $indexOfNeedle + $needle.Length + [Environment]::NewLine.Length
            if( $startIndex -gt $fullOutput.Length )
            {
                $fullOutput = ''
            }
            else
            {
                $fullOutput = $fullOutput.Substring($startIndex)
            }
        }

        if( $Contains )
        {
            foreach( $item in $Contains )
            {
                $fullOutput | Should -Match $item
            }
        }

        if( $Is -or $PSBoundParameters.ContainsKey('Is') )
        {
            $desc = $Is
            if( -not $desc )
            {
                $desc = '[empty]'
            }
            $fullOutput | Should -Match ('^{0}$' -f $Is)
        }

        if( $DoesNotContain )
        {
            foreach( $item in $DoesNotContain )
            {
                $script:output | Should -Not -Match $item
            }
        }
    }

    function ThenOutputIsEmpty
    {
        ThenOutput -Is ''
    }

    function ThenOutputIsMinimal
    {
        ThenOutput -Is '.*\ ->\ .*'
    }

    function ThenOutputIsDebug
    {
        ThenOutput -Contains 'Target\ "[^"]+"\ in\ file\ '
    }

    function ThenSpecificNuGetVersionInstalled
    {
        $nuGetPackageVersion = "NuGet.CommandLine.$($script:nuGetVersion)"

        Get-ChildItem -Path (Join-Path -Path (Get-BuildRoot) -ChildPath 'packages') |
            Out-String |
            Write-Debug

        Join-Path -Path (Get-BuildRoot) -ChildPath "packages\$($nugetPackageVersion)" | Should -Exist
    }

    function ThenTaskFailed
    {
        param(
        )

        $script:threwException | Should -BeTrue
    }

    function ThenWritesError
    {
        param(
            $Pattern
        )

        $Global:Error | Where-Object { $_ -match $Pattern } | Should -Not -BeNullOrEmpty
    }
}

Describe 'MSBuild' {
    BeforeEach {
        $script:version = $null
        $script:nuGetVersion = $null
        $script:use32Bit = $false
        $script:exitCode = $null

        $script:testRoot = New-WhiskeyTestRoot
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }


    It 'should compile project' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
        ThenOutputLogged
    }

    It 'should build multiple projects' {
        GivenProjectsThatCompile
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
    }

    It 'should version with build metadata' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsBuildServer -AtVersion '1.5.9-rc.45+1034.master.deadbee'
        ThenNoErrors
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreVersioned -ProductVersion '1.5.9-rc.45+1034.master.deadbee' -FileVersion '1.5.9'
    }

    It 'should fail when MSBuild fails' {
        GivenAProjectThatDoesNotCompile
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenNuGetPackagesRestored
        ThenProjectsNotCompiled
        ThenTaskFailed
        ThenWritesError 'MSBuild\ exited\ with\ code\ 1'
    }

    It 'should require path parameter' {
        GivenNoPathToBuild
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesNotRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('Path is mandatory'))
    }

    It 'should validate path exists' {
        GivenAProjectThatDoesNotExist
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesnoTRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('does not exist.'))
    }

    It 'should run clean target in clean mode' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenProjectsCompiled
        WhenRunningTask -InCleanMode -AsDeveloper
        ThenNoErrors
        ThenBinsAreEmpty
    }

    It 'should customize output verbosity' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'q'; }
        ThenNoErrors
        ThenOutputIsEmpty
    }

    It 'should use minimal verbosity' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenOutputIsMinimal
    }

    It 'should pass extra build properties' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Property' = @( 'Fubar=Snafu' ) ; 'Verbosity' = 'diag' }
        ThenNoErrors
        ThenOutput -Contains 'Fubar=Snafu'
    }

    It 'should pass custom arguments' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/nologo', '/version' ) }
        ThenNoErrors
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }

    It 'should pass a single custom argument' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/version' ) }
        ThenNoErrors
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }

    It 'should multi-CPU build' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'n' }
        ThenNoErrors
        ThenOutput -Contains '\n\ {5}\d>'
    }

    It 'should pass CPU argument' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'CpuCount' = 1; 'Verbosity' = 'n' }
        ThenNoErrors
        ThenOutput -DoesNotContain '^\ {5}\d>'
    }

    It 'should use custom output directory' {
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'OutputDirectory' = '.myoutput' }
        ThenNoErrors
        ThenProjectsCompiled -To '.myoutput'
    }

    It 'should build custom targets' {
        GivenCustomMSBuildScriptWithMultipleTargets
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Target' = 'clean','build' ; 'Verbosity' = 'diag' }
        ThenNoErrors
        ThenBothTargetsRun
    }

    It 'should validate MSBuild version' {
        GivenAProjectThatCompiles
        GivenVersion 'some.bad.version'
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenWritesError -Pattern 'some\.bad\.version\b.*is\ not\ installed'
    }

    It 'should use custom version of MSBuild' {
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<Target Name="Build">
    <Message Importance="High" Text="`$(MSBuildBinPath)" />
</Target>
</Project>
"@
        $toolsVersionsRegPath = 'hklm:\software\Microsoft\MSBuild\ToolsVersions'
        $script:version =
            Get-ChildItem -Path $toolsVersionsRegPath |
            Select-Object -ExpandProperty 'Name' |
            Split-Path -Leaf |
            Sort-Object -Property { [Version]$_ } -Descending |
            Select-Object -Last 1
        $regPath = Join-Path -Path $toolsVersionsRegPath -ChildPath $script:version
        $expectedPath =
            Get-ItemProperty -Path $regPath -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        GivenVersion $script:version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenOutput -Contains ([regex]::Escape($expectedPath.TrimEnd('\')))
    }

    It 'should pick version of MSBuild to use from multiple candidates' {
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<Target Name="Build">
    <Message Importance="High" Text="`$(MSBuildBinPath)" />
</Target>
</Project>
"@
        $toolsVersionsRegPath = 'hklm:\software\Microsoft\MSBuild\ToolsVersions'
        $script:version =
            Get-ChildItem -Path $toolsVersionsRegPath |
            Select-Object -ExpandProperty 'Name' |
            Split-Path -Leaf |
            Sort-Object -Property { [Version]$_ } -Descending |
            Select-Object -Last 1
        $regPath = Join-Path -Path $toolsVersionsRegPath -ChildPath $script:version
        $msbuildRoot =
            Get-ItemProperty -Path $regPath -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        $msbuildPath = Join-Path -Path $msbuildRoot -ChildPath 'MSBuild.exe' -Resolve
        Mock -CommandName 'Get-MSBuild' -ModuleName 'Whiskey' -MockWith {
            1..2 | ForEach-Object {
                [pscustomobject]@{
                                    Name =  $script:version;
                                    Version = [Version]$script:version;
                                    Path = $msbuildPath;
                                    Path32 = $msbuildPath;
                                }
            }
        }
        GivenVersion $script:version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenNoErrors
        ThenOutput -Contains ([regex]::Escape($msbuildRoot.TrimEnd('\')))
    }

    It 'should run disable multi-CPU builds' {
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<Target Name="Build">
</Target>
</Project>
"@
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true; Verbosity = 'diag' }
        ThenNoErrors
        ThenOutput -Contains ('MSBuildNodeCount = 1')
    }

    It 'should disable file logger' {
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<Target Name="Build">
</Target>
</Project>
"@
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoFileLogger' = $true }
        ThenNoErrors
        ThenOutputNotLogged
    }

    It 'should use custom version of NuGet' {
        GivenProjectsThatCompile
        GivenNuGetVersion '5.9.3'
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenSpecificNuGetVersionInstalled
        ThenNuGetPackagesRestored
    }

    It 'should use 64-bit MSBuild' {
        GivenProject $procArchProject
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = AMD64'
    }

    It 'should use 32-bit MSBuild' {
        GivenProject $procArchProject
        GivenUse32BitIs 'true'
        WhenRunningTask -AsDeveloper
        ThenNoErrors
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = x86'
    }

    It 'should escape property values' {
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<Target Name="Build">
    <Message Importance="High" Text="`$(EscapedDoubleQuoteProperty)" />
    <Message Importance="High" Text="`$(EscapedSemicolon)" />
</Target>
</Project>
"@
        GivenVersion $script:version
        WhenRunningTask -AsDeveloper `
                        -WithParameter @{ 'Property' = @('EscapedDoubleQuoteProperty=double"quote"', 'EscapedSemicolon=semicolon;escapedsemicolon%3B') }
        $LASTEXITCODE | Should -Be 0
        ThenOutput -Contains ([regex]::escape('double"quote"'))
        ThenOutput -Contains ([regex]::escape('semicolon;escapedsemicolon;'))
    }
}
