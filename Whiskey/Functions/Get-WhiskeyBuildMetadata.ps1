
function Get-WhiskeyBuildMetadata
{
    <#
    SYNOPSIS
    Gets metadata about the current build.

    .DESCRIPTION
    The `Get-WhiskeyBuildMetadata` function gets information about the current build. It is exists to hide what CI server the current build is running under. It returns an object with the following properties:

    * `ScmUri`: the URI to the source control repository used in this build.
    * `BuildNumber`: the build number of the current build. This is the incrementing number most CI servers used to identify a build of a specific job.
    * `BuildID`: this unique identifier for this build. Usually, this is used by CI servers to distinguish this build from builds across all jobs.
    * `ScmCommitID`: the full ID of the commit that is being built.
    * `ScmBranch`: the branch name of the commit that is being built.
    * `JobName`: the name of the job that is running the build.
    * `BuildUri`: the URI to this build's results.

    #>
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'

    function Get-EnvironmentVariable
    {
        param(
            $Name
        )

        Get-Item -Path ('env:{0}' -f $Name) | Select-Object -ExpandProperty 'Value'
    }

    $buildNumber = 
        $buildID = 
        $buildUri = 
        $jobName = 
        $scmUri = 
        $scmID = 
        $buildServerName = 
        $scmBranch = ''

    if( (Test-Path -Path 'env:JENKINS_URL') )
    {
        $buildNumber = Get-EnvironmentVariable 'BUILD_NUMBER'
        $buildID = Get-EnvironmentVariable 'BUILD_TAG'
        $buildUri = Get-EnvironmentVariable 'BUILD_URL'
        $jobName = Get-EnvironmentVariable 'JOB_NAME'
        $scmUri = Get-EnvironmentVariable 'GIT_URL'
        $scmID = Get-EnvironmentVariable 'GIT_COMMIT'
        $scmBranch = Get-EnvironmentVariable 'GIT_BRANCH'
        $scmBranch = $scmBranch -replace '^origin/',''
        $buildServerName = 'Jenkins'
    }

    $info = [pscustomobject]@{
                                BuildNumber = $buildNumber;
                                BuildID = $buildID;
                                BuildServerName = $buildServerName;
                                BuildUri = $buildUri;
                                JobName = $jobName;
                                ScmBranch = $scmBranch;
                                ScmCommitID = $scmID;
                                ScmUri = $scmUri;
                            }
    $info |
        Add-Member -MemberType ScriptProperty -Name 'IsJenkins' -Value { return $this.BuildServerName -eq 'Jenkins' } -PassThru |
        Add-Member -MemberType ScriptProperty -Name 'IsDeveloper' -Value { return $this.BuildServerName -eq '' } -PassThru |
        Add-Member -MemberType ScriptProperty -Name 'IsBuildServer' -Value { return -not $this.IsDeveloper } -PassThru 
}

