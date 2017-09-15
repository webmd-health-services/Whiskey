using NUnit.Framework;

namespace NUnit3PassingTest
{
	[TestFixture]
    public class TestFixture
    {
		[Test]
		public void ShouldPass()
		{
			Assert.That(1, Is.EqualTo(1));
		}

        [Test]
        [Category("Category with Spaces 1")]
        public void HasCategory1()
        {
            Assert.That(2, Is.EqualTo(2));
        }

        [Test]
        [Category("Category with Spaces 2")]
        public void HasCategory2()
        {
            Assert.That(3, Is.EqualTo(3));
        }
    }
}
