﻿using System;

namespace Whiskey
{
    public sealed class TaskAttribute : Attribute
    {
        public TaskAttribute(string name)
        {
            Name = name;
            Platform = Platform.All;
        }

        public string CommandName { get; set; }

        public string Name { get; private set; }

        public bool Obsolete { get; set; }

        public string ObsoleteMessage { get; set; }

        public Platform Platform { get; set; }

        public bool SupportsClean { get; set; }

        public bool SupportsInitialize { get; set; }
    }
}