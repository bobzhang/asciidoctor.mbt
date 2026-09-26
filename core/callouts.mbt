///|
/// Tracks callouts across listing blocks and callout lists (Ruby `Callouts`).
pub struct Callouts {
  priv lists : Array[Array[(Int, String)]]
  priv mut list_index : Int
  priv mut co_index : Int
}

///|
pub fn Callouts::new() -> Callouts {
  let c = { lists: [], list_index: 0, co_index: 1, }
  c.next_list()
  c
}

///|
/// Registers a callout with the given ordinal; returns its id.
pub fn Callouts::register(self : Callouts, li_ordinal : String) -> String {
  let id = "CO\{self.list_index}-\{self.co_index}"
  self.current_list().push((@rb.to_i(li_ordinal), id))
  self.co_index += 1
  id
}

///|
/// Reads the id of the next callout in the current list.
pub fn Callouts::read_next_id(self : Callouts) -> String? {
  let list = self.current_list()
  let id = if self.co_index <= list.length() {
    Some(list[self.co_index - 1].1)
  } else {
    None
  }
  self.co_index += 1
  id
}

///|
/// Space-separated ids of the callouts with the given ordinal.
pub fn Callouts::callout_ids(self : Callouts, li_ordinal : Int) -> String {
  self
  .current_list()
  .filter(item => item.0 == li_ordinal)
  .map(item => item.1)
  .join(" ")
}

///|
fn Callouts::current_list(self : Callouts) -> Array[(Int, String)] {
  self.lists[self.list_index - 1]
}

///|
pub fn Callouts::next_list(self : Callouts) -> Unit {
  self.list_index += 1
  if self.lists.length() < self.list_index {
    self.lists.push([])
  }
  self.co_index = 1
}

///|
pub fn Callouts::rewind(self : Callouts) -> Unit {
  self.list_index = 1
  self.co_index = 1
}
