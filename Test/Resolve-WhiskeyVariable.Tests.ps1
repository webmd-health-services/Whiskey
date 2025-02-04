
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:result = $null
    [Whiskey.Context] $script:context = $null

    function GivenEnvironmentVariable
    {
        param(
            [ValidatePattern('^ResolveWhiskey')]
            [String]$Named,
            $WithValue
        )

        [Environment]::SetEnvironmentVariable($Named,$WithValue,[EnvironmentVariableTarget]::Process)
    }

    function GivenVariable
    {
        param(
            $Name,
            $WithValue
        )

        Add-WhiskeyVariable -Context $script:context -Name $Name -Value $WithValue
    }

    function ThenErrorIs
    {
        param(
            $Pattern
        )

        $Global:Error | Should -Match $Pattern
    }

    function ThenNoErrors
    {
        param(
        )

        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenValueIs
    {
        param(
            $ExpectedValue,
            $Actual
        )

        function Test-Hashtable
        {
            param(
                $Expected,
                $Actual
            )

            $Actual | Get-Member -Name 'Keys' | Should -Not -BeNullOrEmpty
            $Actual.Count | Should -Be $Expected.Count

            foreach( $key in $Expected.Keys )
            {
                if ($null -eq $Expected[$key])
                {
                    $Actual[$key] | Should -BeNullOrEmpty
                }
                else
                {
                    if( (Get-Member 'Keys' -InputObject $Expected[$key] ) )
                    {
                        Test-Hashtable -Expected $Expected[$key] -Actual $Actual[$key]
                    }
                    else
                    {
                        $Actual[$key] | Should -Be $Expected[$key]
                    }
                }
            }
        }

        if( -not $Actual )
        {
            $Actual = $script:result
        }

        if ($null -eq $ExpectedValue)
        {
            $Actual | Should -BeNullOrEmpty
        }

        $expectedType = $ExpectedValue.GetType()
        if( (Get-Member 'Keys' -InputObject $ExpectedValue) )
        {
            Test-Hashtable $ExpectedValue $Actual
            return
        }

        if( (Get-Member -Name 'Count' -InputObject $ExpectedValue) )
        {
            Get-Member -Name 'Count' -InputObject $Actual | Should -Not -BeNullOrEmpty
            $Actual.Count | Should -Be $ExpectedValue.Count

            for( $idx = 0; $idx -lt $ExpectedValue.Count; ++$idx )
            {
                ThenValueIs $ExpectedValue[$idx] $Actual[$idx]
            }
            return
        }

        $Actual | Should -Be $ExpectedValue
        ,$Actual | Should -BeOfType $expectedType
        $Actual | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be ($ExpectedValue | Measure-Object).Count
    }

    function WhenResolving
    {
        [CmdletBinding(DefaultParameterSetName='ByPipeline')]
        param(
            [Parameter(ParameterSetName='ByPipeline',Position=0)]
            $Value,

            [Parameter(ParameterSetName='ByName')]
            $ByName,

            [hashtable] $WithArgs = @{}
        )

        $Global:Error.Clear()

        if( $PSCmdlet.ParameterSetName -eq 'ByPipeline' )
        {
            $script:result = $Value | Resolve-WhiskeyVariable -Context $script:context @WithArgs
        }
        else
        {
            $script:result = Resolve-WhiskeyVariable -Context $script:context -Name $ByName @WithArgs
        }

    }
}


AfterAll {
    Remove-Item 'env:ResolveWhiskey*'
}

Describe 'Resolve-WhiskeyVariable' {
    BeforeEach {
        $script:result = $null
        $script:testRoot = New-WhiskeyTestRoot

        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testRoot

        $script:context.Temp = $script:testRoot
    }

    It 'handles no variable in a string' {
        WhenResolving 'no variable'
        ThenValueIs 'no variable'
    }

    It 'resolves environment variable in a string' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '001'
        WhenResolving '$(ResolveWhiskeyVariable)'
        ThenValueIs '001'
    }

    It 'resolve multiple variables' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '002'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '003'
        WhenResolving '$(ResolveWhiskeyVariable1)$(ResolveWhiskeyVariable2)'
        ThenValueIs ('002003')
    }

    It 'resolves each item in an array' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '004'
        WhenResolving @( '$(ResolveWhiskeyVariable)', 'no variable', '4' )
        ThenValueIs @( '004', 'no variable', '4' )
    }

    It 'resolves each value in a hashtable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '005'
        WhenResolving @{ 'Key1' = '$(ResolveWhiskeyVariable)'; 'Key2' = 'no variable'; 'Key3' = '4' }
        ThenValueIs @{ 'Key1' = '005'; 'Key2' = 'no variable'; 'Key3' = '4' }
    }

    It 'resolves only included properties' {
        GivenVariable 'Var071' -WithValue 'Value071'
        WhenResolving @{ 'ReplaceMe1' = '$(Var071)' ; 'ReplaceMe2' = '$(Var071)' ; 'IgnoreMe' = '$(Var071)' } `
                      -WithArgs @{ Include = 'ReplaceMe1','ReplaceMe2' }
        ThenValueIs @{ 'ReplaceMe1' = 'Value071' ; 'ReplaceMe2' = 'Value071' ; 'IgnoreMe' = '$(Var071)' }
    }

    It 'resolves only non-excluded properties' {
        GivenVariable 'Var072' -WithValue 'Value072'
        WhenResolving @{ 'ReplaceMe' = '$(Var072)' ; 'IgnoreMe1' = '$(Var072)' ; 'IgnoreMe2' = '$(Var072)' } `
                      -WithArgs @{ Exclude = 'IgnoreMe1','IgnoreMe2' }
        ThenValueIs @{ 'ReplaceMe' = 'Value072' ; 'IgnoreMe1' = '$(Var072)' ; 'IgnoreMe2' = '$(Var072)' }
    }

    It 'resolve values in array nested in a hashtable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '006'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '007'
        WhenResolving @{ 'Key1' = @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }; 'Key2' = @( '$(ResolveWhiskeyVariable2)', '4' ) }
        ThenValueIs @{ 'Key1' = @{ 'SubKey1' = '006'; }; 'Key2' = @( '007', '4' ) }
    }

    It 'resolves values in a hashtable and array nested in an array ' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '008'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '009'
        WhenResolving @( @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }, @( '$(ResolveWhiskeyVariable2)', '4' ) )
        ThenValueIs @( @{ 'SubKey1' = '008'; }, @( '009', '4' ) )
    }

    It 'resolve variables in each item in a List' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '010'
        $list = New-Object 'Collections.Generic.List[String]'
        $list.Add( '$(ResolveWhiskeyVariable)' )
        $list.Add( 'fubar' )
        $list.Add( 'snafu' )
        WhenResolving @( $list )
        ThenValueIs @( @( '010', 'fubar', 'snafu' ) )
    }

    It 'resolves values in a Dictionary' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '011'
        $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
        $dictionary.Add( 'Key1', '$(ResolveWhiskeyVariable)' )
        $dictionary.Add( 'Key2', 'fubar' )
        $dictionary.Add( 'Key3', 'snafu' )
        WhenResolving @( $dictionary, '4' )
        ThenValueIs @( @{ 'Key1' = '011'; 'Key2' = 'fubar'; 'Key3' = 'snafu' }, '4' )
    }

    It 'resolves variables in keys' {
        GivenVariable 'fubar' 'cat'
        $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
        $dictionary.Add( '$(fubar)', 'in the hat' )
        WhenResolving @( $dictionary )
        ThenValueIs @{ 'cat' = 'in the hat' }
    }

    It 'resolves variable added by user' {
        GivenVariable 'fubar' 'snafu'
        WhenResolving '$(fubar)'
        ThenValueIs 'snafu'
    }

    It 'variable has precedence over environment variable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '012'
        GivenVariable 'ResolveWhiskeyVariable' 'snafu'
        WhenResolving '$(ResolveWhiskeyVariable)'
        ThenValueIs 'snafu'
    }

    It 'validates variable exists' {
        WhenResolving '$(i do not exist)' -ErrorAction SilentlyContinue
        ThenValueIs '$(i do not exist)'
        ThenErrorIs ('''i\ do\ not\ exist'' does not exist.')
    }

    It 'can ignore variable validation' {
        WhenResolving '$(i do not exist)' -ErrorAction Ignore
        ThenValueIs '$(i do not exist)'
        ThenNoErrors
    }

    It 'resolves well-known variables' {
        WhenResolving '$(WHISKEY_MSBUILD_CONFIGURATION)'
        $expectedValue = 'Debug'
        if( $script:context.ByBuildServer )
        {
            $expectedValue = 'Release'
        }
        ThenValueIs $expectedValue
    }

    It 'handles when hashtable value is null' {
        WhenResolving @{ 'Path' = $null }
        ThenValueIs @{ 'Path' = $null }
    }

    It 'ignores escaped variable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '013'
        WhenResolving '$$(ResolveWhiskeyVariable)'
        ThenValueIs '$(ResolveWhiskeyVariable)'
    }

    It 'supports both ignored and resolved variable in same string' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '014'
        WhenResolving '$$(ResolveWhiskeyVariable) $(ResolveWhiskeyVariable)'
        ThenValueIs ('$(ResolveWhiskeyVariable) 014')
    }

    It 'resolves nested variable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '015'
        GivenVariable 'FUBAR' '$(ResolveWhiskeyVariable)'
        WhenResolving '$(FUBAR) $$(ResolveWhiskeyVariable)'
        ThenValueIs ('015 $(ResolveWhiskeyVariable)')
    }

    It 'resolves variable with value 0' {
        GivenVariable 'ZeroValueVariable' 0
        WhenResolving '$(ZeroValueVariable)'
        ThenValueIs '0'
    }

    It 'resolves property name that''s a variable' {
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '016'
        WhenResolving @{ '$(ResolveWhiskeyVariable)' = 'fubarsnafu' }
        ThenValueIs @{ '016' = 'fubarsnafu' }
    }

    It 'resolves variable with no value' {
        GivenVariable 'FUBAR' ''
        WhenResolving 'prefix$(FUBAR)suffix'
        ThenValueIs 'prefixsuffix'
    }


    It 'validates variable property exists' {
        $script:context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_SCM_URI.FubarSnafu)' -ErrorAction SilentlyContinue
        ThenValueIs '$(WHISKEY_SCM_URI.FubarSnafu)'
        ThenErrorIs ('does\ not\ have\ a\ ''FubarSnafu''\ member')
    }

    It 'resolves WHISKEY_SEMVER2_PRERELEASE' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Prerelease)'
        ThenValueIs 'fubar.5'
    }

    It 'resolves WHISKEY_SEMVER2_PRERELEASE_ID' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2_PRERELEASE_ID)'
        ThenValueIs 'fubar'
    }

    It 'resolve WHISKEY_SEMVER2_PRERELEASE_ID when no prerelease' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3'
        WhenResolving '$(WHISKEY_SEMVER2_PRERELEASE_ID)'
        ThenValueIs ''
    }

    It 'resolves WHISKEY_SEMVER2_BUILD' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Build)'
        ThenValueIs 'snafu.6'
    }

    It 'resolves WHISKEY_SEMVER2_VERSION' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2_VERSION)'
        ThenValueIs '1.2.3'
    }

    It 'resolves WHISKEY_SEMVER2_MAJOR' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Major)'
        ThenValueIs '1'
    }

    It 'resolves WHISKEY_SEMVER2_MINOR' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Minor)'
        ThenValueIs '2'
    }

    It 'resolves WHISKEY_SEMVER2_PATCH' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Patch)'
        ThenValueIs '3'
    }

    It 'resolves WHISKEY_SEMVER1_PRERELEASE' {
        $script:context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Prerelease)'
        ThenValueIs 'fubar5'
    }

    It 'resolves WHISKEY_SEMVER1_VERSION' {
        $script:context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1_VERSION)'
        ThenValueIs '1.2.3'
    }

    It 'resolves WHISKEY_SEMVER1_MAJOR' {
        $script:context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Major)'
        ThenValueIs '1'
    }

    It 'resolves WHISKEY_SEMVER1_MINOR' {
        $script:context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Minor)'
        ThenValueIs '2'
    }

    It 'resolves WHISKEY_SEMVER1_PATCH' {
        $script:context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Patch)'
        ThenValueIs '3'
    }

    It 'resolves WHISKEY_BUILD_STARTED_AT' {
        $script:context.StartBuild()
        WhenResolving '$(WHISKEY_BUILD_STARTED_AT.Year)'
        ThenValueIs $script:context.StartedAt.Year.ToString()
    }

    It 'resolves WHISKEY_BUILD_URI' {
        $script:context.BuildMetadata.BuildUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_BUILD_URI.Host)'
        ThenValueIs 'example.com'
    }

    It 'resolves WHISKEY_JOB_URI' {
        $script:context.BuildMetadata.JobUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_JOB_URI.Host)'
        ThenValueIs 'example.com'
    }

    It 'resolves WHISKEY_SCM_URI' {
        $script:context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_SCM_URI.Host)'
        ThenValueIs 'example.com'
    }

    It 'validates variable syntax' {
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$(Fubar' -ErrorAction SilentlyContinue
        ThenValueIs '$(Fubar'
        ThenErrorIs 'Unclosed\ variable\ expression'
    }

    It 'ignores bad syntax on escaped variable' {
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$$(Fubar'
        ThenValueIs '$(Fubar'
    }

    It 'resolves variable method' {
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$(Fubar.Substring(0,7))'
        ThenValueIs $value.Substring(0,7)
        WhenResolving '$(Fubar.Trim("T",''.''))'
        ThenValueIs $value.Trim('T','.')
    }

    It 'parses whitespace between variable method parameters' {
        GivenVariable 'Fubar' ' a '
        WhenResolving '$(Fubar.Trim(  "b"  ))'
        ThenValueIs ' a '
    }

    It 'parses commas in variable method parameter value' {
        GivenVariable 'Fubar' ',,ab,,'
        WhenResolving '$(Fubar.Trim(  "b", ","  ))'
        ThenValueIs 'a'
    }

    It 'parses whitespace in variable method parameter value' {
        GivenVariable 'Fubar' ' a '
        WhenResolving '$(Fubar.Trim(" "))'
        ThenValueIs 'a'
    }

    It 'uses double double quote character to escape double quote character' {
        GivenVariable 'Fubar' '"a"'
        WhenResolving '$(Fubar.Trim(""""))'
        ThenValueIs 'a'
    }

    It 'uses double single quote character to escape single quote character' {
        GivenVariable 'Fubar' "'a'"
        WhenResolving "`$(Fubar.Trim(''''))"
        ThenValueIs 'a'
    }

    It 'handles enum value as variable method parameter' {
        $script:context.BuildMetadata.ScmUri = 'https://example.com/whiskey'
        WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(Scheme))'
        ThenValueIs 'https://'
        WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(''Scheme''))'
        ThenValueIs 'https://'
    }

    It 'calls Substring on string values' {
        $script:context.BuildMetadata.ScmCommitID = 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb'
        WhenResolving '$(WHISKEY_SCM_COMMIT_ID.Substring(0,7))'
        ThenValueIs 'deadbee'
    }

    It 'catches exceptions when calling variable methods' {
        GivenVariable 'Fubar' 'g'
        WhenResolving '$(Fubar.Substring(0,7))' -ErrorAction SilentlyContinue
        ThenValueIs '$(Fubar.Substring(0,7))'
        $Global:Error[0] | Should -Match 'Failed\ to\ call\b.*\bSubstring\b'
    }

    $envStaticPropertyNames =
        [Environment] |
        Get-Member -Static -MemberType Property |
        Select-Object -ExpandProperty 'Name' |
        Where-Object { $_ -notin @('StackTrace', 'TickCount', 'TickCount64', 'WorkingSet') }

    It 'resolves Environment::<_> value' -ForEach $envStaticPropertyNames {
        WhenResolving ('$({0})' -f $_)
        ThenValueIs ([Environment]::$_).ToString()
    }

    It 'uses higher precdence for Environment static properties than environment variables' {
        try
        {
            Set-Item -Path 'env:CommandLine' -Value '557'
                WhenResolving '$(CommandLine)'
            ThenValueIs ([Environment]::CommandLine)
        }
        finally
        {
            Remove-Item -Path 'CommandLine' -Force -ErrorAction Ignore
        }
    }

    It 'resolves WHISKEY_TEMP_DIRECTORY as a DirectoryInfo object' {
        WhenResolving '$(WHISKEY_TEMP_DIRECTORY)'
        ThenValueIs ([IO.Path]::GetTempPath())
        WhenResolving '$(WHISKEY_TEMP_DIRECTORY.Name)'
        ThenValueIs (Split-Path -Path ([IO.Path]::GetTempPath()) -Leaf)
    }

    It 'resolves WHISKEY_TASK_TEMP_DIRECTORY as a DirectoryInfo object' {
        WhenResolving '$(WHISKEY_TASK_TEMP_DIRECTORY)'
        ThenValueIs $script:testRoot
        WhenResolving '$(WHISKEY_TASK_TEMP_DIRECTORY.Name)'
        ThenValueIs (Split-Path -Leaf -Path $script:testRoot)
    }

    It 'resolves variable value by name' {
        $script:context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving -ByName 'WHISKEY_SEMVER2_VERSION'
        ThenValueIs '1.2.3'
    }

    It 'ignores non strings' -ForEach @(([pscustomobject]@{ fubar = 'snafu' }), $true, $false, 1, 0, 1.1) {
        WhenResolving $_
        ThenValueIs $_
    }
}
