require "spec"
require "../src/regex-syntax"
require "../src/regex/syntax/translate"

def expect_parse_error(message : Regex? = nil, &)
  ex = expect_raises(Regex::Syntax::ParseError) do
    yield
  end
  if matcher = message
    ex.raw_message.should match(matcher)
  end
  ex
end

def expect_ast_error(kind : Regex::Syntax::AST::ErrorKind? = nil, span : Regex::Syntax::AST::Span? = nil, auxiliary_span : Regex::Syntax::AST::Span? = nil, &)
  ex = expect_raises(Regex::Syntax::AST::Error) do
    yield
  end
  ex.kind.should eq(kind) if kind
  ex.span.should eq(span) if span
  ex.auxiliary_span.should eq(auxiliary_span) unless auxiliary_span.nil?
  ex
end

def expect_hir_error(kind : Regex::Syntax::Hir::ErrorKind? = nil, span : Regex::Syntax::AST::Span? = nil, &)
  ex = expect_raises(Regex::Syntax::Hir::Error) do
    yield
  end
  ex.kind.should eq(kind) if kind
  ex.span.should eq(span) if span
  ex
end
