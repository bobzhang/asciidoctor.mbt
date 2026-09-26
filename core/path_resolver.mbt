///|
/// Raised when a path escapes the jail in non-recovering mode.
pub suberror SecurityError {
  SecurityError(String)
} derive(Debug)

///|
/// Resolves system and web paths (Ruby `PathResolver`). POSIX separators only.
pub struct PathResolver {
  mut working_dir : String
  priv sys_cache : Map[String, (Array[String], String?)]
  priv web_cache : Map[String, (Array[String], String?)]
}

///|
pub fn PathResolver::new(working_dir? : String = "/") -> PathResolver {
  { working_dir, sys_cache: {}, web_cache: {}, }
}

///|
pub fn PathResolver::is_absolute(_self : PathResolver, path : String) -> Bool {
  path.has_prefix("/")
}

///|
pub fn PathResolver::is_root(self : PathResolver, path : String) -> Bool {
  self.is_absolute(path)
}

///|
pub fn PathResolver::is_unc(_self : PathResolver, path : String) -> Bool {
  path.has_prefix("//")
}

///|
pub fn PathResolver::is_web_root(_self : PathResolver, path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// Offset at which `path` descends from `base`, or None.
pub fn PathResolver::descends_from(
  _self : PathResolver,
  path : String,
  base : String,
) -> Int? {
  if base == path {
    Some(0)
  } else if base == "/" {
    if path.has_prefix("/") {
      Some(1)
    } else {
      None
    }
  } else if path.has_prefix(base + "/") {
    Some(base.length() + 1)
  } else {
    None
  }
}

///|
/// Path of `path` relative to `base` (Ruby `relative_path`).
pub fn PathResolver::relative_path(
  self : PathResolver,
  path : String,
  base : String,
) -> String {
  if !self.is_root(path) {
    return path
  }
  match self.descends_from(path, base) {
    Some(offset) => @rb.from(path, offset)
    None => {
      // Pathname#relative_path_from
      let (ps, _) = self.partition_path(self.expand_path(path))
      let (bs, _) = self.partition_path(self.expand_path(base))
      let mut i = 0
      while i < ps.length() && i < bs.length() && ps[i] == bs[i] {
        i += 1
      }
      let parts = []
      for _ in i..<bs.length() {
        parts.push("..")
      }
      for j in i..<ps.length() {
        parts.push(ps[j])
      }
      if parts.is_empty() {
        "."
      } else {
        parts.join("/")
      }
    }
  }
}

///|
pub fn PathResolver::posixify(_self : PathResolver, path : String?) -> String {
  path.unwrap_or("")
}

///|
/// Resolves `..` segments (Ruby `expand_path`, no filesystem access).
pub fn PathResolver::expand_path(self : PathResolver, path : String) -> String {
  let (segments, root) = self.partition_path(path)
  if path.contains("..") {
    let resolved = []
    for seg in segments {
      if seg == ".." {
        resolved.pop() |> ignore
      } else {
        resolved.push(seg)
      }
    }
    join_path(resolved, root)
  } else {
    join_path(segments, root)
  }
}

///|
/// Splits a path into segments and root.
pub fn PathResolver::partition_path(
  self : PathResolver,
  path : String,
  web? : Bool = false,
) -> (Array[String], String?) {
  let cache = if web { self.web_cache } else { self.sys_cache }
  match cache.get(path) {
    Some(r) => return (r.0.copy(), r.1)
    None => ()
  }
  let posix_path = path
  let root : String? = if web {
    if posix_path.has_prefix("/") {
      Some("/")
    } else if posix_path.has_prefix("./") {
      Some("./")
    } else {
      None
    }
  } else if self.is_root(posix_path) {
    if posix_path.has_prefix("//") {
      Some("//")
    } else {
      Some("/")
    }
  } else if posix_path.has_prefix("./") {
    Some("./")
  } else {
    None
  }
  let rest = match root {
    Some(r) => @rb.from(posix_path, r.length())
    None => posix_path
  }
  let segments = @rb.split(rest, "/").filter(s => s != ".")
  cache[path] = (segments, root)
  (segments.copy(), root)
}

///|
fn join_path(segments : Array[String], root : String?) -> String {
  match root {
    Some(r) => r + segments.join("/")
    None => segments.join("/")
  }
}

///|
/// Resolves a system path (Ruby `system_path`), recovering from jail
/// violations with a warning unless `recover` is false.
pub fn PathResolver::system_path(
  self : PathResolver,
  target : String?,
  start? : String,
  jail? : String,
  target_name? : String = "path",
  recover? : Bool = true,
) -> String raise SecurityError {
  match jail {
    Some(j) =>
      if !self.is_root(j) {
        raise SecurityError("Jail is not an absolute path: \{j}")
      }
    None => ()
  }
  let mut target_segments : Array[String] = []
  match target {
    Some(t) =>
      if self.is_root(t) {
        let target_path = self.expand_path(t)
        match jail {
          Some(j) if self.descends_from(target_path, j) is None => {
            if !recover {
              raise SecurityError(
                "\{target_name} \{t} is outside of jail: \{j} (disallowed in safe mode)",
              )
            }
            log_warn(
              "\{target_name} is outside of jail; recovering automatically",
            )
            let (ts, _) = self.partition_path(target_path)
            let (js, jr) = self.partition_path(j)
            return join_path(js + ts, jr)
          }
          _ => return target_path
        }
      } else {
        target_segments = self.partition_path(t).0
      }
    None => ()
  }
  let mut start = start
  if target_segments.is_empty() {
    match start {
      None | Some("") =>
        return match jail {
          Some(j) => j
          None => self.working_dir
        }
      Some(s) =>
        if self.is_root(s) {
          if jail is None {
            return self.expand_path(s)
          }
        } else {
          target_segments = self.partition_path(s).0
          start = Some(jail.unwrap_or(self.working_dir))
        }
    }
  } else {
    match start {
      None | Some("") => start = Some(jail.unwrap_or(self.working_dir))
      Some(s) =>
        if !self.is_root(s) {
          start = Some(
            "\{@rb.chomp_suffix(jail.unwrap_or(self.working_dir), "/")}/\{s}",
          )
        }
    }
  }
  let start = start.unwrap_or("")
  let recheck = match jail {
    Some(j) => self.descends_from(start, j) is None
    None => false
  }
  let (start_segments, jail_root) = self.partition_path(start)
  let mut resolved_segments = start_segments + target_segments
  let mut jail_segments : Array[String]? = None
  if resolved_segments.contains("..") {
    let unresolved = resolved_segments
    resolved_segments = []
    match jail {
      Some(j) => {
        let js = self.partition_path(j).0
        jail_segments = Some(js)
        let mut warned = false
        for seg in unresolved {
          if seg == ".." {
            if resolved_segments.length() > js.length() {
              resolved_segments.pop() |> ignore
            } else if recover {
              if !warned {
                log_warn(
                  "\{target_name} has illegal reference to ancestor of jail; recovering automatically",
                )
                warned = true
              }
            } else {
              raise SecurityError(
                "\{target_name} \{target.unwrap_or("")} refers to location outside jail: \{j} (disallowed in safe mode)",
              )
            }
          } else {
            resolved_segments.push(seg)
          }
        }
      }
      None =>
        for seg in unresolved {
          if seg == ".." {
            resolved_segments.pop() |> ignore
          } else {
            resolved_segments.push(seg)
          }
        }
    }
  }
  if recheck {
    let j = jail.unwrap()
    let target_path = join_path(resolved_segments, jail_root)
    if self.descends_from(target_path, j) is Some(_) {
      target_path
    } else if recover {
      log_warn("\{target_name} is outside of jail; recovering automatically")
      let js = match jail_segments {
        Some(js) => js
        None => self.partition_path(j).0
      }
      join_path(js + target_segments, jail_root)
    } else {
      raise SecurityError(
        "\{target_name} \{target.unwrap_or("")} is outside of jail: \{j} (disallowed in safe mode)",
      )
    }
  } else {
    join_path(resolved_segments, jail_root)
  }
}

///|
/// Resolves a web path (Ruby `web_path`).
pub fn PathResolver::web_path(
  self : PathResolver,
  target : String,
  start? : String,
) -> String {
  let mut target = target
  let mut uri_prefix : String? = None
  match start {
    Some(s) if s != "" && !self.is_web_root(target) => {
      let combined = "\{s}\{if s.has_suffix("/") { "" } else { "/" }}\{target}"
      if combined.contains(":") {
        match uri_sniff_rx.find(combined) {
          Some(m) => {
            let matched = m.matched()
            target = @rb.from(combined, matched.length())
            uri_prefix = Some(matched)
          }
          None => target = combined
        }
      } else {
        target = combined
      }
    }
    _ => ()
  }
  let (segments, root) = self.partition_path(target, web=true)
  let resolved = []
  for seg in segments {
    if seg == ".." {
      if resolved.is_empty() {
        match root {
          Some(r) if r != "./" => ()
          _ => resolved.push(seg)
        }
      } else if resolved[resolved.length() - 1] == ".." {
        resolved.push(seg)
      } else {
        resolved.pop() |> ignore
      }
    } else {
      resolved.push(seg)
    }
  }
  let mut resolved_path = join_path(resolved, root)
  if resolved_path.contains(" ") {
    resolved_path = resolved_path.replace_all(old=" ", new="%20")
  }
  match uri_prefix {
    Some(p) => p + resolved_path
    None => resolved_path
  }
}
