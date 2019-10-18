
namespace Whiskey
{
    public sealed class RequiresPowerShellModuleAttribute : RequiresToolAttribute
    {
        public RequiresPowerShellModuleAttribute(string moduleName) : base(moduleName)
        {
        }

        public string ModuleInfoParameterName { get; set; }

        public bool SkipImport { get; set; }
    }
}
