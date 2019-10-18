using System;

namespace Whiskey
{
    public class RequiresToolAttribute : Attribute
    {
        public RequiresToolAttribute(string toolName)
        {
            Name = toolName;
            VersionParameterName = "Version";
        }

        public bool AddToPath { get; set; }

        public string Name { get; private set; }

        public string PathParameterName { get; set; }

        public string Version { get; set; }

        public string VersionParameterName { get; set; }
    }
}
