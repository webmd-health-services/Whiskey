
Add-Type -TypeDefinition @"

namespace Whiskey {

    public sealed class TaskAttribute : System.Attribute {

        public TaskAttribute(string name)
        {
            Name = name;
        }

        public string Name { get; private set; }
    }
}

"@

Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }
