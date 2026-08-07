
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey' -Resolve) -Verbose:$false

    $script:results = $null
    $script:inWhiskey = @{ ModuleName = 'Whiskey' }

    function ThenError
    {
        param(
            [switch] $IsEmpty
        )

        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenResult
    {
        param(
            [switch] $Not,

            [Parameter(Mandatory)]
            [switch] $IsEmpty
        )

        if ($Not)
        {
            $script:results | Should -Not -BeNullOrEmpty
            $script:results | Should -BeOfType ([String])
            $script:results | Should -Match '^\d+\.\d+\.\d+'
            $script:results | Where-Object { $_ -like '*-*' } | Should -Not -BeNullOrEmpty
            return
        }

        $script:results | Should -BeNullOrEmpty
    }

    function WhenSearching
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $ForPackage
        )

        $script:results =
            InModuleScope 'Whiskey' `
                          -Parameters @{ ID = $ForPackage } `
                          -ScriptBlock { Find-WhiskeyNuGetPackageVersion -ID $ID -WarningAction Stop | Write-Output }
    }
}

Describe 'Find-WhiskeyNuGetPackageVersion' {
    BeforeEach {
        $script:results = $script:warnings = $null
        $Global:Error.Clear()
    }

    It 'finds all versions of a package' {
        WhenSearching -ForPackage 'NuGet.CommandLine'
        ThenResult -Not -IsEmpty
        ThenError -IsEmpty
    }

    It 'finds nothing for new packages' {
        WhenSearching -ForPackage 'afjdkfjsdklfjsdalkfj'
        ThenResult -IsEmpty
        ThenError -IsEmpty
    }

    $v2NuGetSources = Get-PackageSource -ProviderName 'NuGet' | Where-Object 'Location' -NotLike '*/v3/index.json'
    $v2NuGetSources | Format-Table -Auto | Out-String | Write-Verbose -Verbose
    $hasV2NuGetSources = $null -ne $v2NuGetSources
    WRite-Verbose "Has v2 Sources? ${hasV2NuGetSources}" -Verbose
    Context 'does not implement v3 endpoint' -Skip:(-not $hasV2NuGetSources) {
        It 'fallsback to Find-Package' {
            Mock -CommandName 'Invoke-RestMethod' @inWhiskey -ParameterFilter { $Uri -like '*v3/index.json' }
            WhenSearching -ForPackage 'NuGet.CommandLine'
            ThenResult -Not -IsEmpty
            ThenError -IsEmpty
        }
    }

    # Can't run these tests if there are any v2 sources.
    Context 'index returns nothing' -Skip:$hasV2NuGetSources {
        It 'returns nothing' {
            # if any v2 sources are configured, they might return results, so skip those
            Mock -CommandName 'Invoke-RestMethod' @inWhiskey -ParameterFilter { $Uri -like '*/v3/index.json' }
            WhenSearching -ForPackage 'NuGet.CommandLine'
            ThenResult -IsEmpty
            ThenError -IsEmpty
        }
    }

    Context 'no SearchQueryService resource' {
        It 'returns nothing' {
            $index = Invoke-RestMethod 'https://api.nuget.org/v3/index.json'
            $index.resources = $index.resources | Where-Object '@type' -NE 'SearchQueryService'
            Mock -CommandName 'Invoke-RestMethod' `
                 @inWhiskey `
                 -ParameterFilter { $Uri -like '*/v3/index.json' } `
                 -MockWith { $index }
            WhenSearching -ForPackage 'NuGet.CommandLine'
            ThenResult -IsEmpty
            ThenError -IsEmpty
        }
    }

    Context 'no SearchQueryService @id property' {
        It 'returns nothing' {
            $index = Invoke-RestMethod 'https://api.nuget.org/v3/index.json'
            $index.resources =
                $index.resources |
                ForEach-Object {
                    if ($_.'@type' -NE 'SearchQueryService')
                    {
                        return $_
                    }

                    $_ | Select-Object -Property '*' -ExcludeProperty '@id' | Write-Output
                }
            Mock -CommandName 'Invoke-RestMethod' `
                 @inWhiskey `
                 -ParameterFilter { $Uri -like '*/v3/index.json' } `
                 -MockWith { $index }
            WhenSearching -ForPackage 'NuGet.CommandLine'
            ThenResult -IsEmpty
            ThenError -IsEmpty
        }
    }

    Context 'no SearchQueryService URL' {
        It 'returns nothing' {
            $index = Invoke-RestMethod 'https://api.nuget.org/v3/index.json'
            $index.resources =
                $index.resources |
                ForEach-Object {
                    if ($_.'@type' -NE 'SearchQueryService')
                    {
                        return $_
                    }

                    $_.'@id' = ''
                }
            Mock -CommandName 'Invoke-RestMethod' `
                 @inWhiskey `
                 -ParameterFilter { $Uri -like '*/v3/index.json' } `
                 -MockWith { $index }
            WhenSearching -ForPackage 'NuGet.CommandLine'
            ThenResult -IsEmpty
            ThenError -IsEmpty
        }
    }
}