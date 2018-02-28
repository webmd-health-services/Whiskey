namespace SemVersion.Parser
{
    using System;
    using System.Collections.Generic;
    using System.Linq.Expressions;

    internal sealed class Operation : Symbol
    {
        private readonly Func<Expression, Expression, Expression> binaryOperation;

        private readonly Func<Expression, Expression> unaryOperation;

        public static readonly Operation OrElse = new Operation(2, Expression.OrElse, "OrElse");

        public static readonly Operation AndAlso = new Operation(3, Expression.AndAlso, "AndAlso");

        public static readonly Operation NotEqual = new Operation(1, Expression.NotEqual, "NotEqual");

        public static readonly Operation Equal = new Operation(1, Expression.Equal, "Equal");

        public static readonly Operation LessThan = new Operation(1, Expression.LessThan, "LessThan");

        public static readonly Operation GreaterThan = new Operation(1, Expression.GreaterThan, "GreaterThan");

        public static readonly Operation LessThanOrEqual = new Operation(1, Expression.LessThanOrEqual, "LessThanOrEqual");

        public static readonly Operation GreaterThanOrEqual = new Operation(1, Expression.GreaterThanOrEqual, "GreaterThanOrEqual");

        public static readonly Operation Not = new Operation(1, Expression.Not, "Not");

        private Operation(int precedence, string name)
        {
            this.Precedence = precedence;
            this.Name = name;
        }

        private Operation(int precedence, Func<Expression, Expression> unaryOperation, string name) 
            : this(precedence, name)
        {
            this.unaryOperation = unaryOperation;
            this.NumberOfOperands = 1;
        }

        private Operation(int precedence, Func<Expression, Expression, Expression> operation, string name) 
            : this(precedence, name)
        {
            this.binaryOperation = operation;
            this.NumberOfOperands = 2;
        }

        public string Name { get; private set; }

        public int NumberOfOperands { get; private set; }

        public int Precedence { get; private set; }

        public static explicit operator Operation(string operation)
        {
            Operation result;

            if (Operations.TryGetValue(operation, out result))
            {
                return result;
            }

            throw new InvalidCastException();
        }

        public Expression Apply(params Expression[] expressions)
        {
            if (expressions == null)
            {
                throw new ArgumentNullException(nameof(expressions));
            }

            switch (expressions.Length)
            {
                case 0:
                    throw new ArgumentException("There needs to be at least one expression present to apply.");
                case 1:
                    return this.unaryOperation(expressions[0]);
                case 2:
                    return this.binaryOperation(expressions[0], expressions[1]);
                default:
                    throw new NotSupportedException("Expressions with more than three parameters are not supported.");
            }
        }

        public static bool IsDefined(string operation, out int length)
        {
            if (Operations.ContainsKey(operation.Substring(0, 2)))
            {
                length = 2;
                return true;
            }

            if (Operations.ContainsKey(operation[0].ToString()))
            {
                length = 1;
                return true;
            }

            length = 0;
            return false;
        }

        private static readonly Dictionary<string, Operation> Operations = new Dictionary<string, Operation>
        {
            { "||",  OrElse},
            { "&&", AndAlso },
            { "!=", NotEqual },
            { "==", Equal },
            { "<", LessThan },
            { ">", GreaterThan },
            { "<=", LessThanOrEqual },
            { ">=", GreaterThanOrEqual },
            { "!", Not }
        };
    }
}