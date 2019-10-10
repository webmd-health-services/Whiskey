using System;

namespace Whiskey.Tasks
{
    public sealed class ValidatePathAttribute : Attribute
    {
        public bool Mandatory { get; set; }

        public string PathType { get; set; }

        public bool AllowNonexistent { get; set; }

        public bool AllowOutsideBuildRoot { get; set; }
    }
}
