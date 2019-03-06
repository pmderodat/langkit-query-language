with Interpreter.Errors;              use Interpreter.Errors;
with Interpreter.Types.Atoms;         use Interpreter.Types.Atoms;
with Interpreter.Error_Handling;      use Interpreter.Error_Handling;
with Interpreter.Types.Node_Lists;    use Interpreter.Types.Node_Lists;

with Libadalang.Iterators;     use Libadalang.Iterators;
with Libadalang.Introspection; use Libadalang.Introspection;
with Libadalang.Common;        use type Libadalang.Common.Ada_Node_Kind_Type;

with Langkit_Support.Text; use Langkit_Support.Text;

with Ada.Exceptions;
with Ada.Containers.Hashed_Maps;
with Ada.Strings.Wide_Wide_Unbounded.Wide_Wide_Hash;
with Ada.Characters.Handling;
with Ada.Characters.Conversions;
with Ada.Strings.Wide_Wide_Unbounded; use Ada.Strings.Wide_Wide_Unbounded;

package body Interpreter.Evaluation is

   package String_Kind_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Unbounded_Text_Type,
      Element_Type    => LALCO.Ada_Node_Kind_Type,
      Hash            => Ada.Strings.Wide_Wide_Unbounded.Wide_Wide_Hash,
      Equivalent_Keys => "=");

   function Eval_List
     (Ctx : in out Eval_Context; Node : LEL.LKQL_Node_List) return Primitive;

   function Eval_Assign
     (Ctx : in out Eval_Context; Node : LEL.Assign) return Primitive;

   function Eval_Identifier
     (Ctx : in out Eval_Context; Node : LEL.Identifier) return Primitive;

   function Eval_Integer (Node : LEL.Integer) return Primitive;

   function Eval_String_Literal (Node : LEL.String_Literal) return Primitive;

   function Eval_Bool_Literal (Node : LEL.Bool_Literal) return Primitive;

   function Eval_Print
     (Ctx : in out Eval_Context; Node : LEL.Print_Stmt) return Primitive;

   function Eval_Bin_Op
     (Ctx : in out Eval_Context; Node : LEL.Bin_Op) return Primitive;

   function Eval_Dot_Access
     (Ctx : in out Eval_Context; Node : LEL.Dot_Access) return Primitive;

   function Eval_Is
     (Ctx : in out Eval_Context; Node : LEL.Is_Clause) return Primitive;

   function Eval_Query
     (Ctx : in out Eval_Context; Node : LEL.Query) return Primitive;

   function To_Ada_Node_Kind
     (Kind_Name : Unbounded_Text_Type) return LALCO.Ada_Node_Kind_Type;

   function Get_Field
     (Name : Text_Type; Node : LAL.Ada_Node) return LAL.Ada_Node;

   function Get_Field_Index
     (Name : Text_Type; Node : LAL.Ada_Node) return Positive;

   function Compute_Bin_Op (Op : LEL.Op'Class; Left, Right : Atom) return Atom;

   function Reduce
     (Ctx : in out Eval_Context; Node : LEL.LKQL_Node'Class) return Atom;

   function Format_Ada_Kind_Name (Name : String) return Unbounded_Text_Type
     with Pre => Name'Length > 4 and then
                 Name (Name'First .. Name'First + 3) = "ADA_";
   --  Takes the String representation of an Ada node kind of the form
   --  "ADA_KIND_NAME" and returns a String of the form "KindName".

   function Init_Name_Kinds_Lookup return String_Kind_Maps.Map;

   --------------------------
   -- Format_Ada_Kind_Name --
   --------------------------

   function Format_Ada_Kind_Name (Name : String) return Unbounded_Text_Type is
      use Ada.Characters.Handling;
      use Ada.Characters.Conversions;
      Formatted : Unbounded_Text_Type;
      New_Word  : Boolean := True;
   begin
      for C of Name (Name'First + 4 .. Name'Last) loop
         if C /= '_' then
            if New_Word then
               Append (Formatted, To_Wide_Wide_Character (C));
            else
               Append (Formatted, To_Wide_Wide_Character (To_Lower (C)));
            end if;

            New_Word := False;
         else
            New_Word := True;
         end if;
      end loop;

      return Formatted;
   end Format_Ada_Kind_Name;
   --  TODO: do the conversion using Langkit's primitives (when available !)

   ----------------------------
   -- Init_Name_Kinds_Lookup --
   ----------------------------

   function Init_Name_Kinds_Lookup return String_Kind_Maps.Map is
      Result : String_Kind_Maps.Map;
   begin
      for K in LALCO.Ada_Node_Kind_Type loop
         Result.Insert (Format_Ada_Kind_Name (K'Image), K);
      end loop;

      return Result;
   end Init_Name_Kinds_Lookup;

   Name_Kinds : constant String_Kind_Maps.Map := Init_Name_Kinds_Lookup;
   --  Lookup table used to quickly retrieve the Ada node kind associated
   --  with a given name, if any.

   ----------
   -- Eval --
   ----------

   function Eval
     (Ctx : in out Eval_Context; Node : LEL.LKQL_Node'Class) return Primitive
   is
   begin
      return (case Node.Kind is
                 when LELCO.lkql_LKQL_Node_List =>
                   Eval_List (Ctx, Node.As_LKQL_Node_List),
                 when LELCO.lkql_Assign =>
                   Eval_Assign (Ctx, Node.As_Assign),
                 when LELCO.lkql_Identifier =>
                   Eval_Identifier (Ctx, Node.As_Identifier),
                 when LELCO.lkql_Integer =>
                   Eval_Integer (Node.As_Integer),
                 when LELCO.lkql_String_Literal =>
                   Eval_String_Literal (Node.As_String_Literal),
                 when LELCO.lkql_Bool_Literal =>
                   Eval_Bool_Literal (Node.As_Bool_Literal),
                 when LELCO.lkql_Print_Stmt =>
                   Eval_Print (Ctx, Node.As_Print_Stmt),
                 when LELCO.lkql_Bin_Op =>
                   Eval_Bin_Op (Ctx, Node.As_Bin_Op),
                 when LELCO.lkql_Dot_Access =>
                   Eval_Dot_Access (Ctx, Node.As_Dot_Access),
                 when LELCO.lkql_Is_Clause =>
                   Eval_Is (Ctx, Node.As_Is_Clause),
                 when LELCO.lkql_Query =>
                   Eval_Query (Ctx, Node.As_Query),
                 when others =>
                    raise Program_Error
                      with "Unsupported evaluation root: " & Node.Kind_Name);
   end Eval;

   ---------------
   -- Eval_List --
   ---------------

   function Eval_List
     (Ctx : in out Eval_Context; Node : LEL.LKQL_Node_List) return Primitive
   is
      Result : Primitive;
   begin
      if Node.Children'Length = 0 then
         return To_Primitive ((Kind => Kind_Unit));
      end if;

      for Child of Node.Children loop
         begin
            Result := Eval (Ctx, Child);
         exception
            when Recoverable_Error => null;
         end;
      end loop;

      return Result;
   end Eval_List;

   -----------------
   -- Eval_Assign --
   -----------------

   function Eval_Assign
     (Ctx : in out Eval_Context; Node : LEL.Assign) return Primitive
   is
      Identifier : constant Unbounded_Text_Type :=
        To_Unbounded_Text (Node.F_Identifier.Text);
   begin
      Ctx.Env.Include (Identifier, Eval (Ctx, Node.F_Value));
      return To_Primitive ((Kind => Kind_Unit));
   end Eval_Assign;

   ---------------------
   -- Eval_identifier --
   ---------------------

   function Eval_Identifier
     (Ctx : in out Eval_Context; Node : LEL.Identifier) return Primitive
   is
   begin
      return Ctx.Env (To_Unbounded_Text (Node.Text));
   end Eval_Identifier;

   ------------------
   -- Eval_integer --
   ------------------

   function Eval_Integer (Node : LEL.Integer) return Primitive is
   begin
      return To_Primitive (Integer'Wide_Wide_Value (Node.Text));
   end Eval_Integer;

   -------------------------
   -- Eval_String_Literal --
   -------------------------

   function Eval_String_Literal (Node : LEL.String_Literal) return Primitive is
      Quoted_Literal : constant Unbounded_Text_Type :=
        To_Unbounded_Text (Node.Text);
      Literal : constant Unbounded_Text_Type :=
        Unbounded_Slice (Quoted_Literal, 2, Length (Quoted_Literal) - 1);
   begin
      return To_Primitive (Literal);
   end Eval_String_Literal;

   -------------------------
   -- Eval_Bool_Literal --
   -------------------------

   function Eval_Bool_Literal (Node : LEL.Bool_Literal) return Primitive is
      use type LELCO.LKQL_Node_Kind_Type;
      Value : constant Boolean := (Node.Kind = LELCO.lkql_Bool_Literal_True);
   begin
      return To_Primitive (Value);
   end Eval_Bool_Literal;

   ----------------
   -- Eval_Print --
   ----------------

   function Eval_Print
     (Ctx : in out Eval_Context; Node : LEL.Print_Stmt) return Primitive
   is
   begin
      Display (Eval (Ctx, Node.F_Value));
      return To_Primitive ((Kind => Kind_Unit));
   end Eval_Print;

   -----------------
   -- Eval_Bin_Op --
   -----------------

   function Eval_Bin_Op
     (Ctx : in out Eval_Context; Node : LEL.Bin_Op) return Primitive
   is
      Left   : constant Atom := Reduce (Ctx, Node.F_Left);
      Right  : constant Atom := Reduce (Ctx, Node.F_Right);
      Result : constant Atom := Compute_Bin_Op (Node.F_Op, Left, Right);
   begin
      return To_Primitive (Result);
   exception
      when E : Unsupported_Error =>
         Raise_Error (Ctx,
                      Node.As_LKQL_Node,
                      Ada.Exceptions.Exception_Message (E));
   end Eval_Bin_Op;

   --------------------
   -- Eval_Dot_Acess --
   --------------------

   function Eval_Dot_Access
     (Ctx : in out Eval_Context; Node : LEL.Dot_Access) return Primitive
   is
      Receiver    : constant Primitive := Eval (Ctx, Node.F_Receiver);
      Member_Name : constant Text_Type := Node.F_Member.Text;
   begin
      if Receiver.Kind /= Kind_Node then
         Raise_Invalid_Member (Ctx, Node, Receiver);
      end if;

      return To_Primitive (Get_Field (Member_Name, Receiver.Node_Val));
   end Eval_Dot_Access;

   -------------
   -- Eval Is --
   -------------

   function Eval_Is
     (Ctx : in out Eval_Context; Node : LEL.Is_Clause) return Primitive
   is
      Tested_Node : constant Primitive := Eval (Ctx, Node.F_Node_Expr);
   begin
      if Tested_Node.Kind /= Kind_Node then
         Raise_Invalid_Is_Operand (Ctx, Node, Tested_Node);
      end if;

      declare
         Expected_Kind : constant LALCO.Ada_Node_Kind_Type
           := To_Ada_Node_Kind (To_Unbounded_Text (Node.F_Kind_Name.Text));
         Kind_Match    : constant Boolean :=
           Tested_Node.Node_Val.Kind = Expected_Kind;
      begin
         return To_Primitive (Kind_Match);
      end;
   end Eval_Is;

   ----------------
   -- Eval_Query --
   ----------------

   function Eval_Query
     (Ctx : in out Eval_Context; Node : LEL.Query) return Primitive
   is
      It           : Traverse_Iterator'Class := Traverse (Ctx.AST_Root);
      Current_Node : LAL.Ada_Node;
      Result       : Node_List;
      Local_Ctx    : Eval_Context;
      Binding      : constant Unbounded_Text_Type :=
        To_Unbounded_Text (Node.F_Binding.Text);
   begin
      if Ctx.AST_Root.Is_Null then
         Raise_Null_Root (Ctx, Node);
      end if;

      while It.Next (Current_Node) loop
         Local_Ctx := Ctx;
         Local_Ctx.Env.Include (Binding, To_Primitive (Current_Node));
         declare
            When_Clause_Result : constant Primitive :=
              Eval (Local_Ctx, Node.F_When_Clause);
         begin
            if When_Clause_Result.Kind /= Kind_Atom or else
               When_Clause_Result.Atom_Val.Kind /= Kind_Bool
            then
               Raise_Invalid_Type (Ctx,
                                   Node.F_When_Clause.As_LKQL_Node,
                                   "Bool",
                                   Kind_Name (When_Clause_Result));
            end if;

            if When_Clause_Result = To_Primitive (True) then
               Result.Nodes.Append (Current_Node);
            end if;
         exception
               when Recoverable_Error => null;
         end;
      end loop;

      return (Kind => Kind_Node_List, Node_List_Val => Result);
   end Eval_Query;

   ----------------------
   -- To_Ada_Node_Kind --
   ----------------------

   function To_Ada_Node_Kind
     (Kind_Name : Unbounded_Text_Type) return LALCO.Ada_Node_Kind_Type
   is
      use String_Kind_Maps;
      Position : constant Cursor := Name_Kinds.Find (Kind_Name);
   begin
      if not Has_Element (Position) then
         raise Program_Error with
           "Invalid kind name: " & To_UTF8 (To_Text (Kind_Name));
      end if;

      return Element (Position);
   end To_Ada_Node_Kind;

   ---------------
   -- Get_Field --
   ---------------

   function Get_Field
     (Name : Text_Type; Node : LAL.Ada_Node) return LAL.Ada_Node
   is
      Idx : constant Positive := Get_Field_Index (Name, Node);
   begin
      return Node.Children (Idx);
   end Get_Field;

   ---------------------
   -- Get_Field_Index --
   ---------------------

   function Get_Field_Index
     (Name : Text_Type; Node : LAL.Ada_Node) return Positive
   is
      UTF8_Name : constant String := To_UTF8 (Name);
   begin
      for F of Fields (Node.Kind) loop
         if Field_Name (F) = UTF8_Name then
            return Index (Node.Kind, F);
         end if;
      end loop;

      raise Program_Error with
        "Node of kind " & Node.Kind_Name & " has no field named " & UTF8_Name;
   end Get_Field_Index;

   --------------------
   -- Compute_Bin_Op --
   --------------------

   function Compute_Bin_Op (Op : LEL.Op'Class; Left, Right : Atom) return Atom
   is
   begin
      case Op.Kind is
         when LELCO.lkql_Op_Plus =>
            return Left + Right;
         when LELCO.lkql_Op_Eq =>
            return Left = Right;
         when LELCO.lkql_Op_And =>
            return Left and Right;
         when LELCO.lkql_Op_Or =>
            return Left or Right;
         when others =>
            raise Program_Error with
              "Operator not implemented: " & Op.Kind_Name;
      end case;
   end Compute_Bin_Op;

   ------------
   -- Reduce --
   ------------

   function Reduce
     (Ctx : in out Eval_Context; Node : LEL.LKQL_Node'Class) return Atom
   is
      Reduced : constant Primitive := Eval (Ctx, Node);
   begin
      if Reduced.Kind /= Kind_Atom then
         Raise_Invalid_Type (Ctx, Node.As_LKQL_Node, "atom", Node.Kind_Name);
      else
         return Reduced.Atom_Val;
      end if;
   end Reduce;

end Interpreter.Evaluation;
