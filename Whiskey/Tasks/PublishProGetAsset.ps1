
function Publish-WhiskeyProGetAsset
{
    [Whiskey.Task('PublishProGetAsset')]
    [Whiskey.RequiresPowerShellModule('ProGetAutomation',
                                        Version='3.*',
                                        VersionParameterName='ProGetAutomationVersion')]

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [CmdletBinding()]
    param(
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        [Whiskey.Context]$TaskContext,

        [String[]] $Path,

        [String[]] $AssetPath,

        [String] $AssetDirectory,

        [String] $CredentialID,

        [Alias('Uri')]
        [Uri] $Url,

        [String] $ContentType
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $documentationMsg = "See the PublishProGetAsset task documentation for details: https://github.com/webmd-health-services/Whiskey/wiki/PublishProGetAsset-Task"

    if (-not $Path)
    {
        $msg = """Path"" is a mandatory property. It must be a list of relative paths to the files/directories to " +
               "upload to ProGet. Paths are relative to the whiskey.yml file. ${documentationMsg}"
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $AssetDirectory)
    {
        $msg = """AssetDirectory"" is a mandatory property. It must be the root asset directory in ProGet where the item " +
               "will be uploaded to. ${documentationMsg}"
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $CredentialID)
    {
        $msg = """CredentialID"" is a mandatory property. It should be the ID of the Whiskey credential to use when " +
               "connecting to ProGet. Add the credential to your build with the `Add-WhiskeyCredential` function. ${documentationMsg}"
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $CredentialID -PropertyName 'CredentialID'

    $session = New-ProGetSession -Uri $Url -Credential $credential -WarningAction Ignore

    $optionalArgs = @{}

    if ($ContentType)
    {
        $optionalArgs['ContentType'] = $ContentType
    }

    $assetDirName = $AssetDirectory
    Write-WhiskeyInfo $Url

    foreach($pathItem in $Path)
    {
        if ($AssetPath -and (($AssetPath | Measure-Object).Count -eq ($Path | Measure-Object).Count)) {
            $name = @($AssetPath)[$Path.indexOf($pathItem)]
        }
        else
        {
            $msg = "There must be the same number of ""Path"" items as ""AssetPath"" items. For each asset ""Path"" " +
                   "there must be a respective ""AssetPath"" item which will be the item's path within the ProGet " +
                   "asset directory. ${documentationMsg}"
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }

        Write-WhiskeyInfo "  $($pathItem | Resolve-WhiskeyRelativePath) -> ${assetDirName}/${name}"
        Set-ProGetAsset -Session $session -DirectoryName $assetDirName -Path $name -FilePath $pathItem @optionalArgs
    }
}
