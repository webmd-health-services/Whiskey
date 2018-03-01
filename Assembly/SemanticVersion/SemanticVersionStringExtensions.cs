namespace SemVersion
{
    using System;

    /// <summary>Contains extensions to the string class to improve comparison.</summary>
    internal static class SemanticVersionStringExtensions
    {
        /// <summary>Compares two component parts for equality.</summary>
        /// <param name="component"> The left part to compare.</param>
        /// <param name="other">The right part to compare.</param>
        internal static int CompareComponent(this string component, string other)
        {
            bool componentEmpty = string.IsNullOrWhiteSpace(component);
            bool otherEmtpy = string.IsNullOrWhiteSpace(other);

            if ((componentEmpty && otherEmtpy) || (component == "*" && other == "*"))
            {
                return 0;
            }

            if (componentEmpty || component == "*")
            {
                return 1;
            }

            if (otherEmtpy || other == "*")
            {
                return -1;
            }

            string[] componentParts = component.Split(new[] { '.' }, StringSplitOptions.RemoveEmptyEntries);
            string[] otherParts = other.Split(new[] { '.' }, StringSplitOptions.RemoveEmptyEntries);

            for (int i = 0; i < Math.Min(componentParts.Length, otherParts.Length); i++)
            {
                string componentChar = componentParts[i];
                string otherChar = otherParts[i];

                int componentNumVal, otherNumVal;
                bool componentIsNum = int.TryParse(componentChar, out componentNumVal);
                bool otherIsNum = int.TryParse(otherChar, out otherNumVal);

                if (componentIsNum && otherIsNum)
                {
                    if (componentNumVal.CompareTo(otherNumVal) == 0)
                    {
                        continue;
                    }
                    return componentNumVal.CompareTo(otherNumVal);
                }
                else
                {
                    if (componentIsNum)
                    {
                        return -1;
                    }

                    if (otherIsNum)
                    {
                        return 1;
                    }

                    int comp = string.Compare(componentChar, otherChar, StringComparison.OrdinalIgnoreCase);
                    if (comp != 0)
                    {
                        return comp;
                    }
                }
            }

            return componentParts.Length.CompareTo(otherParts.Length);
        }
    }
}