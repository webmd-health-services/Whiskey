using NUnit.Framework;

namespace NUnit2PassingTest
{
	[TestFixture]
    public class TestFixture
    {
		[Test]
		public void ShouldPass()
		{
			Assert.That(1, Is.EqualTo(1));
		}
    }
}
