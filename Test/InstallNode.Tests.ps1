
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'


BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    [Whiskey.Context]$script:context = $null

    function ThenNodeInstalled
    {
        param(
            [String]$Version
        )

        $nodePath | Should -Exist
        if( $Version )
        {
            $actualVersion =
                Get-ChildItem -Path (Join-Path -Path $testRoot -ChildPath '.output') |
                Where-Object { $_.Name -match '(\d+\.\d+\.\d+)' } |
                ForEach-Object { $Matches[1] }
            $Version | Should -Match ([regex]::Escape($actualVersion))
        }
    }

    function WhenInstallingNode
    {
        param(
            [String]$Version,

            [switch]$Force
        )

        $parameters = @{}
        if( $Force )
        {
            $parameters['Force'] = $true
        }
        $parameters['Version'] = $Version
        Invoke-WhiskeyTask -TaskContext $context `
                           -Parameter $parameters `
                           -Name 'InstallNode' `
                           -InformationAction SilentlyContinue

        $script:fileCreatedTime.add(((Get-ChildItem -Path $nodePath).CreationTime | Select-Object -ExpandProperty ticks))
    }

    function ThenNodeFolderDidNotChange
    {
        @( $filecreatedTime | Select-Object -Unique ) | Should -HaveCount 1
    }
}

Describe 'InstallNode' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot
        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
        $script:fileCreatedTime = New-Object Collections.ArrayList
        $script:nodePath = Join-Path -Path $script:testRoot -ChildPath '.node'
    }

    $nodeVersions = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | ForEach-Object { $_ }

    $ltsVersions =
        $nodeVersions |
        Where-Object 'date' -GT ((Get-Date).AddMonths(-31).ToString('yyyy-mm-dd')) |
        Where-Object 'version' -Match 'v(\d+)\.0\.0' |
        ForEach-Object { [int]$Matches[1] } |
        Where-Object { $_ % 2 -eq 0 } |
        ForEach-Object {
            $nodeVersions |
                Where-Object 'version' -Like "v${_}.*" |
                Select-Object -First 1 |
                Select-Object -ExpandProperty 'version' |
                ForEach-Object { $_.Substring(1) } |
                Write-Output
        }

    $latestNodeVersion =
        $nodeVersions |
        Where-Object{ $_.lts  } |
        Select-Object -ExpandProperty version |
        Select-Object -First 1 |
        ForEach-Object { $_.Substring(1) }

    It 'installs latest by default' -ForEach $latestNodeVersion {
        WhenInstallingNode
        ThenNodeInstalled -Version $_
    }

    It 'installs <_>' -ForEach $ltsVersions {
        WhenInstallingNode -Version $_
        ThenNodeInstalled -Version $_
    }

    $testCase = [pscustomobject]@{ default = $latestNodeVersion ; oldest = $ltsVersions[-1] }
    It 'overwrites installed version when using Force' -ForEach $testCase {
        WhenInstallingNode -Version $_.oldest
        ThenNodeInstalled -Version $_.oldest
        WhenInstallingNode -Force
        ThenNodeInstalled -Version $_.default
    }

    It 'does not overwrite if some version already installed' -ForEach $ltsVersions[-1] {
        WhenInstallingNode -Version $_
        WhenInstallingNode -Version $_
        ThenNodeInstalled -Version $_
        ThenNodeFolderDidNotChange
    }
}