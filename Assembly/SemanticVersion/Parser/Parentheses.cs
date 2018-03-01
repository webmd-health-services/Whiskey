namespace SemVersion.Parser
{
    using System;

    internal class Parentheses : Symbol
    {
        public static readonly Parentheses Left = new Parentheses();
        public static readonly Parentheses Right = new Parentheses();

        private Parentheses()
        {
        }

        public static explicit operator Parentheses(char parenthesis)
        {
            switch (parenthesis)
            {
                case '(':
                    return Left;
                case ')':
                    return Right;
                default:
                    throw new InvalidCastException($"Could not cast char '{parenthesis}' to parentheis.");
            }
        }
    }
}