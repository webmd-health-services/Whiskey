using SemVersion;

namespace Whiskey
{
    public sealed class BuildVersion
    {
        public BuildVersion()
        {
        }

        public SemanticVersion SemVer2 { get; set; }
        
        public SemanticVersion SemVer2NoBuildMetadata { get; set; }

        public System.Version Version { get; set; }

        public SemanticVersion SemVer1 { get; set; }
    }
}
