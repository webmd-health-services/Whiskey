using System;
using System.Collections.Generic;
using System.Text;

namespace Whiskey
{
    [Flags]
    public enum Platform
    {
        Unknown = 0x0,
        Windows = 0x1,
        Linux = 0x2,
        MacOS = 0x4,
        All = Windows|Linux|MacOS
    }
}
