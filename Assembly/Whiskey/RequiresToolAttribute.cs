using System;

namespace Whiskey
{
    public class RequiresToolAttribute : Attribute
    {
        public RequiresToolAttribute(string toolName)
        {
            Name = toolName;
            var nameStartsAt = toolName.IndexOf("::");
            if( nameStartsAt >= 0 )
            {
                ProviderName = toolName.Substring(0, nameStartsAt);
                Name = toolName.Substring(nameStartsAt + 2);
            }
            VersionParameterName = "Version";
        }

        public RequiresToolAttribute(string toolName, string providerName) : this(toolName)
        {
            ProviderName = providerName;
        }

        public bool AddToPath { get; set; }

        public string Name { get; private set; }

        public string PathParameterName { get; set; }

        public string ProviderName { get; set; }

        public string Version { get; set; }

        public string VersionParameterName { get; set; }
    }
}
