
function New-WhiskeyBuildMetadataObject
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'

    $info = [pscustomobject]@{
                                BuildNumber = '';
                                BuildID = '';
                                BuildServerName = '';
                                BuildUri = '';
                                JobName = '';
                                ScmBranch = '';
                                ScmCommitID = '';
                                ScmUri = '';
                            }
    $info |
        Add-Member -MemberType ScriptProperty -Name 'IsJenkins' -Value { return $this.BuildServerName -eq 'Jenkins' } -PassThru |
        Add-Member -MemberType ScriptProperty -Name 'IsDeveloper' -Value { return $this.BuildServerName -eq '' } -PassThru |
        Add-Member -MemberType ScriptProperty -Name 'IsBuildServer' -Value { return -not $this.IsDeveloper } -PassThru 
}
