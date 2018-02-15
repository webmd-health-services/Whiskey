using System;

namespace Whiskey
{
    public sealed class TaskAttribute : Attribute
    {
        public TaskAttribute(string name)
        {
            Name = name;
        }

        public string CommandName { get; set; }

        public string Name { get; private set; }

        public bool SupportsClean { get; set; }

        public bool SupportsInitialize { get; set; }
    }
}