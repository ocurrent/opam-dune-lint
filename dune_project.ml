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

  (*  We use [tmp_dir] so that "--only-packages" doesn't invalidate the existing build. *)
  let dune_external_lib_deps ~tmp_dir ~pkg ~target =
    let tmp_dir = Fpath.to_string tmp_dir in
    Bos.Cmd.(v "dune" % "build" % "--external-lib-deps=sexp" % "--only-packages" % pkg
             % "--build-dir" % tmp_dir
             % target)

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

  let merge_dep ~pkg ~path acc = function
    | Sexplib.Sexp.List (Atom lib :: _) ->
      if Astring.String.take ~sat:((<>) '.') lib <> pkg then
        let dirs = Libraries.find_opt lib acc |> Option.value ~default:Dir_set.empty in
        Libraries.add lib (Dir_set.add path dirs) acc
      else
        acc
    | x -> Fmt.failwith "Bad output from 'dune external-lib-deps': %a" Sexplib.Sexp.pp_hum x

  (* Dune sometimes gives made-up paths. Search upwards until we find a real directory. *)
  let rec find_real_dir = function
    | ".ppx" -> "(ppx)"
    | path ->
      match Unix.stat path with
      | _ -> path
      | exception Unix.Unix_error(Unix.ENOENT, _, _) ->
        let parent = Filename.dirname path in
        if parent <> path then find_real_dir parent
        else path

  let merge_dir ~pkg ~dir_types acc = function
    | Sexplib.Sexp.List [Atom path; List deps] ->
      let path = find_real_dir path in
      if should_use_dir ~dir_types path then (
        (* Fmt.pr "Process %S@." path; *)
        List.fold_left (merge_dep ~pkg ~path) acc deps
      ) else (
        (* Fmt.pr "Skip %S@." path; *)
        acc
      )
    | x -> Fmt.failwith "Bad output from 'dune external-lib-deps': %a" Sexplib.Sexp.pp_hum x

  let parse ~pkg = function
    | Sexplib.Sexp.List [Atom _ctx; List dirs] ->
      let dir_types = Hashtbl.create 10 in
      List.fold_left (merge_dir ~pkg ~dir_types) Libraries.empty dirs
    | x -> Fmt.failwith "Bad output from 'dune external-lib-deps': %a" Sexplib.Sexp.pp_hum x

  (* Get the ocamlfind dependencies of [pkg]. *)
  let get_external_lib_deps ~pkg ~target : t =
    Bos.OS.Dir.with_tmp "opam-dune-lint-%s" (fun tmp_dir () ->
        Bos.OS.Cmd.run_out (dune_external_lib_deps ~tmp_dir ~pkg ~target)
        |> Bos.OS.Cmd.to_string
        |> or_die
      ) ()
    |> or_die
    |> String.trim
    |> function
    | "" -> Libraries.empty
    | sexp -> parse ~pkg (Sexplib.Sexp.of_string sexp)
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
