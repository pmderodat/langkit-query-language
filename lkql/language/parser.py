from langkit.dsl import (T, ASTNode, abstract, Field)
from langkit.parsers import Grammar, Or, List, Pick, Opt
from langkit.expressions import (
    Property, AbstractProperty, Self, String, No
)
from lexer import Token


@abstract
class LKQLNode(ASTNode):
    """
    Root node class for LKQL AST nodes.
    """
    pass


@abstract
class Expr(LKQLNode):
    """
    Root node class for LKQL expressions.
    """
    pass


@abstract
class Op(LKQLNode):
    """
    Base class for operators.
    """
    enum_node = True
    alternatives = [
        'plus', 'minus', 'mul', 'div', 'and', 'or', 'eq', 'neq', 'concat'
    ]


class BoolLiteral(Expr):
    """
    Boolean literal
    """
    enum_node = True
    alternatives = ['true', 'false']


class Identifier(Expr):
    """
    Regular identifier.
    """
    token_node = True


class Integer(Expr):
    """
    Integer literal.
    """
    token_node = True


class StringLiteral(Expr):
    """
    String literal.
    """
    token_node = True


class BinOp(Expr):
    """
    Binary operation.
    """
    left = Field(type=Expr)
    op = Field(type=Op)
    right = Field(type=Expr)


class Assign(Expr):
    """
    Assign expression.
    An assignment associates a name with a value, and returns Unit.

    For instance::
       let message = "Hello World"
    """
    identifier = Field(type=Identifier)
    value = Field(type=Expr)


class PrintStmt(Expr):
    """
    `print` built-in.
    """
    value = Field(type=Expr)


class DotAccess(Expr):
    """
    Access to a node's field using dot notation.
    """
    receiver = Field(type=Expr)
    member = Field(type=Identifier)


class IsClause(Expr):
    """
    Check a node's kind using the 'is' keyword.
    """
    node_expr = Field(type=Expr)
    kind_name = Field(type=Identifier)


class InClause(Expr):
    """
    Check that a list contains a given value using the 'in' keyword
    """
    value_expr = Field(type=Expr)
    list_expr = Field(type=Expr)


class Indexing(Expr):
    """
    Access to the nth element of a List or String

    For instance::
       values[0]
    """
    collection_expr = Field(type=Expr)
    index_expr = Field(type=Expr)


@abstract
class NodePattern(LKQLNode):
    """
    Root node class for node patterns
    """

    binding_name = AbstractProperty(
        type=T.String, public=True,
        doc="Return the pattern's binding name."
            "Return an empty string if the pattern doesn't "
            "contain a binding name"
    )

    has_binding = Property(Self.binding_name.length > 0,
                           type=T.Bool, public=True,
                           doc="Return whether the node patern contains a "
                               "binding name")


class BindingNodePattern(NodePattern):
    """
    Node pattern comprising only a binding identifier

    For instance::
       let decls = query o ...
    """
    binding = Field(type=Identifier)

    binding_name = Property(Self.binding.text)


class KindNodePattern(NodePattern):
    """
    Node pattern comprising only a kind name

    For instance::
       let decls = query ObjectDecl ...
    """
    identifier = Field(type=Identifier)

    binding_name = Property(String(""))


class FullNodePattern(NodePattern):
    """
    Complete node pattern of the form: binding @ KindName

    For instance::
       let decls = query o@ObjectDecl ...
    """
    binding_pattern = Field(type=BindingNodePattern)
    kind_pattern = Field(type=KindNodePattern)

    binding_name = Property(Self.binding_pattern.binding_name)


@abstract
class SelectorPattern(LKQLNode):
    """
    Root node for selector patterns
    """

    condition = Property(
        No(T.Expr),
        type=T.Expr, public=True,
        doc="Conditions associated with this selector"
    )

    selector_name = AbstractProperty(
        type=T.String, public=True,
        doc="Name of the selector."
    )

    quantifier_name = Property(
        String("some"),  # default implicit quantifier
        type=T.String, public=True,
        doc="""Name of the selector's quantifier
               If the selector pattern doesn't include a quantifier, this
               property defaults to "some"."""
    )


class NamedSelector(SelectorPattern):
    """
    Selector comprising only a selector name.
    Used to specify the relationship between the node being queried and some
    other nodes.

    For instance::
       query p [children] ObjectDecl ...
    """

    name = Field(type=Identifier)

    selector_name = Property(Self.name.text, public=True)


class ParametrizedSelector(NamedSelector):
    """
    Selector of the form selector(condition1, condition2, ...)
    """
    condition_expr = Field(type=T.Expr)

    condition = Property(Self.condition_expr)


class QuantifiedSelector(SelectorPattern):
    """
    Selector of the form: [quantifier selector_name].
    The supported quantifiers are: some, all

    For instance::
       query p [all children] ObjectDecl ...
    """
    quantifier = Field(type=Identifier)
    selector = Field(type=NamedSelector)

    selector_name = Property(Self.selector.selector_name, public=True)

    quantifier_name = Property(Self.quantifier.text)

    condition = Property(Self.selector.condition)


@abstract
class QueryPattern(Expr):
    """
    Root node class for query patterns
    """
    pass


class NodeQueryPattern(QueryPattern):
    """
    A query pattern of the form: node_pattern

    For instance::
       let decls = query ObjectDecls when ...
    """
    queried_node = Field(type=NodePattern)


class FullQueryPattern(NodeQueryPattern):
    """
    A query pattern of the form: node_pattern selector_pattern node_pattern

    For instance::
       let withAspects = query ObjectDecl [child] AspectAssoc when ...
    """
    selector = Field(type=SelectorPattern)
    related_node = Field(type=NodePattern)


class Query(Expr):
    """
    Query without filtering predicate.

    For instance::
       let withAspects = query ObjectDecl [child] AspectAssoc
    """
    pattern = Field(type=QueryPattern)


class FilteredQuery(Query):
    """
    Query with a filtering predicate.

    For instance::
       let classesNamedA = query cls@ClassDecl when cls.identifier == "A"
    """
    predicate = Field(type=Expr)


class ArrowAssoc(LKQLNode):
    """
    Arrow association of the form: id <- expr.
    This construction is meant to be used a part of a list comprehension
    """
    binding_name = Field(type=Identifier)
    coll_expr = Field(type=Expr)


class ListComprehension (Expr):
    """
    List comprehension of the form:
        [ expr | generator1, generator2, ...,  opt(guard)]
    """
    expr = Field(type=Expr)
    generators = Field(type=ArrowAssoc.list)
    guard = Field(type=Expr)


class ValExpr (Expr):
    """
    Expression of the form: val id = value; expr

    For instance::
       val x = 40;
       val y = 2;
       x + y
    """
    binding_name = Field(type=Identifier)
    binding_value = Field(type=Expr)
    expr = Field(type=Expr)


lkql_grammar = Grammar('main_rule')
G = lkql_grammar
# noinspection PyTypeChecker
lkql_grammar.add_rules(
    main_rule=List(Or(G.statement, G.expr, G.query)),

    statement=Or(G.assign,
                 G.print_stmt),

    print_stmt=PrintStmt(Token.Print, Token.LPar, G.expr, Token.RPar),

    query=Or(FilteredQuery(Token.QueryTok,
                           G.query_pattern,
                           Token.When,
                           G.expr),
             Query(Token.QueryTok, G.query_pattern)),

    query_pattern=Or(FullQueryPattern(G.node_pattern,
                                      G.selector_pattern,
                                      G.node_pattern),
                     NodeQueryPattern(G.node_pattern)),

    node_pattern=Or(G.full_node_pattern,
                    G.binding_node_pattern,
                    G.kind_node_pattern),

    full_node_pattern=FullNodePattern(G.binding_node_pattern,
                                      Token.At,
                                      G.kind_node_pattern),

    binding_node_pattern=BindingNodePattern(G.identifier),

    kind_node_pattern=KindNodePattern(G.kind_name),

    selector_pattern=Pick(Token.LBrack, G.selector, Token.RBrack),

    selector=Or(G.quantified_selector,
                G.named_selector),

    named_selector=Or(ParametrizedSelector(G.identifier,
                                           Token.LPar,
                                           Opt(G.comp_expr),
                                           Token.RPar),
                      NamedSelector(G.identifier)),

    quantified_selector=QuantifiedSelector(G.identifier, G.named_selector),

    arrow_assoc=ArrowAssoc(G.identifier, Token.LArrow, G.expr),

    listcomp=ListComprehension(Token.LBrack,
                               G.expr,
                               Token.Pipe,
                               List(G.arrow_assoc,
                                    sep=Token.Coma, empty_valid=False),
                               Opt(Token.Coma, G.expr),
                               Token.RBrack),


    expr=Or(BinOp(G.expr,
                  Or(Op.alt_and(Token.And),
                     Op.alt_or(Token.Or)),
                  G.comp_expr),
            G.comp_expr,
            G.val_expr),

    comp_expr=Or(IsClause(G.comp_expr, Token.Is, G.kind_name),
                 InClause(G.comp_expr, Token.In, G.expr),
                 BinOp(G.comp_expr,
                       Or(Op.alt_eq(Token.EqEq),
                          Op.alt_neq(Token.Neq),
                          Op.alt_concat(Token.Amp)),
                       G.plus_expr),
                 G.plus_expr),

    plus_expr=Or(BinOp(G.plus_expr,
                       Or(Op.alt_plus(Token.Plus),
                          Op.alt_minus(Token.Minus)),
                       G.prod_expr),
                 G.prod_expr),

    prod_expr=Or(BinOp(G.prod_expr,
                       Or(Op.alt_mul(Token.Mul),
                          Op.alt_div(Token.Div)),
                       G.value_expr),
                 G.value_expr),

    value_expr=Or(G.listcomp,
                  DotAccess(G.value_expr, Token.Dot, G.identifier),
                  G.assign,
                  Indexing(G.value_expr, Token.LBrack, G.expr, Token.RBrack),
                  G.identifier,
                  G.string_literal,
                  G.bool_literal,
                  G.integer,
                  Pick(Token.LPar, G.expr, Token.RPar)),

    val_expr=ValExpr(Token.Val, G.identifier, Token.Eq,
                     G.expr, Token.SemiCol, G.expr),

    assign=Assign(Token.Let, G.identifier, Token.Eq, Or(G.expr, G.query)),

    identifier=Identifier(Token.Identifier),

    kind_name=Identifier(Token.KindName),

    integer=Integer(Token.Integer),

    bool_literal=Or(BoolLiteral.alt_true(Token.TrueLit),
                    BoolLiteral.alt_false(Token.FalseLit)),

    string_literal=StringLiteral(Token.String),
)
