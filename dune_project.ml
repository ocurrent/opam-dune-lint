open Types

type t = Sexp.t list

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let atom s = Sexp.Atom s
let dune_and x y =  Sexp.(List [atom "and"; x; y])
let lower_bound v = Sexp.(List [atom ">="; atom (OpamPackage.Version.to_string v)])

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

let dune_format dune =
  Bos.OS.Cmd.(in_string dune |>  run_io Bos.Cmd.(v "dune" % "format-dune-file") |> out_string)
  |> Bos.OS.Cmd.success
  |> or_die

let write_project_file t =
  let path = "dune-project" in
  let ch = open_out path in
  let f = Format.formatter_of_out_channel ch in
  Fmt.str "%a" (Fmt.list ~sep:Fmt.cut Sexp.pp) t |> dune_format |> Fmt.pf f "%s";
  flush ch;
  close_out ch;
  Fmt.pr "Wrote %S@." path

module Deps = struct
  type t = Dir_set.t Libraries.t

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
    |> List.filter (fun (item:Dune_items.Item.t) ->
        if target = `Install then
          Option.equal String.equal (Some pkg) item.package
        else
          Option.equal String.equal (Some pkg) item.package || Option.is_none item.package)
          (* if an item has not package, we assume it's used for testing*)


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
