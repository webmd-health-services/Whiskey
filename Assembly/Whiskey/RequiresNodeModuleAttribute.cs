
namespace Whiskey
{
    public sealed class RequiresNodeModuleAttribute : RequiresToolAttribute
    {
        public RequiresNodeModuleAttribute(string name) : base(name, "NodeModule")
        {
        }
    }
}
