using System;

namespace Whiskey.Tasks
{
    public class ParameterValueFromVariableAttribute : Attribute
    {
        public ParameterValueFromVariableAttribute(string name)
        {
            VariableName = name;
        }

        public string VariableName { get; }
    }
}
