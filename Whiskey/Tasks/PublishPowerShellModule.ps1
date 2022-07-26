
function Publish-WhiskeyPowerShellModule
{
    [Whiskey.Task('PublishPowerShellModule')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
        [String] $Path,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String] $ModuleManifestPath,

        [String] $RepositoryName,

        [Alias('RepositoryUri')]
        [String] $RepositoryLocation,

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
        [String] $CredentialID,

        [String] $ApiKeyID
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $manifestPath = '{0}\{1}.psd1' -f $Path,($Path | Split-Path -Leaf)
    if( $ModuleManifestPath )
    {
        $manifestPath = $ModuleManifestPath
    }

    if( -not (Test-Path -Path $manifestPath -PathType Leaf) )
    {
        $msg = "Module manifest path ""$($manifestPath)"" either does not exist or is a directory."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Ignore -WarningAction Ignore
    if( $TaskContext.Version.SemVer2.Prerelease -and `
        (-not ($manifest.PrivateData) -or `
        -not ($manifest.PrivateData | Get-Member 'Keys') -or `
        -not $manifest.PrivateData.ContainsKey('PSData') -or `
        -not ($manifest.PrivateData['PSData'] | Get-Member 'Keys') -or `
        -not $manifest.PrivateData['PSData'].ContainsKey('Prerelease')) )
    {
        $msg = "Module manifest ""$($manifest.Path)"" is missing a ""Prerelease"" property. Please make sure the " +
               "manifest's PrivateData hashtable contains a PSData key with a Prerelease property, e.g.

    @{
        PrivateData = @{
            PSData = @{
                Prerelease = '';
            }
        }
    }
"
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }

    $manifestContent = Get-Content $manifest.Path
    $versionString = 'ModuleVersion = ''{0}.{1}.{2}''' -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )
    $manifestContent = $manifestContent -replace 'ModuleVersion\s*=\s*(''|")[^''"]*(''|")', $versionString
    $prereleaseString = 'Prerelease = ''{0}''' -f $TaskContext.Version.SemVer2.Prerelease  
    $manifestContent = $manifestContent -replace 'Prerelease\s*=\s*(''|")[^''"]*(''|")', $prereleaseString
    $manifestContent | Set-Content $manifest.Path
    Publish-WhiskeyPSObject -Context $TaskContext -ModuleInfo $manifest -RepositoryName $RepositoryName `
        -RepositoryLocation $RepositoryLocation -CredentialID $CredentialID -ApiKeyId $ApiKeyID
}
