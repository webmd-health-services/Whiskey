using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace SemanticVersionTest
{
    using SemVersion;

    using Xunit;

    public class EqualityTests
    {
        [Fact]
        public void EqualsSameVersion()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 0);

            Assert.True(left.Equals(right));
        }

        [Fact]
        public void EqualsObject()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            object right = new SemanticVersion(1, 0, 0);

            Assert.True(left.Equals(right));
        }

        [Fact]
        public void EqualsNull()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);

            Assert.False(left.Equals((object)null));
        }

        [Fact]
        public void NotEqualsNull()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);

            Assert.False(left.Equals(null));
        }

        [Fact]

        public void NotEqualsMajor()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(2, 0, 0);

            Assert.False(left.Equals(right));

        }

        [Fact]

        public void NotEqualsMinor()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 1, 0);

            Assert.False(left.Equals(right));
        }

        [Fact]

        public void NotEqualsPatch()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0);
            SemanticVersion right = new SemanticVersion(1, 0, 1);

            Assert.False(left.Equals(right));
        }

        [Fact]
        public void NotEqualsPrerelease()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo");
            SemanticVersion right = new SemanticVersion(1, 0, 0, "bar");

            Assert.False(left.Equals(right));
        }

        [Fact]

        public void NotEqualsBuild()
        {
            SemanticVersion left = new SemanticVersion(1, 0, 0, "foo", "bar");
            SemanticVersion right = new SemanticVersion(1, 0, 0, "foo", "baz");

            Assert.False(left.Equals(right));
        }
    }
}
