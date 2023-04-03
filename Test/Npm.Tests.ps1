
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:failed = $false
    $script:testRoot = $null

    function GivenNodeInstalled
    {
        Install-Node -BuildRoot $script:testRoot
    }

    function ThenFile
    {
        param(
            $Named,
            $Is
        )

        $path = Join-Path -Path $script:testRoot -ChildPath $Named
        $path | Should -Exist
        $path | Should -FileContentMatchMultiline $Is
    }

    function ThenTaskFails
    {
        param(
            $WithError
        )

        $script:failed | Should -BeTrue
        $Global:Error | Where-Object { $_ -match $WithError } | Should -Not -BeNullOrEmpty
    }

    function ThenTaskSucceeds
    {
        param(
        )

        $script:failed | Should -BeFalse
    }

    function WhenRunningCommand
    {
        [CmdletBinding()]
        param(
            $Name,
            $WithArguments
        )

        $parameters = @{ }
        if( $Name )
        {
            $parameters['Command'] = $Name
        }

        if( $WithArguments )
        {
            $parameters['Argument'] = $WithArguments
        }


        $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $script:testRoot
        $script:failed = $false

        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Name 'Npm' -Parameter $parameters
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'Npm' {
    BeforeEach {
        $script:failed = $false
        $script:testRoot = New-WhiskeyTestRoot
    }

    It 'should run command' {
        WhenRunningCommand 'config' -WithArguments 'set','heading','auto','--userconfig','.npmrc'
        ThenFile '.npmrc' -Is @'
heading=auto
'@
    }

    It 'should fail the build' {
        GivenNodeInstalled
        $configPath = (Get-Item -Path $PSScriptRoot).PSDrive.Root
        $configPath = Join-Path -Path $configPath -ChildPath ([IO.Path]::GetRandomFileName())
        $configPath = Join-Path -Path $configPath -ChildPath ([IO.Path]::GetRandomFileName())
        WhenRunningCommand 'k4bphelohjx' -ErrorAction SilentlyContinue
        ThenTaskFails -WithError 'NPM\ command\ "npm\ k4bphelohjx.*"\ failed\ with\ exit\ code\ '
    }

    It 'should require command' {
        GivenNodeInstalled
        WhenRunningCommand -ErrorAction SilentlyContinue
        ThenTaskFails -WithError 'Property\ "Command\" is required'
    }

    It 'should allow no arguments' {
        GivenNodeInstalled
        WhenRunningCommand 'version'
        ThenTaskSucceeds
    }
}