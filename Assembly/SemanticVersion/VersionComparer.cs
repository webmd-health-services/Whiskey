namespace SemVersion
{
    using System.Collections.Generic;

    /// <summary>Compares two <see cref="SemanticVersion"/> ojects for equality.</summary>
    public sealed class VersionComparer : IEqualityComparer<SemanticVersion>, IComparer<SemanticVersion>
    {
        /// <inheritdoc/>
        public bool Equals(SemanticVersion left, SemanticVersion right)
        {
            return this.Compare(left, right) == 0;
        }

        /// <inheritdoc/>
        public int Compare(SemanticVersion left, SemanticVersion right)
        {
            if (ReferenceEquals(left, null))
            {
                return ReferenceEquals(right, null) ? 0 : -1;
            }

            if (ReferenceEquals(right, null))
            {
                return 1;
            }

            int majorComp = left.Major.CompareToBoxed(right.Major);
            if (majorComp != 0)
            {
                return majorComp;
            }

            int minorComp = left.Minor.CompareToBoxed(right.Minor);
            if (minorComp != 0)
            {
                return minorComp;
            }

            int patchComp = left.Patch.CompareToBoxed(right.Patch);
            if (patchComp != 0)
            {
                return patchComp;
            }

            int prereleaseComp = left.Prerelease.CompareComponent(right.Prerelease);
            if (prereleaseComp != 0)
            {
                return prereleaseComp;
            }

            return left.Build.CompareComponent(right.Build);
        }

        /// <inheritdoc/>
        public int GetHashCode(SemanticVersion obj)
        {
            return obj.GetHashCode();
        }
    }
}
