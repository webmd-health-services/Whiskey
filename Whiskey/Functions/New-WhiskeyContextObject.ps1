
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
                                    ReleaseName ='';
                                    BuildRoot = '';
                                    ConfigurationPath = '';
                                    ProGetSession = [pscustomobject]@{
                                                                        Credential = $null;
                                                                        PowerShellFeedUri = '';
                                                                     }
                                    BuildConfiguration = '';
                                    OutputDirectory = '';
                                    TaskName = '';
                                    TaskIndex = -1;
                                    PipelineName = '';
                                    TaskDefaults = @{ };
                                    Version = (New-WhiskeyVersionObject);
                                    Configuration = $null;
                                    DownloadRoot = '';
                                    ByBuildServer = $false;
                                    ByDeveloper = $true;
                                    Publish = $false;
                                    RunMode = 'Build';
                                }
    $context | Add-Member -MemberType ScriptMethod -Name 'ShouldClean' -Value { return $this.RunMode -eq 'Clean' }
    $context | Add-Member -MemberType ScriptMethod -Name 'ShouldInitialize' -Value { return $this.RunMode -eq 'Initialize' }

    return $context
}