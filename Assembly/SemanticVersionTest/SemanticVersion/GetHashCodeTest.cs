using System;
namespace SemanticVersionTest
{
    using SemVersion;

    using Xunit;

    public class GetHashCodeTests
    {
        [Fact]
        public void GetHashCodeEqual()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo", "bar");
            SemanticVersion right = new SemanticVersion(1, 0, 0, "foo", "bar");
            
            Assert.Equal(left.GetHashCode(), right.GetHashCode());
        }

        [Fact]
        public void GetHashCodeNotEqual()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo", "bar");
            SemanticVersion right = new SemanticVersion(2, 0, 0, "foo", "bar");

            Assert.NotEqual(left.GetHashCode(), right.GetHashCode());
        }

        [Fact]
        public void GetHashCodeNotEqualNoBuild()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo");
            SemanticVersion right = new SemanticVersion(2, 0, 0, "foo");

            Assert.NotEqual(left.GetHashCode(), right.GetHashCode());
        }

        [Fact]
        public void GetHashCodeNotEqualNoBuildNoPrerelease()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(2, 0, 0);

            Assert.NotEqual(left.GetHashCode(), right.GetHashCode());
        }
    }
}
