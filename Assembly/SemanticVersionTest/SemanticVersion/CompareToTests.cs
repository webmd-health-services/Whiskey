namespace SemanticVersionTest
{
    using SemVersion;
    using System;
    using Xunit;

    public class CompareToTests
    {
        [Fact]
        public void CompareToInvaildObject()
        {
            SemanticVersion version = new SemanticVersion(1,0,0);

            Assert.Equal(1,version.CompareTo(new object()));
        }

        [Fact]
        public void CompareToValidObject()
        {
            SemanticVersion version = new SemanticVersion(1,0,0);
            SemanticVersion other = new SemanticVersion(1,0,0);
            Assert.Equal(0, version.CompareTo((object)other));
        }
        
        [Fact]
        public void CompareTo()
        {
            SemanticVersion version = new SemanticVersion(1, 0, 0);

            Assert.Equal(0, version.CompareTo(version));
        }

        [Fact]
        public void CompareToNull()
        {
            SemanticVersion version = new SemanticVersion(1, 0, 0);

            Assert.Equal(1, version.CompareTo(null));
        }

        [Fact]
        public void CompareToMinor()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 1, 0);

            Assert.Equal(-1, left.CompareTo(right));
        }

        [Fact]
        public void CompareToPatch()
        {
            SemanticVersion left = new SemanticVersion(1, 1, 0);
            SemanticVersion right = new SemanticVersion(1, 1, 1);

            Assert.Equal(-1, left.CompareTo(right));
        }

        [Fact]
        public void CompareToBuildRightEmpty()
        {
            SemanticVersion left = new SemanticVersion(1, 1, 0, build:"abc");
            SemanticVersion right = new SemanticVersion(1, 1, 0);

            Assert.Equal(-1, left.CompareTo(right));
        }

        [Fact]
        public void CompareToBuildLeftEmpty()
        {
            SemanticVersion left = new SemanticVersion(1, 1, 0);
            SemanticVersion right = new SemanticVersion(1, 1, 0, build: "abc");

            Assert.Equal(1, left.CompareTo(right));
        }

        [Fact]
        public void Sorted()
        {
            var list = new[]
            {
                new SemanticVersion(2,1,3),
                new SemanticVersion(1,2,3),
                new SemanticVersion(1,1,3),
                new SemanticVersion(4,5,6,"alpha.20"),
                new SemanticVersion(4,5,6,"alpha.2"),
                new SemanticVersion(4,5,6,"alpha.10"),
                new SemanticVersion(4,5,6),
                new SemanticVersion(4,5,6,"alpha.1"),
                new SemanticVersion(4,5,6,"alpha"),
                new SemanticVersion(4,5,6,"beta")
            };

            Array.Sort(list);

            Assert.Equal(new SemanticVersion(1, 1, 3), list[0]);
            Assert.Equal(new SemanticVersion(1, 2, 3), list[1]);
            Assert.Equal(new SemanticVersion(2, 1, 3), list[2]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "alpha"), list[3]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "alpha.1"), list[4]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "alpha.2"), list[5]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "alpha.10"), list[6]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "alpha.20"), list[7]);
            Assert.Equal(new SemanticVersion(4, 5, 6, "beta"), list[8]);
            Assert.Equal(new SemanticVersion(4, 5, 6), list[9]);
        }
    }
}
