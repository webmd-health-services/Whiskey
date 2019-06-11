using System;

namespace Whiskey.Tasks
{
    public sealed class ValidatePathAttribute : Attribute
    {
        public bool Mandatory { get; set; }

        public string PathType { get; set; }
    }
}
