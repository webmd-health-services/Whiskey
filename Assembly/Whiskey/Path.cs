using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Whiskey
{
    public sealed class Path
    {
        // ReSharper disable once StringLiteralTypo
        [DllImport("shlwapi.dll", CharSet = CharSet.Auto)]
        // ReSharper disable once UnusedMember.Global
        public static extern bool PathRelativePathTo(
            [Out] StringBuilder pszPath,
            [In] string pszFrom,
            [In] FileAttributes dwAttrFrom,
            [In] string pszTo,
            [In] FileAttributes dwAttrTo
        );
    }
}
