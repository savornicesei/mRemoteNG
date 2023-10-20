// This file is used by Code Analysis to maintain SuppressMessage
// attributes that are applied to this project.
// Project-level suppressions either have no target or are given
// a specific target and scoped to a namespace, type, member, etc.

using System.Diagnostics.CodeAnalysis;

[assembly: SuppressMessage("StyleCop.CSharp.DocumentationRules", "SA1600:Elements should be documented", Justification = "No need to document tests", Scope = "namespaceanddescendants", Target = "~N:Tests")]
[assembly: SuppressMessage("StyleCop.CSharp.DocumentationRules", "SA1615:Element return value should be documented", Justification = "No need to document tests", Scope = "namespaceanddescendants", Target = "~N:Tests")]
[assembly: SuppressMessage("StyleCop.CSharp.DocumentationRules", "SA1618:Generic type parameters should be documented", Justification = "No need to document tests", Scope = "namespaceanddescendants", Target = "~N:Tests")]

[assembly: SuppressMessage("StyleCop.CSharp.OrderingRules", "SA1202:Elements should be ordered by access", Justification = "No need for test", Scope = "namespaceanddescendants", Target = "~N:Tests")]

[assembly:SuppressMessage("Naming", "CA1707:Identifiers should not contain underscores", Justification = "No need for test", Scope = "namespaceanddescendants", Target = "~N:Tests")]