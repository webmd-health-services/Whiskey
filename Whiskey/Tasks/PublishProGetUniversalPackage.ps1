
function Publish-WhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    [Whiskey.Task('PublishProGetUniversalPackage')]
    [Whiskey.RequiresPowerShellModule('ProGetAutomation',
                                      Version='3.*',
                                      VersionParameterName='ProGetAutomationVersion')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(AllowNonexistent, PathType='File')]
        [String[]]$Path,

        [Alias('Uri')]
        [Uri] $Url
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $exampleTask = 'Publish:
        - PublishProGetUniversalPackage:
            CredentialID: ProGetCredential
            Url: https://proget.example.com
            FeedName: UniversalPackages'


    if( -not $TaskParameter['CredentialID'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet:

        $exampleTask

        Use the `Add-WhiskeyCredential` function to add credentials to the build."
        return
    }

    if (-not $Url)
    {
        $msg = 'Url is a mandatory property. It should be the URL to the ProGet instance where you want to publish ' +
               "your package:

    $exampleTask
               "
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if( -not $TaskParameter['FeedName'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "FeedName is a mandatory property. It should be the name of the universal feed in ProGet where you want to publish your package:

        $exampleTask
        "
        return
    }

    $credential =
        Get-WhiskeyCredential -Context $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'

    $session = New-ProGetSession -Uri $Url -Credential $credential -WarningAction Ignore

    if( -not $Path )
    {
        $Path =
            Join-Path -Path $TaskContext.OutputDirectory -ChildPath '*.upack' |
            Resolve-WhiskeyTaskPath -TaskContext $TaskContext -AllowNonexistent -PropertyName 'Path' -PathType 'File'
    }

    $allowMissingPackages = $false
    if( $TaskParameter.ContainsKey('AllowMissingPackage') )
    {
        $allowMissingPackages = $TaskParameter['AllowMissingPackage'] | ConvertFrom-WhiskeyYamlScalar
    }

    $packages =
        $Path |
        Where-Object {
            if( -not $TaskParameter.ContainsKey('Exclude') )
            {
                return $true
            }

            foreach( $exclusion in $TaskParameter['Exclude'] )
            {
                if( $_ -like $exclusion )
                {
                    return $false
                }
            }

            return $true
        }


    if( $allowMissingPackages -and -not $packages )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('There are no packages to publish.')
        return
    }

    if( -not $packages )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyDescription '' -Message ('Found no packages to publish. By default, the PublishProGetUniversalPackage task publishes all files with a .upack extension in the output directory. Check your whiskey.yml file to make sure you''re running the `ProGetUniversalPackage` task before this task (or some other task that creates universal ProGet packages). To publish other .upack files, set this task''s `Path` property to the path to those files. If you don''t want your build to fail when there are missing packages, then set this task''s `AllowMissingPackage` property to `true`.' -f $TaskContext.OutputDirectory)
        return
    }

    $feedName = $TaskParameter['FeedName']

    $optionalParam = @{ }
    if( $TaskParameter['Timeout'] )
    {
        $optionalParam['Timeout'] = $TaskParameter['Timeout']
    }
    if( $TaskParameter['Overwrite'] )
    {
        $optionalParam['Force'] = $TaskParameter['Overwrite'] | ConvertFrom-WhiskeyYamlScalar
    }

    Write-WhiskeyInfo -Context $TaskContext -Message "${Url}  ${feedName}"
    foreach( $package in $packages )
    {
        Write-WhiskeyInfo -Context $TaskContext -Message "  $($package | Resolve-WhiskeyRelativePath)"
        Publish-ProGetUniversalPackage -Session $session -FeedName $feedName -PackagePath $package @optionalParam -ErrorAction Stop
    }
}
