
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$result = $null
[Whiskey.Context]$context = $null

function GivenEnvironmentVariable
{
    param(
        [string]
        [ValidatePattern('^ResolveWhiskey')]
        $Named,
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
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function ThenErrorIs
{
    param(
        $Pattern
    )

    It 'should write an error' {
        $Global:Error | Should -Match $Pattern
    }
}

function ThenNoErrors
{
    param(
    )

    It 'should write no errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
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

        It ('should return a hashtable') {
            $Actual | Get-Member -Name 'Keys' | Should -Not -BeNullOrEmpty
        }

        It ('should not add extra values') {
            $Actual.Count | Should -Be $Expected.Count
        }

        foreach( $key in $Expected.Keys )
        {
            if( $Expected[$key] -eq $null )
            {
                It ('should leave value as null') {
                    $Actual[$key] | Should -BeNullOrEmpty
                }
            }
            else
            {
                if( (Get-Member 'Keys' -InputObject $Expected[$key] ) )
                {
                    Test-Hashtable -Expected $Expected[$key] -Actual $Actual[$key]
                }
                else
                {
                    It ('should replace variables in keys') {
                        $Actual[$key] | Should -Be $Expected[$key]
                    }
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
        It ('should return null') {
            $Actual | Should -BeNullOrEmpty
        }
    }

    $expectedType = $ExpectedValue.GetType()
    if( (Get-Member 'Keys' -InputObject $ExpectedValue) )
    {
        Test-Hashtable $ExpectedValue $Actual
        return
    }

    if( (Get-Member -Name 'Count' -InputObject $ExpectedValue) )
    {
        It( 'should return same size array' ) {
            Get-Member -Name 'Count' -InputObject $Actual | Should -Not -BeNullOrEmpty
            $Actual.Count | Should -Be $ExpectedValue.Count
        }

        for( $idx = 0; $idx -lt $ExpectedValue.Count; ++$idx )
        {
            ThenValueIs $ExpectedValue[$idx] $Actual[$idx]
        }
        return
    }

    It ('should replace variables in {0}' -f $expectedType.Name) {
        $Actual | Should -Be $ExpectedValue
        ,$Actual | Should -BeOfType $expectedType
    }

    It ('should not add extra items') {
        $Actual | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be ($ExpectedValue | Measure-Object).Count
    }
}

function WhenResolving
{
    [CmdletBinding()]
    param(
        $Value
    )

    $Global:Error.Clear()
    $script:result = $Value | Resolve-WhiskeyVariable -Context $context
}

Describe 'Resolve-WhiskeyVariable.when passed a string with no variable' {
    Init
    WhenResolving 'no variable'
    ThenValueIs 'no variable'
}

Describe 'Resolve-WhiskeyVariable.when passed a string with an environment variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '001'
    WhenResolving '$(ResolveWhiskeyVariable)'
    ThenValueIs '001'
}

Describe 'Resolve-WhiskeyVariable.when passed a string with multiple variables' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '002'
    GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '003'
    WhenResolving '$(ResolveWhiskeyVariable1)$(ResolveWhiskeyVariable2)'
    ThenValueIs ('002003')
}
    
Describe 'Resolve-WhiskeyVariable.when passed a non-string' {
    Init
    WhenResolving 4
    ThenValueIs '4'
}

Describe 'Resolve-WhiskeyVariable.when passed an array' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '004'
    WhenResolving @( '$(ResolveWhiskeyVariable)', 'no variable', '4' )
    ThenValueIs @( '004', 'no variable', '4' )
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '005'
    WhenResolving @{ 'Key1' = '$(ResolveWhiskeyVariable)'; 'Key2' = 'no variable'; 'Key3' = '4' }
    ThenValueIs @{ 'Key1' = '005'; 'Key2' = 'no variable'; 'Key3' = '4' }
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable with an array and hashtable in it' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '006'
    GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '007'
    WhenResolving @{ 'Key1' = @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }; 'Key2' = @( '$(ResolveWhiskeyVariable2)', '4' ) }
    ThenValueIs @{ 'Key1' = @{ 'SubKey1' = '006'; }; 'Key2' = @( '007', '4' ) }
}

Describe 'Resolve-WhiskeyVariable.when passed an array with an array and hashtable in it' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable1' -WithValue '008'
    GivenEnvironmentVariable 'ResolveWhiskeyVariable2' -WithValue '009'
    WhenResolving @( @{ 'SubKey1' = '$(ResolveWhiskeyVariable1)'; }, @( '$(ResolveWhiskeyVariable2)', '4' ) )
    ThenValueIs @( @{ 'SubKey1' = '008'; }, @( '009', '4' ) )
}

Describe 'Resolve-WhiskeyVariable.when passed a List object' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '010'
    $list = New-Object 'Collections.Generic.List[string]'
    $list.Add( '$(ResolveWhiskeyVariable)' )
    $list.Add( 'fubar' )
    $list.Add( 'snafu' )
    WhenResolving @( $list )
    ThenValueIs @( @( '010', 'fubar', 'snafu' ) )
}

Describe 'Resolve-WhiskeyVariable.when passed a Dictionary' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '011'
    $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
    $dictionary.Add( 'Key1', '$(ResolveWhiskeyVariable)' )
    $dictionary.Add( 'Key2', 'fubar' )
    $dictionary.Add( 'Key3', 'snafu' )
    WhenResolving @( $dictionary, '4' )
    ThenValueIs @( @{ 'Key1' = '011'; 'Key2' = 'fubar'; 'Key3' = 'snafu' }, '4' )
}

Describe 'Resolve-WhiskeyVariable.when passed a Dictionary with variable in a key' {
    Init
    GivenVariable 'fubar' 'cat'
    $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
    $dictionary.Add( '$(fubar)', 'in the hat' )
    WhenResolving @( $dictionary )
    ThenValueIs @{ 'cat' = 'in the hat' }
}

Describe 'Resolve-WhiskeyVariable.when using a custom variable' {
    Init
    GivenVariable 'fubar' 'snafu'
    WhenResolving '$(fubar)'
    ThenValueIs 'snafu'
}

Describe 'Resolve-WhiskeyVariable.when using a variable with the same name as an environment variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '012'
    GivenVariable 'ResolveWhiskeyVariable' 'snafu'
    WhenResolving '$(ResolveWhiskeyVariable)'
    ThenValueIs 'snafu'
}

Describe 'Resolve-WhiskeyVariable.when using a variable that doesn''t exist' {
    Init
    WhenResolving '$(i do not exist)' -ErrorAction SilentlyContinue
    ThenValueIs '$(i do not exist)'
    ThenErrorIs ('''i\ do\ not\ exist'' does not exist.')
}

Describe 'Resolve-WhiskeyVariable.when ignoring errors' {
    Init
    WhenResolving '$(i do not exist)' -ErrorAction Ignore
    ThenValueIs '$(i do not exist)'
    ThenNoErrors
}

Describe 'Resolve-WhiskeyVariable.when using well-known variables' {
    Init
    WhenResolving '$(WHISKEY_MSBUILD_CONFIGURATION)'
    $expectedValue = 'Debug'
    if( $context.ByBuildServer )
    {
        $expectedValue = 'Release'
    }
    ThenValueIs $expectedValue
}

Describe 'Resolve-WhiskeyVariable.when hashtable key value is empty' {
    Init
    WhenResolving @{ 'Path' = $null }
    ThenValueIs @{ 'Path' = $null }
}

Describe 'Resolve-WhiskeyVariable.when escaping variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '013'
    WhenResolving '$$(ResolveWhiskeyVariable)'
    ThenValueIs '$(ResolveWhiskeyVariable)'
}

Describe 'Resolve-WhiskeyVariable.when escaping variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '014'
    WhenResolving '$$(ResolveWhiskeyVariable) $(ResolveWhiskeyVariable)'
    ThenValueIs ('$(ResolveWhiskeyVariable) 014')
}

Describe 'Resolve-WhiskeyVariable.when nested variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '015'
    GivenVariable 'FUBAR' '$(ResolveWhiskeyVariable)'
    WhenResolving '$(FUBAR) $$(ResolveWhiskeyVariable)'
    ThenValueIs ('015 $(ResolveWhiskeyVariable)')
}

Describe 'Resolve-WhiskeyVariable.when variable has a value of ''0''' {
    Init
    GivenVariable 'ZeroValueVariable' 0
    WhenResolving '$(ZeroValueVariable)'
    ThenValueIs '0'
}

Describe 'Resolve-WhiskeyVariable.when property name is variable' {
    Init
    GivenEnvironmentVariable 'ResolveWhiskeyVariable' -WithValue '016'
    WhenResolving @{ '$(ResolveWhiskeyVariable)' = 'fubarsnafu' }
    ThenValueIs @{ '016' = 'fubarsnafu' }
}

Describe 'Resolve-WhiskeyVariable.when value is empty' {
    Init
    GivenVariable 'FUBAR' ''
    WhenResolving 'prefix$(FUBAR)suffix'
    ThenValueIs 'prefixsuffix'
}

Describe 'Resolve-WhiskeyVariable.when variable doesn''t have a requested property' {
    Init
    $context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
    WhenResolving '$(WHISKEY_SCM_URI.FubarSnafu)' -ErrorAction SilentlyContinue
    ThenValueIs '$(WHISKEY_SCM_URI.FubarSnafu)'
    ThenErrorIs ('does\ not\ have\ a\ ''FubarSnafu''\ member')
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PRERELEASE' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2.Prerelease)'
    ThenValueIs 'fubar.5'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_BUILD' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2.Build)'
    ThenValueIs 'snafu.6'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_VERSION' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2_VERSION)'
    ThenValueIs '1.2.3'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_MAJOR' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2.Major)'
    ThenValueIs '1'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_MINOR' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2.Minor)'
    ThenValueIs '2'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER2_PATCH' {
    Init
    $context.Version.SemVer2 = [SemVersion.SemanticVersion]'1.2.3-fubar.5+snafu.6'
    WhenResolving '$(WHISKEY_SEMVER2.Patch)'
    ThenValueIs '3'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_PRERELEASE' {
    Init
    $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
    WhenResolving '$(WHISKEY_SEMVER1.Prerelease)'
    ThenValueIs 'fubar5'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_VERSION' {
    Init
    $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
    WhenResolving '$(WHISKEY_SEMVER1_VERSION)'
    ThenValueIs '1.2.3'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_MAJOR' {
    Init
    $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
    WhenResolving '$(WHISKEY_SEMVER1.Major)'
    ThenValueIs '1'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_MINOR' {
    Init
    $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
    WhenResolving '$(WHISKEY_SEMVER1.Minor)'
    ThenValueIs '2'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SEMVER1_PATCH' {
    Init
    $context.Version.SEMVER1 = [SemVersion.SemanticVersion]'1.2.3-fubar5'
    WhenResolving '$(WHISKEY_SEMVER1.Patch)'
    ThenValueIs '3'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_BUILD_STARTED_AT' {
    Init
    $context.StartedAt = Get-Date
    WhenResolving '$(WHISKEY_BUILD_STARTED_AT.Year)'
    ThenValueIs $context.StartedAt.Year.ToString()
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_BUILD_URI' {
    Init
    $context.BuildMetadata.BuildUri = 'https://example.com/path?query=string'
    WhenResolving '$(WHISKEY_BUILD_URI.Host)'
    ThenValueIs 'example.com'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_JOB_URI' {
    Init
    $context.BuildMetadata.JobUri = 'https://example.com/path?query=string'
    WhenResolving '$(WHISKEY_JOB_URI.Host)'
    ThenValueIs 'example.com'
}

Describe 'Resolve-WhiskeyVariable.WHISKEY_SCM_URI' {
    Init
    $context.BuildMetadata.ScmUri = 'https://example.com/path?query=string'
    WhenResolving '$(WHISKEY_SCM_URI.Host)'
    ThenValueIs 'example.com'
}

Describe 'Resolve-WhiskeyVariable.when variable not terminated' {
    Init
    $value = "The quick brown fox jumped over the lazy dog."
    GivenVariable 'Fubar' $value
    WhenResolving '$(Fubar' -ErrorAction SilentlyContinue
    ThenValueIs '$(Fubar'
    ThenErrorIs 'Unclosed\ variable\ expression'
}

Describe 'Resolve-WhiskeyVariable.when variable not terminated but escaped' {
    Init
    $value = "The quick brown fox jumped over the lazy dog."
    GivenVariable 'Fubar' $value
    WhenResolving '$$(Fubar'
    ThenValueIs '$(Fubar'
}

Describe 'Resolve-WhiskeyVariable.when calling variable object method' {
    Init
    $value = "The quick brown fox jumped over the lazy dog."
    GivenVariable 'Fubar' $value
    WhenResolving '$(Fubar.Substring(0,7))'
    ThenValueIs $value.Substring(0,7)
    WhenResolving '$(Fubar.Trim("T",''.''))'
    ThenValueIs $value.Trim('T','.')
}

Describe 'Resolve-WhiskeyVariable.when method call parmeters have whitespace' {
    Init
    GivenVariable 'Fubar' ' a '
    WhenResolving '$(Fubar.Trim(  "b"  ))'
    ThenValueIs ' a '
}

Describe 'Resolve-WhiskeyVariable.when method call parameter contains a comma' {
    Init
    GivenVariable 'Fubar' ',,ab,,'
    WhenResolving '$(Fubar.Trim(  "b", ","  ))'
    ThenValueIs 'a'
}

Describe 'Resolve-WhiskeyVariable.when method call parameter contains whitespace' {
    Init
    GivenVariable 'Fubar' ' a '
    WhenResolving '$(Fubar.Trim(" "))'
    ThenValueIs 'a'
}

Describe 'Resolve-WhiskeyVariable.when method call parameter is double-quoted and contains double quote' {
    Init
    GivenVariable 'Fubar' '"a"'
    WhenResolving '$(Fubar.Trim(""""))'
    ThenValueIs 'a'
}

Describe 'Resolve-WhiskeyVariable.when method call parameter is single-quoted and contains single quote' {
    Init
    GivenVariable 'Fubar' "'a'"
    WhenResolving "`$(Fubar.Trim(''''))"
    ThenValueIs 'a'
}

Describe 'Resolve-WhiskeyVariable.when method parameter is enumeration' {
    Init
    $context.BuildMetadata.ScmUri = 'https://example.com/whiskey'
    WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(Scheme))'
    ThenValueIs 'https://'
    WhenResolving '$(WHISKEY_SCM_URI.GetLeftPart(''Scheme''))'
    ThenValueIs 'https://'
}

Describe 'Resolve-WhiskeyVariable.when getting substring of a variable value' {
    Init
    $context.BuildMetadata.ScmCommitID = 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb'
    WhenResolving '$(WHISKEY_SCM_COMMIT_ID.Substring(0,7))'
    ThenValueIs 'deadbee'
}

Describe 'Resolve-WhiskeyVariable.when method call is invalid' {
    Init
    GivenVariable 'Fubar' 'g'
    WhenResolving '$(Fubar.Substring(0,7))' -ErrorAction SilentlyContinue
    ThenValueIs '$(Fubar.Substring(0,7))'
    It ('should explain that method call failed') {
        $Global:Error[0] | Should -Match 'Failed\ to\ call\b.*\bSubstring\b'
    }
}

Describe ('Resolve-WhiskeyVariable.when resolving variables for Environment static properties') {
    foreach( $dotNetEnvironmentPropertyName in ([Environment] | Get-Member -Static -MemberType Property | Select-Object -ExpandProperty 'Name') )
    {
        # These variables don't test very well.
        if( $dotNetEnvironmentPropertyName -in @( 'StackTrace' ) )
        {
            continue
        }

        Context $dotNetEnvironmentPropertyName {
            Init
            WhenResolving ('$({0})' -f $dotNetEnvironmentPropertyName)
            ThenValueIs ([Environment]::$dotNetEnvironmentPropertyName).ToString()
        }
    }
}

Describe 'Resolve-WhiskeyVariable.when using an Environment property name with the same name as an environment variable' {
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

Remove-Item 'env:ResolveWhiskey*'
