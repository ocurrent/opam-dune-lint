open Types

type t = Sexp.t list

let atom s = Sexp.Atom s
let dune_and x y =  Sexp.(List [atom "and"; x; y])
let lower_bound v = Sexp.(List [atom ">="; atom (OpamPackage.Version.to_string v)])

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let parse () =
  Stdune.Path.Build.(set_build_dir (Stdune.Path.Outside_build_dir.of_string (Sys.getcwd ())));
  Sexp.input_sexps (open_in "dune-project")

let generate_opam_enabled =
  List.exists (function
      | Sexp.List [Sexp.Atom "generate_opam_files"; Atom v] -> bool_of_string v
      | _ -> false
    )

(* ("foo" args) -> ("foo" (f args)) *)
let map_if name f = function
  | Sexp.List (Atom head as x :: xs) when head = name ->
    Sexp.List (x :: f xs)
  | x -> x

(* (... ("foo" args) ...) -> (... ("foo" (f args)) ...)
   (...)                  -> (... ("foo" (f []  ))    )
*)
let rec update_or_create name f = function
  | Sexp.List (Atom head as x :: xs) :: rest when head = name ->
    Sexp.List (x :: f xs) :: rest
  | [] ->
    Sexp.List (atom name :: f []) :: []
  | head :: rest -> head :: update_or_create name f rest

(* [package_name xs] returns the value of the (name foo) item in [xs]. *)
let package_name =
  List.find_map (function
      | Sexp.List [Atom "name"; Atom name] -> Some name
      | _ -> None
    )

let rec simplify_and = function
  | Sexp.List [Atom "and"; x] -> x
  | Sexp.List xs -> List (List.map simplify_and xs)
  | x -> x

(* (foo)         -> foo
   (foo (and x)) -> (foo x)
*)
let simplify = function
  | Sexp.List [Atom _ as x] -> x
  | Sexp.List xs -> List (List.map simplify_and xs)
  | x -> x

let rec remove_with_test = function
  | [] -> []
  | Sexp.Atom ":with-test" :: xs -> xs
  | List x :: xs -> List (remove_with_test x) :: remove_with_test xs
  | x :: xs -> x :: remove_with_test xs

let apply_change items = function
  | `Add_build_dep dep ->
    let item = Sexp.(List [atom (OpamPackage.name_to_string dep);
                                lower_bound (OpamPackage.version dep)]) in
    item :: items
  | `Add_test_dep dep ->
    let item = Sexp.(List [atom (OpamPackage.name_to_string dep);
                                dune_and
                                  (lower_bound (OpamPackage.version dep))
                                  (atom ":with-test")
                               ])
    in
    item :: items
  | `Remove_with_test name ->
    List.map (map_if (OpamPackage.Name.to_string name) remove_with_test) items
    |> List.map simplify
  | `Add_with_test name ->
    let name = OpamPackage.Name.to_string name in
    items |> List.map (function
        | Sexp.List [Atom name2 as a; expr] when name = name2 ->
          Sexp.List [a; dune_and (atom ":with-test") expr]
        | Atom name2 as a when name = name2 ->
          Sexp.List [a; atom ":with-test"]
        | x -> x
      )

let apply_changes ~changes items =
  List.fold_left apply_change items changes

let update (changes:(_ * Change.t list) Paths.t) (t:t) =
  let update_package items =
    match package_name items with
    | None -> failwith "Missing 'name' in (package)!"
    | Some name ->
      match Paths.find_opt (name ^ ".opam") changes with
      | None -> items
      | Some (_opam, changes) -> update_or_create "depends" (apply_changes ~changes) items
  in
  List.map (map_if "package" update_package) t

let write_project_file t =
  let path = "dune-project" in
  let ch = open_out path in
  let f = Format.formatter_of_out_channel ch in
  Fmt.pf f "@[<v>%a@]@." (Fmt.list ~sep:Fmt.cut Sexp.pp) t;
  close_out ch;
  Fmt.pr "Wrote %S@." path

module Deps = struct
  type t = Dir_set.t Libraries.t

  let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

  let dune_external_lib_deps = Bos.Cmd.(v "dune" % "describe" % "external-lib-deps")

  let has_dune_subproject = function
    | "." | "" -> false
    | dir -> Sys.file_exists (Filename.concat dir "dune-project")

  let rec should_use_dir ~dir_types path =
    match Hashtbl.find_opt dir_types path with
    | Some x -> x
    | None ->
      let r =
        match Astring.String.cut ~sep:"/" ~rev:true path with
        | Some (parent, _) ->
          if should_use_dir ~dir_types parent then (
            not (has_dune_subproject path)
          ) else false
        | None ->
          not (has_dune_subproject path)
      in
      Hashtbl.add dir_types path r;
      r

  let get_dune_items dir_types ~sexp ~pkg ~target =
    Dune_items.items_of_sexp sexp
    |> List.filter (fun item ->
        match (item,target) with
        | Dune_items.Tests _, `Install -> false
        | Dune_items.Tests _, `Runtest -> true
        | _ , `Runtest -> false
        | _, `Install -> true)
    |> List.map Dune_items.get_item
    |> List.filter (fun (item:Dune_items.Item.t) -> should_use_dir ~dir_types item.source_dir)
    |> List.filter (fun (item:Dune_items.Item.t) -> Option.equal String.equal (Some pkg) item.package)

  let lib_deps sexp ~pkg ~target =
    get_dune_items (Hashtbl.create 10) ~sexp ~pkg ~target
    |> List.fold_left (fun acc (item:Dune_items.Item.t) ->
        List.map (fun dep -> (fst dep, item.source_dir)) item.external_deps @ acc) []
    |> List.fold_left (fun acc (lib,path) ->
        if Astring.String.take ~sat:((<>) '.') lib <> pkg then
          let dirs = Libraries.find_opt lib acc |> Option.value ~default:Dir_set.empty in
          Libraries.add lib (Dir_set.add path dirs) acc
        else
          acc) Libraries.empty

  let sexp =
    Bos.OS.Cmd.run_out (dune_external_lib_deps)
    |> Bos.OS.Cmd.to_string
    |> or_die
    |> String.trim
    |> (fun s ->
        try Sexp.of_string s with
        | Sexp.Parse_error _ as e -> Fmt.pr "Error parsing 'dune describe external-lib-deps' output:\n"; raise e)

  let get_external_lib_deps ~pkg ~target : t = sexp |> lib_deps ~pkg ~target

end

module Library_map = Map.Make(String)

type index = [`Internal | `External] Library_map.t

let rec field name = function
  | [] -> Fmt.failwith "Field %S is missing!" name
  | Sexp.List [Atom n; v] :: _ when n = name -> v
  | _ :: xs -> field name xs

let field_atom name xs =
  match field name xs with
  | Atom a -> a
  | Sexp.List _ -> Fmt.failwith "Expected %S to be an atom!" name

let field_bool name xs =
  bool_of_string (field_atom name xs)

let index_lib acc fields =
  let name = field_atom "name" fields in
  let local = if field_bool "local" fields then `Internal else `External in
  Library_map.add name local acc

let index_item acc = function
  | Sexp.List [Atom "library"; List fields] -> index_lib acc fields
  | _ -> acc

let make_index = function
  | Sexp.List libs -> List.fold_left index_item Library_map.empty libs
  | Atom _ -> failwith "Bad 'dune describe' output!"

let describe () =
  Bos.OS.Cmd.run_out (Bos.Cmd.(v "dune" % "describe" % "--format=csexp" % "--lang=0.1"))
  |> Bos.OS.Cmd.to_string
  |> or_die
  |> (fun s ->
      try Sexp.of_string s with
      | Sexp.Parse_error _ as e -> Fmt.pr "Error parsing 'dune describe' output:\n"; raise e)
  |> make_index

let lookup = Library_map.find_opt
