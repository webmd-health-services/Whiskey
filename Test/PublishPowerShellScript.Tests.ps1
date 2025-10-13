
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    $Global:VerbosePreference = [Management.Automation.ActionPreference]::Continue

    Write-Debug 'PUBLISHPOWERSHELLSCRIPT  PSMODULEPATH'
    $env:PSModulePath -split ([IO.Path]::PathSeparator) | Write-Debug

    Write-Debug 'PUBLISHPOWERSHELLSCRIPT  START'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Write-Debug 'PUBLISHPOWERSHELLSCRIPT  POST INITIALIZE'

    $script:testRoot = $null
    $script:context = $null
    $script:credentials = @{}
    $script:testScriptName = 'MyScript'

    function Get-Error
    {
        [CmdletBinding()]
        param(
        )

        # PackageManagement and PowerShellGet leave handled errors in Global:Error so we need to filter those errors out.
        $Global:Error |
            Where-Object 'ScriptStackTrace' -NotMatch '\bPowerShellGet\b' -ErrorAction Ignore |
            Where-Object 'ScriptStackTrace' -NotMatch '\bPackageManagement\b' -ErrorAction Ignore
    }

    function Get-TestRepositoryFullPath
    {
        param(
            [Parameter(Mandatory)]
            [String] $Name
        )

        return Join-Path -Path $script:testRoot -ChildPath $Name

    }

    function GivenCredential
    {
        param(
            [Parameter(Mandatory)]
            [pscredential]$Credential,

            [Parameter(Mandatory)]
            [String]$WithID
        )

        $script:credentials[$WithID] = $Credential
    }

    function GivenPublishingFails
    {
        param(
            [Parameter(Mandatory)]
            [String]$WithError
        )

        $script:publishError = $WithError
    }

    function GivenRegisteringFails
    {
        param(
            [Parameter(Mandatory)]
            [String]$WithError
        )

        $script:registerError = $WithError
    }

    function GivenRepository
    {
        param(
            $Named,
            $At
        )

        if( -not $At )
        {
            $At = Get-TestRepositoryFullPath -Name $Named
        }

        if( -not ([IO.Path]::IsPathRooted($At)) )
        {
            $At = Join-Path -Path $script:testRoot -ChildPath $At
        }

        New-Item -Path $At -ItemType 'Directory' -Force | Out-Null
        $script:publishRoot = $At

        Register-PSRepository -Name $Named -PublishLocation $At -SourceLocation $At
        $script:repoToUnregister = $Named
    }

    function ThenFailed
    {
        param(
            [Parameter(Mandatory)]
            $WithError
        )

        $script:failed | Should -BeTrue
        Get-Error | Should -Match $WithError
    }

    function ThenManifest
    {
        param(
            [String]$ManifestPath = (Join-Path -Path $script:testRoot -ChildPath "${script:testScriptName}\${script:testScriptName}.ps1"),

            [String]$HasPrerelease
        )

        Test-ScriptFileInfo -Path $ManifestPath | Should -Not -BeNullOrEmpty
        Get-Content -Raw -Path $ManifestPath | Should -Match ".VERSION 1.2.3-$($HasPrerelease)"
    }

    function ThenRepository
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [switch] $Exists,

            [switch] $NotExists,

            [switch] $NotRegistered,

            [switch] $NotUnregistered
        )

        if( $NotRegistered )
        {
            Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 0
        }

        if( $Exists )
        {
            Get-PSRepository |
                Where-Object 'Name' -EQ $Named |
                Where-Object 'PublishLocation' -EQ $script:publishRoot |
                Should -Not -BeNullOrEmpty
        }

        if( $NotExists )
        {
            Get-PSRepository |
                Where-Object 'Name' -EQ $Named |
                Should -BeNullOrEmpty
        }

        if( $NotUnregistered )
        {
            Assert-MockCalled -CommandName 'Unregister-PSRepository' -ModuleName 'Whiskey' -Times 0
        }
    }

    function ThenScriptNotPublished
    {
        param(
            $To = $script:context.OutputDirectory.FullName
        )

        if( -not [IO.Path]::IsPathRooted($To) )
        {
            $To = Join-Path -Path $script:testRoot -ChildPath $To
        }

        Join-Path -Path $To -ChildPath "${script:testScriptName}.*.*.*.nupkg" | Should -Not -Exist
    }

    function ThenScriptPublished
    {
        param(
            $To = $script:context.OutputDirectory.FullName,
            $WithPrerelease = ''
        )

        if( -not [IO.Path]::IsPathRooted($To) )
        {
            $To = Join-Path -Path $script:testRoot -ChildPath $To
        }

        Join-Path -Path $To -ChildPath "${script:testScriptName}.*.*.*$($WithPrerelease).nupkg" | Should -Exist
    }

    function ThenSucceeded
    {
        $script:failed | Should -BeFalse
        Get-Error | Should -BeNullOrEmpty
    }

    function WhenPublishing
    {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
        param(
            [String] $ToRepo,

            [String] $RepoAt,

            [String] $ForManifestPath,

            [switch] $WithInvalidPath,

            [switch] $WithNonExistentPath,

            [switch] $WithoutPathParameter,

            [switch] $WithNoPrereleasePropertyInManifest,

            [String] $WithPrerelease,

            [String] $WithApiKey,

            [String] $WithCredentialID,

            [switch] $WithoutVersionProperty
        )

        $version = '1.2.3'
        if( $WithPrerelease )
        {
            $version = '1.2.3-{0}' -f $WithPrerelease
        }

        $script:context = New-WhiskeyTestContext -ForBuildServer `
                                                -ForVersion $version `
                                                -ForBuildRoot $script:testRoot `
                                                -IncludePSModule @( 'PackageManagement', 'PowerShellGet' )

        $TaskParameter = @{ }

        if( $ToRepo )
        {
            $TaskParameter['RepositoryName'] = $ToRepo
        }

        if( $WithInvalidPath )
        {
            $TaskParameter.Add( 'Path', ${script:testScriptName} )
            New-Item -Path $script:testRoot -ItemType 'Directory' -Name $TaskParameter['Path']
        }
        elseif( $WithNonExistentPath )
        {
            $TaskParameter.Add( 'Path', 'PathDoesNotExist.ps1' )
        }
        elseif( -not $WithoutPathParameter )
        {
            New-Item -Path $script:testRoot -ItemType 'Directory' -Name $script:testScriptName
            $script = Join-Path -Path $script:testRoot -ChildPath $script:testScriptName
            $TaskParameter.Add( 'Path', "$($script)\${script:testScriptName}.ps1" )
            if( -not $ForManifestPath )
            {
                if( $WithoutVersionProperty )
                {
                    New-Item -Path $script -ItemType 'file' -Name "${script:testScriptName}.ps1" -Value @"
<#PSScriptInfo

.GUID $([Guid]::NewGuid().ToString())

.AUTHOR $([Environment]::UserName)

.DESCRIPTION
${script:testScriptName}

#>
Param()
"@
                }
                else
                {
                    $Parms = @{
                        Path = "$($script)\${script:testScriptName}.ps1"
                        Version = $version
                        Author = [Environment]::UserName
                        Description = $script:testScriptName
                    }
                    New-ScriptFileInfo @Parms
                }
            }
            else
            {
                $TaskParameter['Path'] = $ForManifestPath
            }
        }

        Mock -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey'

        $Global:Error.Clear()
        $script:failed = $False

        if( $RepoAt )
        {
            $TaskParameter['RepositoryLocation'] = $RepoAt
        }

        if( $WithApiKey )
        {
            $TaskParameter['ApiKeyID'] = [Guid]::NewGuid().ToString()
            Add-WhiskeyApiKey -Context $script:context -ID $TaskParameter['ApiKeyID'] -Value $WithApiKey
        }

        if( $WithCredentialID )
        {
            $TaskParameter['CredentialID'] = $WithCredentialID
            foreach( $key in $script:credentials.Keys )
            {
                Add-WhiskeyCredential -Context $script:context -ID $WithCredentialID -Credential $script:credentials[$key]
            }
        }

        if( $script:repoToUnregister )
        {
            Mock -CommandName 'Register-PSRepository' -ModuleName 'Whiskey'
        }

        Mock -CommandName 'Unregister-PSRepository' -ModuleName 'Whiskey'
        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Parameter $TaskParameter -Name 'PublishPowerShellScript'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_ -ErrorAction $ErrorActionPreference
        }
    }
}

Describe 'PublishPowerShellScript' {
    BeforeEach {
        Write-Debug 'PUBLISHPOWERSHELLSCRIPT  INIT'
        Get-Module | Format-Table -AutoSize | Out-String | Write-Debug

        $script:context = $null
        $script:credentials = @{ }
        $script:failed = $false
        $script:repoToUnregister = $null
        $script:publishRoot = $null
        $script:testRoot = New-WhiskeyTestRoot
    }

    AfterEach {
        Write-Debug 'PUBLISHPOWERSHELLSCRIPT  RESET'
        Get-Module | Format-Table -AutoSize | Out-String | Write-Debug

        $Global:Error | Format-List * -force | Out-String | Write-Debug

        Reset-WhiskeyTestPSModule
        Get-PSRepository | Where-Object 'Name' -Like 'Whiskey*' | Unregister-PSRepository
        if( $script:repoToUnregister )
        {
            Unregister-PSRepository -Name $script:repoToUnregister
        }
    }

    It 'publishes the script without registering the repository' {
        GivenRepository 'RS1'
        WhenPublishing -ToRepo 'RS1'
        ThenSucceeded
        ThenScriptPublished -To 'RS1'
        ThenRepository 'RS1' -Exists -NotRegistered
    }

    It 'validates repository exists' {
        WhenPublishing -ToRepo 'RS2' -ErrorAction Silently
        ThenFailed 'a repository with that name doesn''t exist'
        ThenRepository 'RS2' -NotExists -NotUnregistered
    }

    It 'publishes prerelease script' {
        WhenPublishing -WithPrerelease 'beta1'
        ThenSucceeded
        ThenScriptPublished -WithPrerelease '-beta1'
        ThenManifest -HasPrerelease 'beta1'
    }

    It 'publishes to file system' {
        WhenPublishing
        ThenSucceeded
        ThenRepository 'Whiskey*' -NotExists
        ThenScriptPublished -To $script:context.OutputDirectory
    }

    It 'publishes with API Key' {
        Mock -CommandName 'Publish-Script' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $NuGetApiKey -eq 'API6' } `
             -Verifiable
        WhenPublishing -WithApiKey 'API6'
        ThenSucceeded
        Assert-VerifiableMock
    }

    It 'requires path property' {
        WhenPublishing -WithoutPathParameter -ErrorAction SilentlyContinue
        ThenFailed -WithError '"Path\b.*\bis mandatory'
        ThenScriptNotPublished -To $script:context.OutputDirectory
    }

    It 'validates path exists' {
        WhenPublishing -WithNonExistentPath -ErrorAction SilentlyContinue
        ThenFailed -WithError 'does\ not\ exist'
        ThenScriptNotPublished -To $script:context.OutputDirectory
    }

    It 'validates path is a file' {
        WhenPublishing -WithInvalidPath -ErrorAction SilentlyContinue
        ThenFailed -WithError 'should resolve to a file'
        ThenScriptNotPublished -To $script:context.OutputDirectory
    }

    It 'validates script manifest' {
        WhenPublishing -ForManifestPath 'fubar' -ErrorAction SilentlyContinue
        ThenFailed -WithError '"fubar"\ does\ not\ exist'
        ThenScriptNotPublished -To $script:context.OutputDirectory
    }

    It 'prefers repository location over repository name' {
        GivenRepository -Named 'RS7' -At 'RS7'
        WhenPublishing -ToRepo 'RS8' -RepoAt $script:publishRoot
        ThenSucceeded
        ThenRepository 'RS8' -NotRegistered -NotExists
        ThenRepository 'RS7' -NotRegistered -Exists
        ThenScriptPublished -To 'RS7'
    }

    It 'publishes with credential' {
        $password = ConvertTo-SecureString 'MySecretPassword' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('TestUser', $password)
        $credentialID = [Guid]::NewGuid().ToString()
        GivenCredential -Credential $credential -WithID $credentialID
        Mock -CommandName 'Publish-WhiskeyPSObject' `
             -ModuleName 'Whiskey' `
             -Verifiable
        WhenPublishing -WithCredentialID $credentialID
        ThenSucceeded
        Assert-VerifiableMock
        Assert-MockCalled -CommandName 'Publish-WhiskeyPSObject' -ModuleName 'Whiskey' -ParameterFilter {
            $CredentialID | Should -Be $credentialID
            return $true
        }
    }

    It 'validates script is versioned'{
        WhenPublishing -WithoutVersionProperty -ErrorAction SilentlyContinue
        ThenFailed -WithError 'missing required metadata properties'
        ThenScriptNotPublished -To $script:context.OutputDirectory
    }
}
