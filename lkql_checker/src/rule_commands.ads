with Ada.Containers.Vectors;

with LKQL.Primitives;    use LKQL.Primitives;
with LKQL.Eval_Contexts; use LKQL.Eval_Contexts;

with Liblkqllang.Analysis;

with Libadalang.Analysis;

with Langkit_Support.Diagnostics; use Langkit_Support.Diagnostics;
with Langkit_Support.Text; use Langkit_Support.Text;

--  A diagnostic is composed of a collection of individual rule commands
package Rule_Commands is

   package L renames Liblkqllang.Analysis;
   package LAL renames Libadalang.Analysis;

   Rule_Error : exception;

   type Rule_Argument is record
      Name  : Unbounded_Text_Type;
      --  Name of the argument

      Value : Unbounded_Text_Type;
      --  Value of the argument, as a string.
   end record;

   package Rule_Argument_Vectors
   is new Ada.Containers.Vectors (Positive, Rule_Argument);

   type Rule_Command is tagged record
      Name          : Unbounded_Text_Type;
      --  Name of the Rule

      LKQL_Root     : L.LKQL_Node;
      --  Root of the LKQL AST

      LKQL_Context  : L.Analysis_Context;
      --  Analysis context that was used to create the LKQL AST

      Rule_Args    : Rule_Argument_Vectors.Vector;
      --  Optional arguments to pass to the rule. Empty by default.
   end record;

   type Eval_Diagnostic is record
      Diag : Diagnostic;
      Unit : Libadalang.Analysis.Analysis_Unit;
   end record;

   package Eval_Diagnostic_Vectors
   is new Ada.Containers.Vectors (Positive, Eval_Diagnostic);

   function Evaluate
     (Self : Rule_Command;
      Ctx  : Eval_Context)
      return Eval_Diagnostic_Vectors.Vector;
   --  Execute the LKQL script of the rule and return a Rule_Result value
   --  containing the flagged nodes.

   function Create_Rule_Command (LKQL_File_Path : String) return Rule_Command;
   --  Create a Rule_Command value with the given name and arguments

   procedure Check_Kind
     (Expected_Kind : Valid_Primitive_Kind; Actual_Kind : Valid_Primitive_Kind;
      Context       : String);
   --  Raise a Rule_error if 'Expected_Kind' is different from 'Actual_Kind'.
   --  The error message will start with the context String.

end Rule_Commands;
