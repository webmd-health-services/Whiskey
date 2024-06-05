
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

    $message = "
    Build:
    - PublishProGetAsset:
        CredentialID: ProGetCredential
        Path:
        - ""path/to/file.txt""
        - ""path/to/anotherfile.txt""
        Url: http://proget.inedo.com/
        AssetPath:
        - ""path/to/exampleAsset""
        - ""path/toanother/file.txt""
        AssetDirectory: 'versions'
        "

    if (-not $Path)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Path Parameter to your whiskey.yml file:" + $message)
        return
    }

    if (-not $AssetDirectory)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory Parameter to your whiskey.yml file:" + $message)
        return
    }

    if (-not $CredentialID)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet. Add the credential with the `Add-WhiskeyCredential` function:" + $message)
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
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ("There must be the same number of `Path` items as `AssetPath` Items. Each asset must have both a `Path` and an `AssetPath` in the whiskey.yml file." + $message)
            return
        }

        Write-WhiskeyInfo "  $($pathItem | Resolve-WhiskeyRelativePath) -> ${assetDirName}/${name}"
        Set-ProGetAsset -Session $session -DirectoryName $assetDirName -Path $name -FilePath $pathItem @optionalArgs
    }
}
