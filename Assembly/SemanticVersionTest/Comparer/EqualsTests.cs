namespace SemanticVersionTest.Comparer
{
    using System;

    using SemVersion;

    using Xunit;

    public class EqualsTests
    {
        [Fact]
        public void ReferenceEqualsSameObject()
        {
            SemanticVersion version = new SemanticVersion(1, 0, 0);
            
            VersionComparer comparer = new VersionComparer();

            Assert.True(comparer.Equals(version, version));
        }

        [Fact]
        public void ReferenceEqualsLeftNull()
        {
            SemanticVersion version = new SemanticVersion(1, 0, 0);

            VersionComparer comparer = new VersionComparer();

            Assert.False(comparer.Equals(null, version));
        }

        [Fact]
        public void ReferenceEqualsRightNull()
        {
            SemanticVersion version = new SemanticVersion(1, 0, 0);

            VersionComparer comparer = new VersionComparer();

            Assert.False(comparer.Equals(version, null));
        }
    }
}
