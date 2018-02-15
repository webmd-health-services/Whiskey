namespace SemanticVersionTest.Comparer
{
    using SemVersion;

    using Xunit;

    public class GetHashCodeTests
    {
        [Fact]
        public void GetHashCodeSame()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo", "bar");
            SemanticVersion right = new SemanticVersion(1, 0, 0, "foo", "bar");

            VersionComparer comparer = new VersionComparer();

            Assert.Equal(comparer.GetHashCode(left), comparer.GetHashCode(right));
        }

        [Fact]
        public void GetHashCodeDifferent()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo", "bar");
            SemanticVersion right = new SemanticVersion(1, 0, 0, "foo", "baz");

            VersionComparer comparer = new VersionComparer();

            Assert.NotEqual(comparer.GetHashCode(left), comparer.GetHashCode(right));
        }
    }
}