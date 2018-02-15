namespace SemanticVersionTest.Comparer
{
    using SemVersion;

    using Xunit;

    public class CompareTests
    {
        [Fact]
        public void Compare()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);

            VersionComparer comparer = new VersionComparer();

            Assert.Equal(0,comparer.Compare(left, right));
        }

        [Fact]
        public void CompareLeftNull()
        {
            SemanticVersion right = new SemanticVersion(1, 0, 0);

            VersionComparer comparer = new VersionComparer();

            Assert.Equal(-1, comparer.Compare(null, right));
        }

        [Fact]
        public void CompareRightNull()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);

            VersionComparer comparer = new VersionComparer();

            Assert.Equal(1, comparer.Compare(left, null));
        }

        [Fact]
        public void CompareBothNull()
        {
            VersionComparer comparer = new VersionComparer();

            Assert.Equal(0, comparer.Compare(null, null));
        }
    }
}