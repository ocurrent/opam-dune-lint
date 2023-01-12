open Types

module Kind = struct
  type t = Required | Optional

  let merge x y =
    match (x, y) with
    | Required,_ | _, Required -> Required
    | _ -> Optional
end

module Item = struct
  type t =
    {
      names: string list;
      package: string option;
      external_deps : (string * Kind.t) list;
      source_dir: string
    }

  let dump =
    {
      names = [];
      package = None;
      external_deps = [];
      source_dir = ""
    }
end

open Sexp

type t = Lib of Item.t | Exes of Item.t | Tests of Item.t

let get_item = function
  | Lib item | Exes item | Tests item -> item


let string_of_atom =
  function
  | Atom s -> s
  | s -> Fmt.failwith "%s is an atom" (Sexp.to_string s)

let string_of_external_dep_sexp = function
  | List [Atom name; Atom kind] ->
    if String.equal "required" kind then
      (name, Kind.Required)
    else
      (name, Kind.Optional)
  | s -> Fmt.failwith "%s is not 'List[Atom _; Atom _]'" (Sexp.to_string s)

let decode_item =
  List.fold_left (fun (item:Item.t) sexps ->
      match sexps with
      | Sexp.List [Atom "name"; Atom n] -> {item with names = [n]}
      | Sexp.List [Atom "package"; Atom p] -> {item with package = Some p}
      | Sexp.List [Atom "source_dir"; Atom s] -> {item with source_dir = s}
      | Sexp.List [Atom "names"; List sexps] ->
         {item with names = List.map string_of_atom sexps}
      | Sexp.List [Atom "external_deps" ; List sexps] ->
        {item with external_deps = List.map string_of_external_dep_sexp sexps}
      | s -> Fmt.failwith "%s is not a good format decoding an item" (Sexp.to_string s)
    ) Item.dump

let extract_items : Sexp.t list -> t list =
  List.map (function
      | Sexp.List [Atom "library"; List sexps] -> Lib (decode_item sexps)
      | Sexp.List [Atom "tests"; List sexps]   -> Tests (decode_item sexps)
      | Sexp.List [Atom "executables"; List sexps] -> Exes (decode_item sexps)
      | s -> Fmt.failwith "%s is not a good format decoding items" (Sexp.to_string s))

let items_of_sexp : Sexp.t -> t list = function
  | Sexp.List [Atom _ctx; List sexps] -> extract_items sexps
  | _ -> Fmt.failwith "Invalid format"

let deps_merge deps_x deps_y =
  Libraries.merge
    (fun _ x y ->
       match (x,y) with
       | Some k1, Some k2 -> Some (Kind.merge k1 k2)
       | _ -> None) deps_x deps_y

let items_deps_by_dir =
  List.fold_left
    (fun dir_map (item:Item.t) ->
       match Dir_map.find_opt item.source_dir dir_map with
       | Some deps ->
         Dir_map.add
          item.source_dir
          (deps_merge deps (Libraries.of_seq (List.to_seq item.external_deps)))
          dir_map
       | None ->
         Dir_map.add
           item.source_dir
           (Libraries.of_seq (List.to_seq item.external_deps))
           dir_map)
    Dir_map.empty

let items_by_package =
  List.fold_left
    (fun dir_map (item:Item.t) ->
       match item.package with
       | Some package ->
         (match  Dir_map.find_opt package dir_map with
         | Some items -> Dir_map.add package (item::items) dir_map
         | None -> Dir_map.add item.source_dir [item] dir_map)
       | None -> dir_map)
    Dir_map.empty
