namespace SemVersion
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.Text;
    using System.Text.RegularExpressions;


    /// <summary>Reprensents a version object, compliant with the Semantic Version standard 2.0 (http://semver.org)</summary>
    public class SemanticVersion : IEquatable<SemanticVersion>, IComparable<SemanticVersion>
    {
        private static IComparer<SemanticVersion> comparer = new VersionComparer();

        private static readonly Regex VersionExpression = new Regex(@"^(?<major>[0-9]+|[*])((\.(?<minor>[0-9]+|[*]))(\.(?<patch>[0-9]+|[*]))?)?(\-(?<pre>[0-9A-Za-z\-\.]+|[*]))?(\+(?<build>[0-9A-Za-z\-\.]+|[*]))?$",
            RegexOptions.CultureInvariant | RegexOptions.ExplicitCapture);

        /// <summary>Initializese a new instance of the <see cref="SemanticVersion"/> class.</summary>
        /// <param name="major">The major version component.</param>
        /// <param name="minor">The minor version component.</param>
        /// <param name="patch">The patch version component.</param>
        /// <param name="prerelease">The pre-release version component.</param>
        /// <param name="build">The build version component.</param>
        public SemanticVersion(int? major, int? minor, int? patch, string prerelease = "", string build = "")
        {
            this.Major = major;
            this.Minor = minor;
            this.Patch = patch;
            this.Prerelease = prerelease;
            this.Build = build;
        }

        /// <summary>Gets the major version component.</summary>
        public int? Major { get; }

        /// <summary>Gets the minor version component.</summary>
        public int? Minor { get; }

        /// <summary>Gets the patch version component.</summary>
        public int? Patch { get; }

        /// <summary>Gets the pre-release version component.</summary>
        public string Prerelease { get; }

        /// <summary>Gets the build version component.</summary>
        public string Build { get; }

        public static bool operator ==(SemanticVersion left, SemanticVersion right)
        {
            return comparer.Compare(left, right) == 0;
        }

        public static bool operator !=(SemanticVersion left, SemanticVersion right)
        {
            return comparer.Compare(left, right) != 0;
        }

        public static bool operator <(SemanticVersion left, SemanticVersion right)
        {
            return comparer.Compare(left, right) < 0;
        }

        public static bool operator >(SemanticVersion left, SemanticVersion right)
        {
            return comparer.Compare(left, right) > 0;
        }

        public static bool operator <=(SemanticVersion left, SemanticVersion right)
        {
            return left == right || left < right;
        }

        public static bool operator >=(SemanticVersion left, SemanticVersion right)
        {
            return left == right || left > right;
        }

        /// <summary>Implicitly converts a string into a <see cref="SemanticVersion"/>.</summary>
        /// <param name="versionString">The string to convert.</param>
        /// <returns>The <see cref="SemanticVersion"/> object.</returns>

        public static implicit operator SemanticVersion(string versionString)
        {
            // ReSharper disable once ArrangeStaticMemberQualifier
            return SemanticVersion.Parse(versionString);
        }

        /// <summary>Explicitly converts a <see cref="System.Version"/> onject into a <see cref="SemanticVersion"/>.</summary>
        /// <param name="dotNetVersion">The version to convert.</param>
        /// <remarks>
        /// <para>This operator conversts a C# <see cref="System.Version"/> object into the corresponding <see cref="SemanticVersion"/> object.</para>
        /// <para>Note, that with a C# version the <see cref="System.Version.Build"/> property is identical to the <see cref="Patch"/> propertry on a semantic version compliant object.
        /// Whereas the <see cref="System.Version.Revision"/> property is equivalent to the <see cref="Build"/> property on a semantic version.
        /// The <see cref="Prerelease"/> property is never set, since the C# version object does not use such a notation.</para>
        /// </remarks>
        public static explicit operator SemanticVersion(Version dotNetVersion)
        {
            if (dotNetVersion == null)
            {
                throw new ArgumentNullException(nameof(dotNetVersion), "The version to convert is null.");
            }

            int major = dotNetVersion.Major;
            int minor = dotNetVersion.Minor;
            int patch = dotNetVersion.Build >= 0 ? dotNetVersion.Build : 0;
            string build = dotNetVersion.Revision >= 0 ? dotNetVersion.Revision.ToString() : string.Empty;

            return new SemanticVersion(major, minor, patch, string.Empty, build);
        }

        /// <summary>Change the comparer used to compare two <see cref="SemanticVersion"/> objects.</summary>
        /// <param name="versionComparer">An instance of the comparer to use in future comparisons.</param>
        public static void ChangeComparer(IComparer<SemanticVersion> versionComparer)
        {
            comparer = versionComparer;
        }

        /// <summary>Describes the first public api version.</summary>
        /// <returns>A <see cref="SemanticVersion"/> with version 1.0.0 as version number.</returns>
        public static SemanticVersion BaseVersion() => new SemanticVersion(1, 0, 0);

        /// <summary>Checks if a given string can be considered a valid <see cref="SemanticVersion"/>.</summary>
        /// <param name="inputString">The string to check for validity.</param>
        /// <returns>True, if the passed string is a valid <see cref="SemanticVersion"/>, otherwise false.</returns>
        public static bool IsVersion(string inputString) => VersionExpression.IsMatch(inputString);

        /// <summary>Parses the specified string to a semantic version.</summary>
        /// <param name="versionString">The version string.</param>
        /// <returns>A new <see cref="SemanticVersion"/> object that has the specified values.</returns>
        /// <exception cref="ArgumentNullException">Raised when the input string is null.</exception>
        /// <exception cref="ArgumentException">Raised when the the input string is in an invalid format.</exception>
        public static SemanticVersion Parse(string versionString)
        {
            if (versionString == null)
                throw new ArgumentNullException(nameof(versionString));

            SemanticVersion version;

            if (!TryParse(versionString, out version))
                throw new ArgumentException("The provided version string is invalid.", nameof(versionString));

            return version;
        }

        /// <summary>Tries to parse the specified string into a semantic version.</summary>
        /// <param name="versionString">The version string.</param>
        /// <param name="version">When the method returns, contains a SemVersion instance equivalent
        /// to the version string passed in, if the version string was valid, or <c>null</c> if the
        /// version string was not valid.</param>
        /// <returns><c>False</c> when a invalid version string is passed, otherwise <c>true</c>.</returns>
        public static bool TryParse(string versionString, out SemanticVersion version)
        {
            version = null;

            if (versionString == null)
                return false;

            var versionMatch = VersionExpression.Match(versionString);

            if (!versionMatch.Success)
                return false;

            var majorMatch = versionMatch.Groups["major"];
            var minorMatch = versionMatch.Groups["minor"];
            var patchMatch = versionMatch.Groups["patch"];
            var prereleaseMatch = versionMatch.Groups["pre"];
            var buildMatch = versionMatch.Groups["build"];

            // Parse the major component, if the match equals to "*",
            // we return a version that matches everty version.
            if (majorMatch.Value == "*")
            {
                version = new SemanticVersion(null, null, null);
                return true;
            }

            var major = int.Parse(majorMatch.Value, CultureInfo.InvariantCulture);

            // Parse the minor component, if the match equals to "*",
            // we return a version that matches every minor version
            // for a specified major version.
            if (!minorMatch.Success)
                return false;

            if (minorMatch.Value == "*")
            {
                version = new SemanticVersion(major, null, null);
                return true;
            }

            var minor = int.Parse(minorMatch.Value, CultureInfo.InvariantCulture);

            // Parse the patch component, if the match equals to "*",
            // we return a version that matches every patch version
            // for a specified major and minor version
            if (!patchMatch.Success)
                return false;

            if (patchMatch.Value == "*")
            {
                version = new SemanticVersion(major, minor, null);
                return true;
            }

            var patch = int.Parse(patchMatch.Value, CultureInfo.InvariantCulture);

            // Parse the patch and build components
            string prerelease = prereleaseMatch.Value != "*" ? prereleaseMatch.Value : string.Empty;
            string build = buildMatch.Value != "*" ? buildMatch.Value : string.Empty;

            version = new SemanticVersion(major, minor, patch, prerelease, build);
            return true;
        }

        /// <inheritdoc />
        public bool Equals(SemanticVersion other)
        {
            return comparer.Compare(this, other) == 0;
        }

        /// <inheritdoc />
        public int CompareTo(object obj)
        {
            return comparer.Compare(this, obj as SemanticVersion);
        }

        /// <inheritdoc />
        public int CompareTo(SemanticVersion other)
        {
            return comparer.Compare(this, other);
        }

        /// <inheritdoc />
        public override bool Equals(object obj)
        {
            return this.Equals(obj as SemanticVersion);
        }

        /// <inheritdoc />
        public override int GetHashCode()
        {
            unchecked
            {
                int hashCode = this.Major ?? 0;
                hashCode = (hashCode * 397) ^ this.Minor ?? 0;
                hashCode = (hashCode * 397) ^ this.Patch ?? 0;
                hashCode = (hashCode * 397) ^ (!string.IsNullOrWhiteSpace(this.Prerelease) ? StringComparer.OrdinalIgnoreCase.GetHashCode(this.Prerelease) : 0);
                hashCode = (hashCode * 397) ^ (!string.IsNullOrWhiteSpace(this.Build) ? StringComparer.OrdinalIgnoreCase.GetHashCode(this.Build) : 0);
                return hashCode;
            }
        }

        /// <inheritdoc />
        public override string ToString()
        {
            StringBuilder builder = new StringBuilder();

            if (this.Major.HasValue)
            {
                builder.Append($"{this.Major.Value}.");
            }
            else
            {
                return "*";
            }

            if (this.Minor.HasValue)
            {
                builder.Append($"{this.Minor.Value}.");
            }
            else
            {
                builder.Append("*");
                return builder.ToString();
            }

            if (this.Patch.HasValue)
            {
                builder.Append($"{this.Patch.Value}");
            }
            else
            {
                builder.Append("*");
                return builder.ToString();
            }

            builder.Append(string.IsNullOrWhiteSpace(this.Prerelease) ? string.Empty : $"-{this.Prerelease}");
            builder.Append(string.IsNullOrWhiteSpace(this.Build) ? string.Empty : $"+{this.Build}");

            return builder.ToString();
        }
    }
}
