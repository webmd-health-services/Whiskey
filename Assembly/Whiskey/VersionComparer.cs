using System;
using System.Collections.Generic;
using SemVersion;

namespace Whiskey
{

    /// <summary>Compares two <see cref="SemanticVersion"/> ojects for equality.</summary>
    public sealed class VersionComparer : IEqualityComparer<SemanticVersion>, IComparer<SemanticVersion>
    {
        private static int CompareToBoxed(int? left, int? right)
        {
            if (!left.HasValue)
            {
                return !right.HasValue ? 0 : -1;
            }
            return !right.HasValue ? 1 : left.Value.CompareTo(right.Value);
        }
        
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

            int majorComp = CompareToBoxed(left.Major, right.Major);
            if (majorComp != 0)
            {
                return majorComp;
            }

            int minorComp = CompareToBoxed(left.Minor, right.Minor);
            if (minorComp != 0)
            {
                return minorComp;
            }

            int patchComp = CompareToBoxed(left.Patch, right.Patch);
            if (patchComp != 0)
            {
                return patchComp;
            }

            return CompareComponent(left.Prerelease, right.Prerelease);
        }

        /// <inheritdoc/>
        public int GetHashCode(SemanticVersion obj)
        {
            return obj.GetHashCode();
        }

        private static int CompareComponent(string component, string other)
        {
            bool componentEmpty = string.IsNullOrWhiteSpace(component);
            bool otherEmtpy = string.IsNullOrWhiteSpace(other);

            if ((componentEmpty && otherEmtpy) || (component == "*" && other == "*"))
            {
                return 0;
            }

            if (componentEmpty || component == "*")
            {
                return 1;
            }

            if (otherEmtpy || other == "*")
            {
                return -1;
            }

            string[] componentParts = component.Split(new[] { '.' }, StringSplitOptions.RemoveEmptyEntries);
            string[] otherParts = other.Split(new[] { '.' }, StringSplitOptions.RemoveEmptyEntries);

            for (int i = 0; i < Math.Min(componentParts.Length, otherParts.Length); i++)
            {
                string componentChar = componentParts[i];
                string otherChar = otherParts[i];

                int componentNumVal, otherNumVal;
                bool componentIsNum = int.TryParse(componentChar, out componentNumVal);
                bool otherIsNum = int.TryParse(otherChar, out otherNumVal);

                if (componentIsNum && otherIsNum)
                {
                    if (componentNumVal.CompareTo(otherNumVal) == 0)
                    {
                        continue;
                    }
                    return componentNumVal.CompareTo(otherNumVal);
                }
                else
                {
                    if (componentIsNum)
                    {
                        return -1;
                    }

                    if (otherIsNum)
                    {
                        return 1;
                    }

                    int comp = string.Compare(componentChar, otherChar, StringComparison.OrdinalIgnoreCase);
                    if (comp != 0)
                    {
                        return comp;
                    }
                }
            }

            return componentParts.Length.CompareTo(otherParts.Length);
        }
    }
}
