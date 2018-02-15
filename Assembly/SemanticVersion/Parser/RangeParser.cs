namespace SemVersion.Parser
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Linq.Expressions;

    /// <summary>Provides methods to parse a string into an appropriate <see cref="Expression"/> tree or <see cref="Func{T,TResult}"/></summary>
    public class RangeParser
    {
        private readonly Stack<Expression> expressionStack = new Stack<Expression>();
        private readonly Stack<Symbol> operatorStack = new Stack<Symbol>();

        private readonly ParameterExpression variableExpression = Expression.Parameter(typeof(SemanticVersion));

        /// <summary>Create a <see cref="Func{T,TResult}"/> based upon valid version string.</summary>
        /// <param name="range">The range string to parse.</param>
        /// <returns>A useable <see cref="Func{T,TResult}"/> to evaluate a <see cref="SemanticVersion"/> against.</returns>
        /// <remarks>This method calls the <see cref="Parse"/> method internally and compiles the returned expression tree into a func.</remarks>
        public Func<SemanticVersion, bool> Evaluate(string range)
        {
            return this.Parse(range).Compile();
        }

        /// <summary>Parses a range string into an expression tree.</summary>
        /// <param name="range">The range string to parse.</param>
        /// <returns>An expression tree representing the version range.</returns>
        public Expression<Func<SemanticVersion, bool>> Parse(string range)
        {
            if (string.IsNullOrWhiteSpace(range))
            {
                throw new ArgumentException("The range string must not be null or empty", nameof(range));
            }

            this.expressionStack.Clear();
            this.operatorStack.Clear();

            string copyString = range;

            while (copyString.Length > 0)
            {
                if (copyString[0] == '*' || char.IsDigit(copyString[0]))
                {
                    char[] opArr = { ' ', '|', '&', '!', '=', '<', '>' };
                    string version = copyString.TakeWhile(t => !opArr.Any(c => c.Equals(t))).Aggregate(string.Empty, (current, t) => current + t);

                    copyString = copyString.Substring(version.Length);

                    this.expressionStack.Push(this.variableExpression);
                    this.expressionStack.Push(Expression.Constant(SemanticVersion.Parse(version)));

                    continue;
                }

                int length;
                if (Operation.IsDefined(copyString, out length))
                {
                    Operation currentOp = (Operation)copyString.Substring(0, length);
                    copyString = copyString.Substring(length);

                    this.EvaluateWhile(() =>
                                       this.operatorStack.Count > 0
                                       && this.operatorStack.Peek() != (Parentheses)'('
                                       && currentOp.Precedence >= ((Operation)this.operatorStack.Peek()).Precedence);

                    this.operatorStack.Push(currentOp);
                    continue;
                }

                switch (copyString[0])
                {
                    case '(':
                        copyString = copyString.Substring(1);
                        this.operatorStack.Push(Parentheses.Left);
                        continue;
                    case ')':
                        copyString = copyString.Substring(1);
                        this.EvaluateWhile(() => this.operatorStack.Count > 0 & this.operatorStack.Peek() != Parentheses.Left);
                        this.operatorStack.Pop();
                        continue;
                    case ' ':
                        copyString = copyString.Substring(1);
                        continue;
                    default:
                        throw new ArgumentException($"Encountered invalid character {copyString[0]}");
                }
            }

            this.EvaluateWhile(() => this.operatorStack.Count > 0);

            return Expression.Lambda<Func<SemanticVersion, bool>>(this.expressionStack.Pop(), this.variableExpression);
        }

        private void EvaluateWhile(Func<bool> condition)
        {
            if (condition == null)
            {
                throw new ArgumentNullException(nameof(condition), "The loop condition must not be null.");
            }

            // ReSharper disable once LoopVariableIsNeverChangedInsideLoop
            while (condition())
            {
                Operation operation = (Operation)this.operatorStack.Pop();

                Expression[] expressions = new Expression[operation.NumberOfOperands];
                for (int i = operation.NumberOfOperands - 1; i >= 0; i--)
                {
                    expressions[i] = this.expressionStack.Pop();
                }

                this.expressionStack.Push(operation.Apply(expressions));
            }
        }
    }
}
