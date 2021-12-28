
function Publish-WhiskeyPowerShellScript
{
    [Whiskey.Task('PublishPowerShellScript')]
    [Whiskey.RequiresPowerShellModule('PackageManagement', Version='1.4.7', VersionParameterName='PackageManagementVersion')]
    [Whiskey.RequiresPowerShellModule('PowerShellGet', Version='2.2.5', VersionParameterName='PowerShellGetVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String] $Path,

        [String] $RepositoryName,

        [Alias('RepositoryUri')]
        [String] $RepositoryLocation,

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
        [String] $CredentialID,

        [String] $ApiKeyID
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not (Test-Path -Path $Path -PathType Leaf) )
    {
        $msg = "Script manifest path ""$($Path)"" either does not exist or is a directory."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    try 
    {
        $scriptManifest = Test-ScriptFileInfo -Path $Path
    }
    catch 
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $_
        return
    }
    $manifestContent = Get-Content $scriptManifest.Path
    $versionString = ".VERSION $($TaskContext.Version.SemVer2NoBuildMetadata)"
    $manifestContent = $manifestContent -replace '.VERSION\s[^''"]*', $versionString
    $manifestContent | Set-Content $scriptManifest.Path
    Publish-WhiskeyPSObject -Context $TaskContext -ScriptInfo $scriptManifest -RepositoryName $RepositoryName `
        -RepositoryLocation $RepositoryLocation -CredentialID $CredentialID -ApiKeyId $ApiKeyID
}