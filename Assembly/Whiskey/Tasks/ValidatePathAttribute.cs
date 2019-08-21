using System;

namespace Whiskey.Tasks
{
    public sealed class ValidatePathAttribute : Attribute
    {
        public bool Mandatory { get; set; }

        public string PathType { get; set; }

        public bool MustExist { get; set; } = true;

        public bool AllowOutsideBuildRoot { get; set; }
    }
}
