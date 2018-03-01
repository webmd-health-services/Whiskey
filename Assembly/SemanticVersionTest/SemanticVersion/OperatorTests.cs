namespace SemanticVersionTest
{
    using SemVersion;

    using Xunit;

    public class OperatorTests
    {
        [Fact]
        public void EqualsSameVersion()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);

            Assert.True(left == right);
        }

        [Fact]
        public void NotEquals()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(2, 0, 0);

            Assert.True(left != right);

        }

        [Fact]
        public void Greater()
        {
            SemanticVersion left = new SemanticVersion(2, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);

            Assert.True(left > right);
        }

        [Fact]
        public void Less()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(2, 0, 0);

            Assert.True(left < right);
        }

        [Fact]
        public void GreaterEquals()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);


            SemanticVersion left1 = new SemanticVersion(2, 0, 0);
            SemanticVersion right1 = new SemanticVersion(1, 0, 0);

            Assert.True(left >= right);
            Assert.True(left1 >= right1);
        }

        [Fact]
        public void LessEquals()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);


            SemanticVersion left1 = new SemanticVersion(1, 0, 0);
            SemanticVersion right1 = new SemanticVersion(2, 0, 0);

            Assert.True(left <= right);
            Assert.True(left1 <= right1);

        }
    }
}