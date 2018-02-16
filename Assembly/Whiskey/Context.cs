using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;

namespace Whiskey
{
    public sealed class Context
    {
        public Context()
        {
            ApiKeys = new Dictionary<string, string>();
            BuildMetadata = new BuildInfo();
            RunBy = RunBy.Developer;
            Configuration = new Dictionary<object, object>();
            Credentials = new Dictionary<string, object>();
            RunMode = RunMode.Build;
            TaskDefaults = new Dictionary<string, Dictionary<string, object>>();
            TaskIndex = -1;
            Variables = new Dictionary<string, object>();
            Version = new BuildVersion();
            Environment = "";
            PipelineName = "";
            TaskName = "";
        }

        public IDictionary ApiKeys { get; private set; }

        public DirectoryInfo BuildRoot { get; set; }

        public bool ByBuildServer { get { return this.RunBy == RunBy.BuildServer; } } 

        public bool ByDeveloper { get { return this.RunBy == RunBy.Developer; } }

        public BuildInfo BuildMetadata { get; set; }

        public IDictionary Configuration { get; set; }

        public FileInfo ConfigurationPath { get; set; }

        public IDictionary Credentials { get; private set; }

        public DirectoryInfo DownloadRoot { get; set; }

        public string Environment { get; set; }

        public DirectoryInfo OutputDirectory { get; set; }

        public string PipelineName { get; set; }

        public bool Publish { get; set; }

        public RunBy RunBy { get; set; }

        public RunMode RunMode { get; set; }

        public bool ShouldClean { get { return RunMode == RunMode.Clean; } }

        public bool ShouldInitialize { get { return RunMode == RunMode.Initialize; } }

        public DateTime StartedAt { get; set; }

        public string TaskName { get; set; }

        public int TaskIndex { get; set; }

        public IDictionary TaskDefaults { get; private set; }

        public DirectoryInfo Temp { get; set; }

        public IDictionary Variables { get; private set; }

        public BuildVersion Version { get; set; }


    }
}
