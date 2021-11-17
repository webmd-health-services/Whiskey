
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$result = $null
[Whiskey.Context]$context = $null

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
        $Value
    )

    Add-WhiskeyVariable -Context $context -Name $Name -Value $Value
}

function Init
{
    $script:result = $null
    $script:testRoot = New-WhiskeyTestRoot

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot

    $context.Temp = $testRoot
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
            if( $Expected[$key] -eq $null )
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
        $Actual = $result
    }

    if( $ExpectedValue -eq $null )
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
        $ByName
    )

    $Global:Error.Clear()

    if( $PSCmdlet.ParameterSetName -eq 'ByPipeline' )
    {
        $script:result = $Value | Resolve-WhiskeyVariable -Context $context
    }
    else
    {
        $script:result = Resolve-WhiskeyVariable -Context $context -Name $ByName
    }

}

Describe 'Resolve-WhiskeyVariable.when passed a string with no variable' {
    It 'should do nothing' {
        Init
        WhenResolving 'no variable'
        ThenValueIs 'no variable'
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a string with an environment variable' {
    It 'should resolve variable value' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '001'
        WhenResolving '$(ResolveWhiskeyVariable)'
        ThenValueIs '001'
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a string with multiple variables' {
    It 'should resolve all variables' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '002'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '003'
        WhenResolving '$(ResolveWhiskeyVariable1)$(ResolveWhiskeyVariable2)'
        ThenValueIs ('002003')
    }
}
        
Describe 'Resolve-WhiskeyVariable.when passed a non-string' {
    It 'should do nothing' {
        Init
        WhenResolving 4
        ThenValueIs '4'
    }
}

Describe 'Resolve-WhiskeyVariable.when passed an array' {
    It 'should resolve variables in each item' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '004'
        WhenResolving @( '$(ResolveWhiskeyVariable)', 'no variable', '4' )
        ThenValueIs @( '004', 'no variable', '4' )
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable' {
    It 'should resolve variables in values' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '005'
        WhenResolving @{ 'Key1' = '$(ResolveWhiskeyVariable)'; 'Key2' = 'no variable'; 'Key3' = '4' }
        ThenValueIs @{ 'Key1' = '005'; 'Key2' = 'no variable'; 'Key3' = '4' }
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable with an array and hashtable in it' {
    It 'should resolve values in nested objects' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '006'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '007'
        WhenResolving @{ 'Key1' = @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }; 'Key2' = @( '$(ResolveWhiskeyVariable2)', '4' ) }
        ThenValueIs @{ 'Key1' = @{ 'SubKey1' = '006'; }; 'Key2' = @( '007', '4' ) }
    }
}

Describe 'Resolve-WhiskeyVariable.when passed an array with an array and hashtable in it' {
    It 'should resolve nested objects' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '008'
        GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '009'
        WhenResolving @( @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }, @( '$(ResolveWhiskeyVariable2)', '4' ) )
        ThenValueIs @( @{ 'SubKey1' = '008'; }, @( '009', '4' ) )
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a List object' {
    It 'should resolve variables in each item' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '010'
        $list = New-Object 'Collections.Generic.List[String]'
        $list.Add( '$(ResolveWhiskeyVariable)' )
        $list.Add( 'fubar' )
        $list.Add( 'snafu' )
        WhenResolving @( $list )
        ThenValueIs @( @( '010', 'fubar', 'snafu' ) )
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a Dictionary' {
    It 'should resolve variables in values' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '011'
        $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
        $dictionary.Add( 'Key1', '$(ResolveWhiskeyVariable)' )
        $dictionary.Add( 'Key2', 'fubar' )
        $dictionary.Add( 'Key3', 'snafu' )
        WhenResolving @( $dictionary, '4' )
        ThenValueIs @( @{ 'Key1' = '011'; 'Key2' = 'fubar'; 'Key3' = 'snafu' }, '4' )
    }
}

Describe 'Resolve-WhiskeyVariable.when passed a Dictionary with variable in a key' {
    It 'should resolve variables in keys' {
        Init
        GivenVariable 'fubar' 'cat'
        $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
        $dictionary.Add( '$(fubar)', 'in the hat' )
        WhenResolving @( $dictionary )
        ThenValueIs @{ 'cat' = 'in the hat' }
    }
}

Describe 'Resolve-WhiskeyVariable.when using a custom variable' {
    It 'should resolve variable' {
        Init
        GivenVariable 'fubar' 'snafu'
        WhenResolving '$(fubar)'
        ThenValueIs 'snafu'
    }
}

Describe 'Resolve-WhiskeyVariable.when using a variable with the same name as an environment variable' {
    It 'should use variable over environment variable' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '012'
        GivenVariable 'ResolveWhiskeyVariable' 'snafu'
        WhenResolving '$(ResolveWhiskeyVariable)'
        ThenValueIs 'snafu'
    }
}

Describe 'Resolve-WhiskeyVariable.when using a variable that does not exist' {
    It 'should fail' {
        Init
        WhenResolving '$(i do not exist)' -ErrorAction SilentlyContinue
        ThenValueIs '$(i do not exist)'
        ThenErrorIs ('''i\ do\ not\ exist'' does not exist.')
    }
}

Describe 'Resolve-WhiskeyVariable.when ignoring errors' {
    It 'should not fail' {
        Init
        WhenResolving '$(i do not exist)' -ErrorAction Ignore
        ThenValueIs '$(i do not exist)'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyVariable.when using well-known variables' {
    It 'should resolve' {
        Init
        WhenResolving '$(WHISKEY_MSBUILD_CONFIGURATION)'
        $expectedValue = 'Debug'
        if( $context.ByBuildServer )
        {
            $expectedValue = 'Release'
        }
        ThenValueIs $expectedValue
    }
}

Describe 'Resolve-WhiskeyVariable.when hashtable key value is empty' {
    It 'should not fail' {
        Init
        WhenResolving @{ 'Path' = $null }
        ThenValueIs @{ 'Path' = $null }
    }
}

Describe 'Resolve-WhiskeyVariable.when escaping variable' {
    It 'should not resolve variable' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '013'
        WhenResolving '$$(ResolveWhiskeyVariable)'
        ThenValueIs '$(ResolveWhiskeyVariable)'
    }
}

Describe 'Resolve-WhiskeyVariable.when escaping variable' {
    It 'should not resolve variable' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '014'
        WhenResolving '$$(ResolveWhiskeyVariable) $(ResolveWhiskeyVariable)'
        ThenValueIs ('$(ResolveWhiskeyVariable) 014')
    }
}

Describe 'Resolve-WhiskeyVariable.when nested variable' {
    It 'should resolve nested variable' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '015'
        GivenVariable 'FUBAR' '$(ResolveWhiskeyVariable)'
        WhenResolving '$(FUBAR) $$(ResolveWhiskeyVariable)'
        ThenValueIs ('015 $(ResolveWhiskeyVariable)')
    }
}

Describe 'Resolve-WhiskeyVariable.when variable has a value of "0"'  {
    It 'should resolve variable' {
        Init
        GivenVariable 'ZeroValueVariable' 0
        WhenResolving '$(ZeroValueVariable)'
        ThenValueIs '0'
    }
}

Describe 'Resolve-WhiskeyVariable.when property name is variable' {
    It 'should resolve property names' {
        Init
        GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '016'
        WhenResolving @{ '$(ResolveWhiskeyVariable)' = 'fubarsnafu' }
        ThenValueIs @{ '016' = 'fubarsnafu' }
    }
}

Describe 'Resolve-WhiskeyVariable.when value is empty' {
    It 'should replace' {
        Init
        GivenVariable 'FUBAR' ''
        WhenResolving 'prefix$(FUBAR)suffix'
        ThenValueIs 'prefixsuffix'
    }
}

Describe 'Resolve-WhiskeyVariable.when variable does not have a requested property' {
    It 'should fail' {
        Init
        $context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_SCM_URI.FubarSnafu)' -ErrorAction SilentlyContinue
        ThenValueIs '$(WHISKEY_SCM_URI.FubarSnafu)'
        ThenErrorIs ('does\ not\ have\ a\ ''FubarSnafu''\ member')
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PRERELEASE' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Prerelease)'
        ThenValueIs 'fubar.5'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PRERELEASE_ID' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2_PRERELEASE_ID)'
        ThenValueIs 'fubar'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PRERELEASE_ID when version doesn''t contain a prerelease label' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3'
        WhenResolving '$(WHISKEY_SEMVER2_PRERELEASE_ID)'
        ThenValueIs ''
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_BUILD' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Build)'
        ThenValueIs 'snafu.6'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_VERSION' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2_VERSION)'
        ThenValueIs '1.2.3'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_MAJOR' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Major)'
        ThenValueIs '1'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_MINOR' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Minor)'
        ThenValueIs '2'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PATCH' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving '$(WHISKEY_SEMVER2.Patch)'
        ThenValueIs '3'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_PRERELEASE' {
    It 'should resolve' {
        Init
        $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Prerelease)'
        ThenValueIs 'fubar5'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_VERSION' {
    It 'should resolve' {
        Init
        $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1_VERSION)'
        ThenValueIs '1.2.3'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_MAJOR' {
    It 'should resolve' {
        Init
        $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Major)'
        ThenValueIs '1'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_MINOR' {
    It 'should resolve' {
        Init
        $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Minor)'
        ThenValueIs '2'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_PATCH' {
    It 'should resolve' {
        Init
        $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
        WhenResolving '$(WHISKEY_SEMVER1.Patch)'
        ThenValueIs '3'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_BUILD_STARTED_AT' {
    It 'should resolve' {
        Init
        $context.StartBuild()
        WhenResolving '$(WHISKEY_BUILD_STARTED_AT.Year)'
        ThenValueIs $context.StartedAt.Year.ToString()
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_BUILD_URI' {
    It 'should resolve' {
        Init
        $context.BuildMetadata.BuildUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_BUILD_URI.Host)'
        ThenValueIs 'example.com'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_JOB_URI' {
    It 'should resolve' {
        Init
        $context.BuildMetadata.JobUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_JOB_URI.Host)'
        ThenValueIs 'example.com'
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SCM_URI' {
    It 'should resolve' {
        Init
        $context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
        WhenResolving '$(WHISKEY_SCM_URI.Host)'
        ThenValueIs 'example.com'
    }
}

Describe 'Resolve-WhiskeyVariable.when variable not terminated' {
    It 'should fail' {
        Init
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$(Fubar' -ErrorAction SilentlyContinue
        ThenValueIs '$(Fubar'
        ThenErrorIs 'Unclosed\ variable\ expression'
    }
}

Describe 'Resolve-WhiskeyVariable.when variable not terminated but escaped' {
    It 'should pass' {
        Init
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$$(Fubar'
        ThenValueIs '$(Fubar'
    }
}

Describe 'Resolve-WhiskeyVariable.when calling variable object method' {
    It 'should resolve variable' {
        Init
        $value = "The quick brown fox jumped over the lazy dog."
        GivenVariable 'Fubar' $value
        WhenResolving '$(Fubar.Substring(0,7))'
        ThenValueIs $value.Substring(0,7)
        WhenResolving '$(Fubar.Trim("T",''.''))'
        ThenValueIs $value.Trim('T','.')
    }
}

Describe 'Resolve-WhiskeyVariable.when method call parmeters have whitespace' {
    It 'should ignore whitespace' {
        Init
        GivenVariable 'Fubar' ' a '
        WhenResolving '$(Fubar.Trim(  "b"  ))'
        ThenValueIs ' a '
    }
}

Describe 'Resolve-WhiskeyVariable.when method call parameter contains a comma' {
    It 'should parse commas correctly' {
        Init
        GivenVariable 'Fubar' ',,ab,,'
        WhenResolving '$(Fubar.Trim(  "b", ","  ))'
        ThenValueIs 'a'
    }
}

Describe 'Resolve-WhiskeyVariable.when method call parameter contains quoted whitespace' {
    It 'should allow whitespace' {
        Init
        GivenVariable 'Fubar' ' a '
        WhenResolving '$(Fubar.Trim(" "))'
        ThenValueIs 'a'
    }
}

Describe 'Resolve-WhiskeyVariable.when method call parameter is double-quoted and contains double quote' {
    It 'should allow escaping quote character' {
        Init
        GivenVariable 'Fubar' '"a"'
        WhenResolving '$(Fubar.Trim(""""))'
        ThenValueIs 'a'
    }
}

Describe 'Resolve-WhiskeyVariable.when method call parameter is single-quoted and contains single quote' {
    It 'should allow escaping quote character' {
        Init
        GivenVariable 'Fubar' "'a'"
        WhenResolving "`$(Fubar.Trim(''''))"
        ThenValueIs 'a'
    }
}

Describe 'Resolve-WhiskeyVariable.when method parameter is enumeration' {
    It 'should handle it because PowerShell does' {
        Init
        $context.BuildMetadata.ScmUri = 'https://example.com/whiskey'
        WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(Scheme))'
        ThenValueIs 'https://'
        WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(''Scheme''))'
        ThenValueIs 'https://'
    }
}

Describe 'Resolve-WhiskeyVariable.when getting substring of a variable value' {
    It 'should get the substring' {
        Init
        $context.BuildMetadata.ScmCommitID = 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb'
        WhenResolving '$(WHISKEY_SCM_COMMIT_ID.Substring(0,7))'
        ThenValueIs 'deadbee'
    }
}

Describe 'Resolve-WhiskeyVariable.when method call is invalid' {
    It 'should fail' {
        Init
        GivenVariable 'Fubar' 'g'
        WhenResolving '$(Fubar.Substring(0,7))' -ErrorAction SilentlyContinue
        ThenValueIs '$(Fubar.Substring(0,7))'
        $Global:Error[0] | Should -Match 'Failed\ to\ call\b.*\bSubstring\b'
    }
}

Describe ('Resolve-WhiskeyVariable.when resolving variables for Environment static properties') {
    foreach( $dotNetEnvironmentPropertyName in ([Environment] | Get-Member -Static -MemberType Property | Select-Object -ExpandProperty 'Name') )
    {
        # These variables don't test very well.
        if( $dotNetEnvironmentPropertyName -in @( 'StackTrace', 'TickCount', 'TickCount64', 'WorkingSet' ) )
        {
            continue
        }

        Context $dotNetEnvironmentPropertyName {
            It 'should resolve' {
                Init
                WhenResolving ('$({0})' -f $dotNetEnvironmentPropertyName)
                ThenValueIs ([Environment]::$dotNetEnvironmentPropertyName).ToString()
            }
        }
    }
}

Describe 'Resolve-WhiskeyVariable.when using an Environment property name with the same name as an environment variable' {
    It 'should use Environment static property' {
        try
        {
            Set-Item -Path 'env:CommandLine' -Value '557'
            Init
            WhenResolving '$(CommandLine)'
            ThenValueIs ([Environment]::CommandLine)
        }
        finally
        {
            Remove-Item -Path 'CommandLine' -Force -ErrorAction Ignore
        }
    }
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_TEMP_DIRECTORY' {
    It 'should resolve as DirectoryInfo object' {
        Init
        WhenResolving '$(WHISKEY_TEMP_DIRECTORY)'
        ThenValueIs ([IO.Path]::GetTempPath())
        WhenResolving '$(WHISKEY_TEMP_DIRECTORY.Name)'
        ThenValueIs (Split-Path -Path ([IO.Path]::GetTempPath()) -Leaf)
    }
}

Describe 'Resolve-WhiskeyVariable.exposes current task''s temp directory as Whiskey variable' {
    It 'should resolve as a DirectoryInfo object' {
        Init
        WhenResolving '$(WHISKEY_TASK_TEMP_DIRECTORY)'
        ThenValueIs $testRoot
        WhenResolving '$(WHISKEY_TASK_TEMP_DIRECTORY.Name)'
        ThenValueIs (Split-Path -Leaf -Path $testRoot)
    }
}

Describe 'Resolve-WhiskeyVariable.when resolving by name' {
    It 'should resolve' {
        Init
        $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
        WhenResolving -ByName 'WHISKEY_SEMVER2_VERSION'
        ThenValueIs '1.2.3'
    }
}

Remove-Item 'env:ResolveWhiskey*'
