using System;

namespace Whiskey
{
    public sealed class BuildInfo
    {
        public BuildInfo()
        {
            BuildID = "";
            JobName = "";
            ScmBranch = "";
            ScmCommitID = "";
            ScmSourceBranch = "";
            ScmSourceCommitID = "";
        }

        public int BuildNumber { get; set; }

        public string BuildID { get; set; }

        public BuildServer BuildServer { get; set; }

        public Uri BuildUri { get; set; }

        public bool IsAppVeyor { get { return BuildServer == BuildServer.AppVeyor; } }

        public bool IsDeveloper { get { return BuildServer == BuildServer.None; } }

        public bool IsBuildServer { get { return !IsDeveloper; } }

        public bool IsJenkins { get { return BuildServer == BuildServer.Jenkins; } }

        public bool IsPullRequest { get; set; }

        public bool IsTeamCity { get { return BuildServer == BuildServer.TeamCity; } }

        public string JobName { get; set; }

        public Uri JobUri { get; set; }

        public string ScmBranch { get; set; }

        public string ScmCommitID { get; set; }

        public string ScmSourceBranch { get; set; }

        public string ScmSourceCommitID { get; set; }

        public Uri ScmUri { get; set; }
    }
}
