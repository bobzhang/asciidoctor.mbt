// Ported from test/attribute_list_test.rb. Expected values are the Ruby
// hashes from the assertions, rendered with Ruby 2.x `Hash#inspect`.

///|
fn parse_al(
  line : String,
  positional? : Array[String?],
  block? : @core.Node,
) -> String {
  attrs_inspect(
    @core.parse_attribute_list(line, positional_attrs?=positional, block?),
  )
}

///|
test "collect unnamed attribute" {
  inspect(
    parse_al("quote"),
    content=(
      #|{1=>"quote"}
    ),
  )
}

///|
test "collect unnamed attribute double-quoted" {
  inspect(
    parse_al("\"quote\""),
    content=(
      #|{1=>"quote"}
    ),
  )
}

///|
test "collect empty unnamed attribute double-quoted" {
  inspect(
    parse_al("\"\""),
    content=(
      #|{1=>""}
    ),
  )
}

///|
test "collect unnamed attribute double-quoted containing escaped quote" {
  inspect(
    parse_al("\"ba\\\"zaar\""),
    content=(
      #|{1=>"ba\"zaar"}
    ),
  )
}

///|
test "collect unnamed attribute single-quoted" {
  inspect(
    parse_al("'quote'"),
    content=(
      #|{1=>"quote"}
    ),
  )
}

///|
test "collect empty unnamed attribute single-quoted" {
  inspect(
    parse_al("''"),
    content=(
      #|{1=>""}
    ),
  )
}

///|
test "collect isolated single quote positional attribute" {
  let doc = @asciidoctor.load("")
  inspect(
    parse_al("'", block=doc),
    content=(
      #|{1=>"'"}
    ),
  )
}

///|
test "collect isolated single quote attribute value" {
  let doc = @asciidoctor.load("")
  inspect(
    parse_al("name='", block=doc),
    content=(
      #|{"name"=>"'"}
    ),
  )
}

///|
test "collect attribute value as is if it has only leading single quote" {
  let doc = @asciidoctor.load(
    "",
    options=@core.Options::new(attributes=[("val", Str("val"))]),
  )
  inspect(
    parse_al("name='{val}", block=doc),
    content=(
      #|{"name"=>"'{val}"}
    ),
  )
}

///|
test "collect unnamed attribute single-quoted containing escaped quote" {
  inspect(
    parse_al("'ba\\'zaar'"),
    content=(
      #|{1=>"ba'zaar"}
    ),
  )
}

///|
test "collect unnamed attribute with dangling delimiter" {
  inspect(
    parse_al("quote , "),
    content=(
      #|{1=>"quote", 2=>nil}
    ),
  )
}

///|
test "collect unnamed attribute in second position after empty attribute" {
  inspect(
    parse_al(", John Smith"),
    content=(
      #|{1=>nil, 2=>"John Smith"}
    ),
  )
}

///|
test "collect unnamed attributes" {
  inspect(
    parse_al("first, second one, third"),
    content=(
      #|{1=>"first", 2=>"second one", 3=>"third"}
    ),
  )
}

///|
test "collect blank unnamed attributes" {
  inspect(
    parse_al("first,,third,"),
    content=(
      #|{1=>"first", 2=>nil, 3=>"third", 4=>nil}
    ),
  )
}

///|
test "collect unnamed attribute enclosed in equal signs" {
  inspect(
    parse_al("=foo="),
    content=(
      #|{1=>"=foo="}
    ),
  )
}

///|
test "collect named attribute" {
  inspect(
    parse_al("foo=bar"),
    content=(
      #|{"foo"=>"bar"}
    ),
  )
}

///|
test "collect named attribute double-quoted" {
  inspect(
    parse_al("foo=\"bar\""),
    content=(
      #|{"foo"=>"bar"}
    ),
  )
}

///|
test "collect named attribute with double-quoted empty value" {
  inspect(
    parse_al("height=100,caption=\"\",link=\"images/octocat.png\""),
    content=(
      #|{"height"=>"100", "caption"=>"", "link"=>"images/octocat.png"}
    ),
  )
}

///|
test "collect named attribute single-quoted" {
  inspect(
    parse_al("foo='bar'"),
    content=(
      #|{"foo"=>"bar"}
    ),
  )
}

///|
test "collect named attribute with single-quoted empty value" {
  inspect(
    parse_al("height=100,caption='',link='images/octocat.png'"),
    content=(
      #|{"height"=>"100", "caption"=>"", "link"=>"images/octocat.png"}
    ),
  )
}

///|
test "collect single named attribute with empty value" {
  inspect(
    parse_al("foo="),
    content=(
      #|{"foo"=>""}
    ),
  )
}

///|
test "collect single named attribute with empty value when followed by other attributes" {
  inspect(
    parse_al("foo=,bar=baz"),
    content=(
      #|{"foo"=>"", "bar"=>"baz"}
    ),
  )
}

///|
test "collect named attributes unquoted" {
  inspect(
    parse_al("first=value, second=two, third=3"),
    content=(
      #|{"first"=>"value", "second"=>"two", "third"=>"3"}
    ),
  )
}

///|
test "collect named attributes quoted" {
  inspect(
    parse_al("first='value', second=\"value two\", third=three"),
    content=(
      #|{"first"=>"value", "second"=>"value two", "third"=>"three"}
    ),
  )
}

///|
test "collect named attributes quoted containing non-semantic spaces" {
  inspect(
    parse_al(
      "     first    =     'value', second     =\"value two\"     , third=       three      ",
    ),
    content=(
      #|{"first"=>"value", "second"=>"value two", "third"=>"three"}
    ),
  )
}

///|
test "collect mixed named and unnamed attributes" {
  inspect(
    parse_al("first, second=\"value two\", third=three, Sherlock Holmes"),
    content=(
      #|{1=>"first", "second"=>"value two", "third"=>"three", 4=>"Sherlock Holmes"}
    ),
  )
}

///|
test "collect mixed empty named and blank unnamed attributes" {
  inspect(
    parse_al("first,,third=,,fifth=five"),
    content=(
      #|{1=>"first", 2=>nil, "third"=>"", 4=>nil, "fifth"=>"five"}
    ),
  )
}

///|
test "collect options attribute" {
  inspect(
    parse_al("quote, options='opt1,,opt2 , opt3'"),
    content=(
      #|{1=>"quote", "opt1-option"=>"", "opt2-option"=>"", "opt3-option"=>""}
    ),
  )
}

///|
test "collect opts attribute as options" {
  inspect(
    parse_al("quote, opts='opt1,,opt2 , opt3'"),
    content=(
      #|{1=>"quote", "opt1-option"=>"", "opt2-option"=>"", "opt3-option"=>""}
    ),
  )
}

///|
test "should ignore options attribute if empty" {
  inspect(
    parse_al("quote, opts="),
    content=(
      #|{1=>"quote"}
    ),
  )
}

///|
test "collect and rekey unnamed attributes" {
  inspect(
    parse_al("first, second one, third, fourth", positional=[
      Some("a"),
      Some("b"),
      Some("c"),
    ]),
    content=(
      #|{"a"=>"first", 1=>"first", "b"=>"second one", 2=>"second one", "c"=>"third", 3=>"third", 4=>"fourth"}
    ),
  )
}

///|
test "should not assign nil to attribute mapped to missing positional attribute" {
  inspect(
    parse_al("alt text,,100", positional=[
      Some("alt"),
      Some("width"),
      Some("height"),
    ]),
    content=(
      #|{"alt"=>"alt text", 1=>"alt text", 2=>nil, "height"=>"100", 3=>"100"}
    ),
  )
}

///|
test "rekey positional attributes" {
  let attrs = @core.Attributes::new()
  attrs.set_pos(1, Str("source"))
  attrs.set_pos(2, Str("java"))
  @core.rekey_attributes(attrs, [
    Some("style"),
    Some("language"),
    Some("linenums"),
  ])
  |> ignore
  inspect(
    attrs_inspect(attrs),
    content=(
      #|{1=>"source", 2=>"java", "style"=>"source", "language"=>"java"}
    ),
  )
}
