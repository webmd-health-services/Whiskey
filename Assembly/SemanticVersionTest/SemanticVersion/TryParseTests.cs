namespace SemanticVersionTest
{
    using SemVersion;

    using Xunit;

    public class TryParseTests
    {
        [Fact]
        public void TryParseReturnsVersion()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.2.3", out version);

            Assert.True(result);
            Assert.Equal(new SemanticVersion(1, 2, 3), version);
        }

        [Fact]
        public void TryParseNullReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse(null, out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseEmptyStringReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse(string.Empty, out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseInvalidStringReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("invalid-version", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseMissingMinorReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseMissingPatchReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.2", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseMissingPatchWithPrereleaseReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.2-alpha", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact]
        public void TryParseMajorWildcard()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("*", out version);

            Assert.True(result);
            Assert.Null(version.Major);
            Assert.Null(version.Minor);
            Assert.Null(version.Patch);
        }

        [Fact]
        public void TryParseMinorWildcard()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.*", out version);

            Assert.True(result);
            Assert.Equal(1, version.Major);
            Assert.Null(version.Minor);
            Assert.Null(version.Patch);
        }

        [Fact]
        public void TryParsePatchWildcard()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.2.*", out version);

            Assert.True(result);
            Assert.Equal(1, version.Major);
            Assert.Equal(2, version.Minor);
            Assert.Null(version.Patch);
        }

        [Fact(Skip = "Needs check with specification and regex refactoring")]
        public void TryParseWildcardWithMinorReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("*.2", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact(Skip = "Needs check with specification and regex refactoring")]
        public void TryParseWildcardWithMinorAndPatchReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("*.2.3", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact(Skip = "Needs check with specification and regex refactoring")]
        public void TryParseWildcardInMiddleReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.*.3", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact(Skip = "Needs check with specification and regex refactoring")]
        public void TryParseMinorWildcardWithPrereleaseReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.*-alpha", out version);

            Assert.False(result);
            Assert.Null(version);
        }

        [Fact(Skip = "Needs check with specification and regex refactoring")]
        public void TryParsePatchWildcardWithPrereleaseReturnsFalse()
        {
            SemanticVersion version;
            var result = SemanticVersion.TryParse("1.2.*-alpha", out version);

            Assert.False(result);
            Assert.Null(version);
        }
    }
}