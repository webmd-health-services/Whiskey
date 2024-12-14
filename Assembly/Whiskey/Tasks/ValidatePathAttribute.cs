using System;

namespace Whiskey.Tasks
{
    public sealed class ValidatePathAttribute : Attribute
    {
        public bool AllowNonexistent { get; set; }

        [Obsolete]
        public bool AllowOutsideBuildRoot { get; set; }

        public bool Create { get; set; }

        public string GlobExcludeParameter { get; set; }

        public bool Mandatory { get; set; }

        public string PathType { get; set; }

        public bool UseGlob { get; set; }
    }
}
