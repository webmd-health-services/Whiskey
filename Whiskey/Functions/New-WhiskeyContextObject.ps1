
function New-WhiskeyContextObject
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $context = [pscustomobject]@{
                                    ApiKeys = @{ };
                                    Environment = '';
                                    Credentials = @{ }
                                    ApplicationName = '';
                                    BuildRoot = '';
                                    ConfigurationPath = '';
                                    OutputDirectory = '';
                                    TaskName = '';
                                    TaskIndex = -1;
                                    PipelineName = '';
                                    TaskDefaults = @{ };
                                    Version = (New-WhiskeyVersionObject);
                                    Configuration = @{ };
                                    DownloadRoot = '';
                                    ByBuildServer = $false;
                                    ByDeveloper = $true;
                                    Publish = $false;
                                    RunMode = 'Build';
                                    BuildMetadata = (New-WhiskeyBuildMetadataObject);
                                }
    $context | Add-Member -MemberType ScriptMethod -Name 'ShouldClean' -Value { return $this.RunMode -eq 'Clean' }
    $context | Add-Member -MemberType ScriptMethod -Name 'ShouldInitialize' -Value { return $this.RunMode -eq 'Initialize' }

    return $context
}