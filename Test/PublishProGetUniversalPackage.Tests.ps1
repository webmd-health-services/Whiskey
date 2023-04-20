
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:progetUrl = $null
    $script:credentialID = $null
    $script:credential = $null
    $script:feedName = $null
    $script:path = $null
    $script:threwException = $false
    $script:noAccessToProGet = $null
    $script:myTimeout = $null
    $script:packageExists = $false
    $script:overwrite = $false
    $script:properties = @{ }

    function GivenProperty
    {
        param(
            $Name,
            $Is
        )

        $script:properties[$Name] = $Is
    }

    function GivenOverwrite
    {
        $script:overwrite = $true
    }

    function GivenNoPath
    {
        $script:path = $null
    }

    function GivenPackageExists
    {
        $script:packageExists = $true
    }

    function GivenPath
    {
        param(
            $Path
        )

        $script:path = $Path
    }

    function GivenProGetIsAt
    {
        param(
            $Url
        )

        $script:progetUrl = $Url
    }

    function GivenCredential
    {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
        param(
            [Parameter(Mandatory,Position=0)]
            $Credential,

            [Parameter(Mandatory)]
            $WithID
        )

        $script:noAccessToProGet = $false
        $password = ConvertTo-SecureString -AsPlainText -Force -String $Credential
        $script:credential = New-Object 'Management.Automation.PsCredential' $Credential,$password
        $script:credentialID = $WithID
    }

    function GivenNoAccessToProGet
    {
        $script:noAccessToProGet = $true
    }

    function GivenNoParameters
    {
        $script:credentialID = $null
        $script:feedName = $null
        $script:path = $null
        $script:progetUrl = $null
        $script:credential = $null
    }

    function GivenTimeout
    {
        param(
            $Timeout
        )

        $script:myTimeout = $Timeout
    }

    function GivenUniversalFeed
    {
        param(
            $Named
        )

        $script:feedName = $Named
    }

    function GivenUpackFile
    {
        param(
            $Name
        )

        New-Item -Path (Join-Path -Path $script:testRoot -ChildPath ('.output\{0}' -f $Name)) -Force -ItemType 'File'
    }

    function ThenPackageOverwritten
    {
        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter {
                            #$DebugPreference = 'continue'
                            Write-WhiskeyDebug -Message ('Force  expected  true')
                            Write-WhiskeyDebug -Message ('       actual    false' -f $Force)
                            $Force.ToBool()
                        }
    }

    function ThenPackageNotPublished
    {
        param(
            $FileName
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $PackagePath -eq (Join-Path -Path $script:testRoot -ChildPath ('.output\{0}' -f $FileName)) } `
                        -Times 0
    }

    function ThenPackagePublished
    {
        param(
            $FileName
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter {
                            $expectedPath = Join-Path -Path '.\.output' -ChildPath $FileName
                            Write-Debug ('PackagePath  expected  {0}' -f $expectedPath)
                            Write-Debug ('             actual    {0}' -f $PackagePath)
                            $PackagePath -eq $expectedPath
                        }
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenPackagePublishedAs
    {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
        param(
            $Credential
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Session.Credential.UserName -eq $Credential }
        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Session.Credential.GetNetworkCredential().Password -eq $Credential }
    }

    function ThenPackagePublishedAt
    {
        param(
            $Url
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug -Message ('Url  expected  {0}' -f $Url)
            Write-WhiskeyDebug -Message ('     actual    {0}' -f $Session.Uri)
            $session | Format-List | Out-String | Write-WhiskeyDebug
            $Session.Uri -eq $Url
        }
    }

    function ThenPackagePublishedToFeed
    {
        param(
            $Named
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $FeedName -eq $Named }
    }

    function ThenPackagePublishedWithTimeout
    {
        param(
            $ExpectedTimeout
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug -Message ('Timeout  expected  {0}' -f $Timeout)
            Write-WhiskeyDebug -Message ('         actual    {0}' -f $ExpectedTimeout)
            $Timeout -eq $ExpectedTimeout
        }
    }

    function ThenPackagePublishedWithDefaultTimeout
    {
        param(
        )

        Should -Invoke 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $null -eq $Timeout }
    }

    function ThenTaskCompleted
    {
        param(
        )

        $script:threwException | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenTaskFailed
    {
        param(
            $Pattern
        )

        $script:threwException | Should -BeTrue
        $Global:Error | Should -Match $Pattern
    }

    function WhenPublishingPackage
    {
        [CmdletBinding()]
        param(
            $Excluding
        )

        $context = New-WhiskeyTestContext -ForTaskName 'PublishProGetUniversalPackage' `
                                        -ForBuildServer `
                                        -IgnoreExistingOutputDirectory `
                                        -IncludePSModule 'ProGetAutomation' `
                                        -ForBuildRoot $script:testRoot

        if( $script:credentialID )
        {
            $script:properties['CredentialID'] = $script:credentialID
            if( $script:credential )
            {
                Add-WhiskeyCredential -Context $context -ID $script:credentialID -Credential $script:credential
            }
        }

        if( $script:progetUrl )
        {
            $script:properties['Url'] = $script:progetUrl
        }

        if( $script:feedName )
        {
            $script:properties['FeedName'] = $script:feedName
        }

        if( $script:path )
        {
            $script:properties['Path'] = $script:path
        }

        if( $script:myTimeout )
        {
            $script:properties['Timeout'] = $script:myTimeout
        }

        if( $script:overwrite )
        {
            # String to ensure parsed to a boolean.
            $script:properties['Overwrite'] = 'true'
        }

        if( $Excluding )
        {
            $script:properties['Exclude'] = $Excluding
        }

        $mock = { }
        if( $script:noAccessToProGet )
        {
            $mock = {
                $eaArg = @{}
                if ($PesterBoundParameters.ContainsKey('ErrorAction'))
                {
                    $eaArg['ErrorAction'] = $PesterBoundParameters['ErrorAction']
                }
                Write-Error -Message 'Failed to upload package to some URL.' @eaArg
            }
        }
        elseif( $script:packageExists )
        {
            $mock = {
                if( -not $Force )
                {
                    $eaArg = @{}
                    if ($PesterBoundParameters.ContainsKey('ErrorAction'))
                    {
                        $eaArg['ErrorAction'] = $PesterBoundParameters['ErrorAction']
                    }
                    Write-Error -Message ('Package already exists!') @eaArg
                }
            }
        }

        Import-WhiskeyTestModule -Name 'ProGetAutomation'
        Mock -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -MockWith $mock

        $script:threwException = $false
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Parameter $script:properties -Name 'PublishProGetUniversalPackage'
        }
        catch
        {
            $script:threwException = $true
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'PublishProGetUniversalPackage' {
    BeforeEach {
        $script:myTimeout = $null
        $script:packageExists = $false
        $script:properties = @{ }

        Remove-Module -Name 'ProGetAutomation' -Force -ErrorAction Ignore

        $script:testRoot = New-WhiskeyTestRoot
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'publishes all upack files in output directory' {
        GivenUpackFile 'myfile1.upack'
        GivenUpackFile 'myfile2.upack'
        GivenProGetIsAt 'my url'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        WhenPublishingPackage
        ThenPackagePublished 'myfile1.upack'
        ThenPackagePublished 'myfile2.upack'
        ThenPackagePublishedAt 'my url'
        ThenPackagePublishedToFeed 'universalfeed'
        ThenPackagePublishedAs 'fubar'
        ThenPackagePublishedWithDefaultTimeout
    }

    It 'does not publish excluded files' {
        GivenUpackFile 'myfile1.upack'
        GivenUpackFile 'myfile2.upack'
        GivenProGetIsAt 'my url'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        WhenPublishingPackage -Excluding '*2.upack'
        ThenPackagePublished 'myfile1.upack'
        ThenPackageNotPublished 'myfile2.upack'
    }

    It 'publishes only included files' {
        GivenUpackFile 'myfile1.upack'
        GivenUpackFile 'myfile2.upack'
        GivenProGetIsAt 'my url'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        GivenPath '.output\myfile1.upack'
        WhenPublishingPackage
        ThenPackagePublished 'myfile1.upack'
        ThenPackageNotPublished 'myfile2.upack'
    }

    It 'does not publish excluded files that match an include wildcard' {
        GivenUpackFile 'myfile1.upack'
        GivenUpackFile 'myfile2.upack'
        GivenProGetIsAt 'my url'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        GivenPath '.output\*.upack'
        WhenPublishingPackage -Excluding '*1.upack'
        ThenPackageNotPublished 'myfile1.upack'
        ThenPackagePublished 'myfile2.upack'
    }

    It 'requires Credential ID' {
        GivenNoParameters
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFailed '\bCredentialID\b.*\bis\ a\ mandatory\b'
    }

    It 'requires Url property' {
        GivenNoParameters
        GivenCredential 'somecredential' -WithID 'fubar'
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFailed '\bUrl\b.*\bis\ a\ mandatory\b'
    }

    It 'requires FeedName properyt' {
        GivenNoParameters
        GivenCredential 'somecredential' -WithID 'fubar'
        GivenProGetIsAt 'some url'
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFailed '\bFeedName\b.*\bis\ a\ mandatory\b'
    }

    It 'requires at least one file to publish' {
        GivenProGetIsAt 'my url'
        GivenCredential 'fubatr' -WithID 'id'
        GivenUniversalFeed 'universal'
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFailed ([regex]::Escape('Found no packages to publish'))
    }

    It 'allows no files to publish' {
        GivenProGetIsAt 'my url'
        GivenCredential 'fubatr' -WithID 'id'
        GivenUniversalFeed 'universal'
        GivenProperty 'AllowMissingPackage' -Is 'true'
        WhenPublishingPackage
        ThenTaskCompleted
        ThenPackageNotPublished
    }

    It 'allows no included files to be published' {
        GivenProGetIsAt 'my url'
        GivenCredential 'fubatr' -WithID 'id'
        GivenUniversalFeed 'universal'
        GivenProperty 'AllowMissingPackage' -Is 'true'
        GivenProperty 'Path' -Is '*.fubar'
        WhenPublishingPackage
        ThenTaskCompleted
        ThenPackageNotPublished
    }

    It 'surfaces ProGet no permission to publish error' {
        GivenProGetIsAt 'my url'
        GivenUpackFile 'my.upack'
        GivenCredential 'fubatr' -WithID 'id'
        GivenUniversalFeed 'noaccess'
        GivenNoAccessToProGet
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFAiled 'Failed to upload'
    }

    It 'customizes upload timeout' {
        GivenUpackFile 'myfile1.upack'
        GivenUpackFile 'myfile2.upack'
        GivenProGetIsAt 'my url'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        GivenTimeout 600
        WhenPublishingPackage
        ThenPackagePublishedWithTimeout 600
    }

    It 'rejects package that already exists' {
        GivenUpackFile 'my.upack'
        GivenProGetIsAt 'proget.example.com'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        GivenPackageExists
        WhenPublishingPackage -ErrorAction SilentlyContinue
        ThenTaskFailed
    }

    It 'can overwrite existing package' {
        GivenUpackFile 'my.upack'
        GivenProGetIsAt 'proget.example.com'
        GivenCredential 'fubar' -WithID 'progetid'
        GivenUniversalFeed 'universalfeed'
        GivenPackageExists
        GivenOverwrite
        WhenPublishingPackage
        ThenPackagePublished 'my.upack'
        ThenPackageOverwritten
    }
}