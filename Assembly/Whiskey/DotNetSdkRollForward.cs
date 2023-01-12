namespace Whiskey
{
    public enum DotNetSdkRollForward
    {
        Disable = 0,
        Patch = 1,
        Feature = 2,
        Minor = 3,
        Major = 4,
        LatestPatch = 5,
        LatestFeature = 6,
        LatestMinor = 7,
        LatestMajor = 8
    }
}