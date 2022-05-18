
namespace Whiskey
{
    public sealed class RequiresNuGetPackageAttribute : RequiresToolAttribute
    {
        public RequiresNuGetPackageAttribute(string name) : base(name, "NuGet")
        {
        }
    }
}
