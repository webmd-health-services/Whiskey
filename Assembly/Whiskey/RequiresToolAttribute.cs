using System;

namespace Whiskey
{
    public class RequiresToolAttribute : Attribute
    {
        public RequiresToolAttribute(string toolName, string toolPathParameterName)
        {
            Name = toolName;
            PathParameterName = toolPathParameterName;
            VersionParameterName = "Version";
        }

        public string Name { get; private set; }

        public string PathParameterName { get; set; }

        public string Version { get; set; }

        public string VersionParameterName { get; set; }
    }
}
