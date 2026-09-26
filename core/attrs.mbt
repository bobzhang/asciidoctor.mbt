///|
/// An attribute value. Ruby Asciidoctor stores strings, integers, floats,
/// booleans and nil in attribute hashes; this enum mirrors that.
pub(all) enum AttrVal {
  Str(String)
  Int(Int)
  Float(Double)
  Bool(Bool)
  List(Array[String])
  Nil
} derive(Eq, Debug)

///|
/// Ruby `to_s` of the value (`nil` → "").
pub fn AttrVal::to_s(self : AttrVal) -> String {
  match self {
    Str(s) => s
    Int(i) => i.to_string()
    Float(f) => @rb.float_to_s(f)
    Bool(b) => if b { "true" } else { "false" }
    List(l) => "[" + l.map(x => x.escape()).join(", ") + "]"
    Nil => ""
  }
}

///|
/// Ruby truthiness: only nil and false are falsy.
pub fn AttrVal::truthy(self : AttrVal) -> Bool {
  match self {
    Nil | Bool(false) => false
    _ => true
  }
}

///|
/// Ruby `to_i` of the value.
pub fn AttrVal::to_i(self : AttrVal) -> Int {
  match self {
    Str(s) => @rb.to_i(s)
    Int(i) => i
    Float(f) => f.to_int()
    _ => 0
  }
}

///|
/// Ruby `to_f` of the value.
pub fn AttrVal::to_f(self : AttrVal) -> Double {
  match self {
    Str(s) => @rb.to_f(s)
    Int(i) => i.to_double()
    Float(f) => f
    _ => 0.0
  }
}

///|
/// Ruby `==` against a string.
pub fn AttrVal::is_str(self : AttrVal, s : String) -> Bool {
  self is Str(v) && v == s
}

///|
/// Key of an attribute: named (String) or positional (1-based Int).
pub(all) enum AttrKey {
  Name(String)
  Pos(Int)
} derive(Eq, Hash, Debug)

///|
/// A document attribute assignment recorded in the body of a document and
/// replayed during conversion (Ruby `Document::AttributeEntry`).
pub(all) struct AttributeEntry {
  name : String
  value : String?
  negate : Bool
} derive(Debug)

///|
pub fn AttributeEntry::new(
  name : String,
  value : String?,
  negate? : Bool,
) -> AttributeEntry {
  { name, value, negate: negate.unwrap_or(value is None), }
}

///|
/// An insertion-ordered attribute map (Ruby Hash semantics) plus the
/// attribute entries that Ruby stores under the `:attribute_entries` key.
pub struct Attributes {
  priv map : Map[AttrKey, AttrVal]
  mut entries : Array[AttributeEntry]?
}

///|
pub fn Attributes::new() -> Attributes {
  { map: {}, entries: None, }
}

///|
pub fn Attributes::from_array(pairs : Array[(String, AttrVal)]) -> Attributes {
  let a = Attributes::new()
  for p in pairs {
    a.map[Name(p.0)] = p.1
  }
  a
}

///|
/// Shallow copy (Ruby `Hash#merge` with no arguments).
pub fn Attributes::copy(self : Attributes) -> Attributes {
  let m = {}
  for k, v in self.map {
    m[k] = v
  }
  { map: m, entries: self.entries.map(e => e.copy()), }
}

///|
pub fn Attributes::length(self : Attributes) -> Int {
  self.map.length()
}

///|
/// Whether the map is empty (the attribute entries count as a key, as in Ruby).
pub fn Attributes::is_empty(self : Attributes) -> Bool {
  self.map.is_empty() && self.entries is None
}

///|
pub fn Attributes::clear(self : Attributes) -> Unit {
  self.map.clear()
  self.entries = None
}

///|
/// Replaces all contents with those of `other` (Ruby `Hash#replace`).
pub fn Attributes::replace(self : Attributes, other : Attributes) -> Unit {
  if physical_equal(self, other) {
    return
  }
  self.map.clear()
  for k, v in other.map {
    self.map[k] = v
  }
  self.entries = other.entries.map(e => e.copy())
}

///|
/// Merges `other` into self, overwriting (Ruby `Hash#update`).
pub fn Attributes::update(self : Attributes, other : Attributes) -> Unit {
  for k, v in other.map {
    self.map[k] = v
  }
  if other.entries is Some(e) {
    self.entries = Some(e.copy())
  }
}

///|
/// Raw value of a named attribute.
pub fn Attributes::get(self : Attributes, name : String) -> AttrVal? {
  self.map.get(Name(name))
}

///|
/// Raw value of a positional attribute.
pub fn Attributes::get_pos(self : Attributes, i : Int) -> AttrVal? {
  self.map.get(Pos(i))
}

///|
pub fn Attributes::get_key(self : Attributes, k : AttrKey) -> AttrVal? {
  self.map.get(k)
}

///|
/// Ruby `attrs[name]` coerced to a string when truthy (nil/false → None).
pub fn Attributes::str(self : Attributes, name : String) -> String? {
  match self.map.get(Name(name)) {
    Some(Nil) | Some(Bool(false)) | None => None
    Some(v) => Some(v.to_s())
  }
}

///|
/// Positional attribute as string when truthy.
pub fn Attributes::pos_str(self : Attributes, i : Int) -> String? {
  match self.map.get(Pos(i)) {
    Some(Nil) | Some(Bool(false)) | None => None
    Some(v) => Some(v.to_s())
  }
}

///|
/// Whether a named attribute has a truthy value (Ruby `if attrs[name]`).
pub fn Attributes::truthy(self : Attributes, name : String) -> Bool {
  match self.map.get(Name(name)) {
    Some(v) => v.truthy()
    None => false
  }
}

///|
/// Ruby `attrs.key?(name)`.
pub fn Attributes::contains(self : Attributes, name : String) -> Bool {
  self.map.contains(Name(name))
}

///|
pub fn Attributes::contains_pos(self : Attributes, i : Int) -> Bool {
  self.map.contains(Pos(i))
}

///|
pub fn Attributes::set(self : Attributes, name : String, v : AttrVal) -> Unit {
  self.map[Name(name)] = v
}

///|
pub fn Attributes::set_str(
  self : Attributes,
  name : String,
  v : String,
) -> Unit {
  self.map[Name(name)] = Str(v)
}

///|
pub fn Attributes::set_pos(self : Attributes, i : Int, v : AttrVal) -> Unit {
  self.map[Pos(i)] = v
}

///|
pub fn Attributes::set_key(self : Attributes, k : AttrKey, v : AttrVal) -> Unit {
  self.map[k] = v
}

///|
/// Ruby `attrs[name] ||= value`.
pub fn Attributes::set_default(
  self : Attributes,
  name : String,
  v : AttrVal,
) -> Unit {
  if !self.truthy(name) {
    self.map[Name(name)] = v
  }
}

///|
/// Removes a named attribute, returning its value.
pub fn Attributes::remove(self : Attributes, name : String) -> AttrVal? {
  let k = Name(name)
  let v = self.map.get(k)
  if v is Some(_) {
    self.map.remove(k)
  }
  v
}

///|
/// Removes a named attribute, returning its value as a string when truthy.
pub fn Attributes::remove_str(self : Attributes, name : String) -> String? {
  match self.remove(name) {
    Some(Nil) | Some(Bool(false)) | None => None
    Some(v) => Some(v.to_s())
  }
}

///|
pub fn Attributes::remove_pos(self : Attributes, i : Int) -> AttrVal? {
  let k = Pos(i)
  let v = self.map.get(k)
  if v is Some(_) {
    self.map.remove(k)
  }
  v
}

///|
pub fn Attributes::remove_key(self : Attributes, k : AttrKey) -> Unit {
  self.map.remove(k)
}

///|
/// Iterates over (key, value) pairs in insertion order.
pub fn Attributes::iter(self : Attributes) -> Iter2[AttrKey, AttrVal] {
  self.map.iter2()
}

///|
/// Named keys in insertion order.
pub fn Attributes::names(self : Attributes) -> Array[String] {
  let out = []
  for k, _ in self.map {
    if k is Name(n) {
      out.push(n)
    }
  }
  out
}

///|
/// Records an attribute entry (Ruby `AttributeEntry#save_to`).
pub fn Attributes::save_entry(
  self : Attributes,
  entry : AttributeEntry,
) -> Unit {
  match self.entries {
    Some(e) => e.push(entry)
    None => self.entries = Some([entry])
  }
}

///|
/// Ruby `attrs.delete :attribute_entries`.
pub fn Attributes::clear_entries(self : Attributes) -> Unit {
  self.entries = None
}
