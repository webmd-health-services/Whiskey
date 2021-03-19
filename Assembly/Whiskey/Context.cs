using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security;

namespace Whiskey
{
    public sealed class Context
    {
        public Context()
        {
            ApiKeys = new Dictionary<string, SecureString>();
            BuildMetadata = new BuildInfo();
            RunBy = RunBy.Developer;
            Configuration = new Dictionary<object, object>();
            Credentials = new Dictionary<string, object>();
            RunMode = RunMode.Build;
            TaskDefaults = new Dictionary<string, IDictionary>();
            TaskIndex = -1;
            Variables = new Dictionary<string, object>();
            Version = new BuildVersion();
            Environment = "";
            PipelineName = "";
            TaskName = "";
            TaskPaths = new List<FileInfo>();
            MSBuildConfiguration = "";
            Events = new Hashtable(StringComparer.InvariantCultureIgnoreCase);
            BuildStopwatch = new Stopwatch();
            TaskStopwatch = new Stopwatch();
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

        public Hashtable Events { get; private set; }

        public string MSBuildConfiguration { get; set; }

        public DirectoryInfo OutputDirectory { get; set; }

        public string PipelineName { get; set; }

        public bool Publish { get; set; }

        public RunBy RunBy { get; set; }

        public RunMode RunMode { get; set; }

        public bool ShouldClean { get { return RunMode == RunMode.Clean; } }

        public bool ShouldInitialize { get { return RunMode == RunMode.Initialize; } }

        public DateTime StartedAt { get; private set; }

        public Stopwatch BuildStopwatch { get; private set; }

        public string TaskName { get; private set; }

        public int TaskIndex { get; set; }

        public IDictionary TaskDefaults { get; private set; }

        public IList<FileInfo> TaskPaths { get; private set; }

        public Stopwatch TaskStopwatch { get; private set; }

        public DirectoryInfo Temp { get; set; }

        public IDictionary Variables { get; private set; }

        public BuildVersion Version { get; set; }

        public void StartBuild()
        {
            if( BuildStopwatch.IsRunning )
            {
                return;
            }

            StartedAt = DateTime.Now;
            BuildStopwatch.Reset();
            BuildStopwatch.Start();
        }

        public void StartTask(string name)
        {
            if( TaskStopwatch.IsRunning )
            {
                return;
            }

            TaskStopwatch.Reset();
            TaskStopwatch.Start();
            TaskName = name;
        }

        public void StopBuild()
        {
            BuildStopwatch.Stop();
        }

        public void StopTask()
        {
            TaskStopwatch.Stop();
            TaskName = String.Empty;
        }
    }
}
