using System.Collections.Generic;
using System.IO;

namespace Whiskey
{
    public sealed class Context
    {
        public Context()
        {
            ApiKeys = new Dictionary<string, string>();
            RunBy = RunBy.Developer;
            BuildMetadata = new BuildInfo();
            Configuration = new Dictionary<object, object>();
            Credentials = new Dictionary<string, object>();
            RunMode = RunMode.Build;
            TaskDefaults = new Dictionary<string, Dictionary<string, object>>();
            TaskIndex = -1;
            Version = new BuildVersion();
        }

        public Dictionary<string,string> ApiKeys { get; private set; }

        public DirectoryInfo BuildRoot { get; set; }

        public bool ByBuildServer { get { return this.RunBy == RunBy.BuildServer; } } 

        public bool ByDeveloper { get { return this.RunBy == RunBy.Developer; } }

        public BuildInfo BuildMetadata { get; private set; }

        public Dictionary<object,object> Configuration { get; set; }

        public FileInfo ConfigurationPath { get; set; }

        public Dictionary<string,object> Credentials { get; private set; }

        public DirectoryInfo DownloadRoot { get; set; }

        public string Environment { get; set; }

        public DirectoryInfo OutputDirectory { get; set; }

        public string PipelineName { get; set; }

        public bool Publish { get; set; }

        public RunBy RunBy { get; set; }

        public RunMode RunMode { get; set; }

        public string TaskName { get; set; }

        public int TaskIndex { get; set; }

        public Dictionary<string,Dictionary<string,object>> TaskDefaults { get; private set; }

        public DirectoryInfo Temp { get; set; }

        public Dictionary<string,string> Variables { get; private set; }

        public BuildVersion Version { get; set; }
    }
}
