
$events = @{ }

$type = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType('Whiskey.TaskAttribute') } | Select-Object -First 1

if( -not $type )
{
    Add-Type -TypeDefinition @"

namespace Whiskey {

    public sealed class TaskAttribute : System.Attribute {

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

"@ -ErrorAction Ignore
}

$attr = New-Object -TypeName 'Whiskey.TaskAttribute' -ArgumentList 'Whiskey' -ErrorAction Ignore
if( -not ($attr | Get-Member 'SupportsClean') )
{
    Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
}

Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions'),(Join-Path -Path $PSScriptRoot -ChildPath 'Tasks') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }

$packageManagementModule = Get-Module -Name 'PackageManagement' -ListAvailable |
                                Where-Object { [Version]$_.Version -ge [Version]'1.1.7' }
if( -not $packageManagementModule )
{
    Write-Error -Message ('Whiskey depends on PackageManagement module version 1.1.7 or later. Please install it: Install-Module -Name ''PackageManagement'' -MinimumVersion ''1.1.7'' -Force.') -ErrorAction Stop
}

if( (Get-Module -Name 'PackageManagement') )
{
    Remove-Module -Name 'PackageManagement' -Force
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '.\PackageManagement\PackageManagement.psd1')

if( (Get-Module -Name 'PowerShellGet') )
{
    Remove-Module -Name 'PowerShellGet' -Force
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '.\PowerShellGet\PowerShellGet.psd1')
