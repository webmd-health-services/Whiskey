namespace Whiskey
{
    public sealed class RequiresPowerShellModuleAttribute : RequiresToolAttribute
    {
        public RequiresPowerShellModuleAttribute(string moduleName, string modulePathParameterName) : base(moduleName, modulePathParameterName)
        {
        }

        public bool SkipImport { get; set; }
    }
}
