using NUnit.Framework;

namespace NUnit2FailingTest
{
	[TestFixture]
    public class TestFixture
    {
		[Test]
		public void ShouldFail()
		{
			Assert.That(1, Is.EqualTo(2));
		}
    }
}
