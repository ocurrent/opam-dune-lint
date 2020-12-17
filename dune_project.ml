open Types

type t = Dune_lang.t list

let atom = Dune_lang.atom
let dune_and x y =  Dune_lang.(List [atom "and"; x; y])
let lower_bound v = Dune_lang.(List [atom ">="; atom (OpamPackage.Version.to_string v)])

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let parse () =
  Stdune.Path.Build.(set_build_dir (Kind.of_string (Sys.getcwd ())));
  let path = Stdune.Path.of_string "dune-project" in
  Dune_lang.Parser.load path ~mode:Dune_lang.Parser.Mode.Many
  |> List.map Dune_lang.Ast.remove_locs

let generate_opam_enabled =
  List.exists (function
      | Dune_lang.List [Dune_lang.Atom (A "generate_opam_files"); Atom (A v)] -> bool_of_string v
      | _ -> false
    )

(* ("foo" args) -> ("foo" (f args)) *)
let map_if name f = function
  | Dune_lang.List (Atom (A head) as x :: xs) when head = name ->
    Dune_lang.List (x :: f xs)
  | x -> x

(* [package_name xs] returns the value of the (name foo) item in [xs]. *)
let package_name =
  List.find_map (function
      | Dune_lang.List [Atom (A "name"); Atom (A name)] -> Some name
      | _ -> None
    ) 

let rec simplify_and = function
  | Dune_lang.List [Atom (A "and"); x] -> x
  | Dune_lang.List xs -> List (List.map simplify_and xs)
  | x -> x

(* (foo)         -> foo
   (foo (and x)) -> (foo x)
*)
let simplify = function
  | Dune_lang.List [Atom _ as x] -> x
  | Dune_lang.List xs -> List (List.map simplify_and xs)
  | x -> x

let rec remove_with_test = function
  | [] -> []
  | Dune_lang.Atom (A ":with-test") :: xs -> xs
  | List x :: xs -> List (remove_with_test x) :: remove_with_test xs
  | x :: xs -> x :: remove_with_test xs

let apply_change items = function
  | `Add_build_dep dep ->
    let item = Dune_lang.(List [atom (OpamPackage.name_to_string dep);
                                lower_bound (OpamPackage.version dep)]) in
    item :: items
  | `Add_test_dep dep ->
    let item = Dune_lang.(List [atom (OpamPackage.name_to_string dep);
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
        | Dune_lang.List [Atom (A name2) as a; expr] when name = name2 ->
          Dune_lang.List [a; dune_and (atom ":with-test") expr]
        | Atom (A name2) as a when name = name2 ->
          Dune_lang.List [a; atom ":with-test"]
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
      | Some (_opam, changes) -> List.map (map_if "depends" (apply_changes ~changes)) items
  in
  List.map (map_if "package" update_package) t

let write_project_file t =
  let path = "dune-project" in
  let ch = open_out path in
  let f = Format.formatter_of_out_channel ch in
  Fmt.pf f "@[<v>%a@]@." (Fmt.list ~sep:Fmt.cut (Fmt.using Dune_lang.pp Stdune.Pp.render_ignore_tags)) t;
  close_out ch;
  Fmt.pr "Wrote %S@." path

module Deps = struct
  type t = Dir_set.t Libraries.t

  (*  We use [tmp_dir] so that "--only-packages" doesn't invalidate the existing build. *)
  let dune_external_lib_deps ~tmp_dir ~pkg ~target =
    let tmp_dir = Fpath.to_string tmp_dir in
    Bos.Cmd.(v "dune" % "external-lib-deps" % "--only-packages" % pkg
             % "--build-dir" % tmp_dir
             % "--sexp" % "--unstable-by-dir"
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

  let merge_dep ~path acc = function
    | Sexplib.Sexp.List (Atom lib :: _) ->
      let dirs = Libraries.find_opt lib acc |> Option.value ~default:Dir_set.empty in
      Libraries.add lib (Dir_set.add path dirs) acc
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

  let merge_dir ~dir_types acc = function
    | Sexplib.Sexp.List [Atom path; List deps] ->
      let path = find_real_dir path in
      if should_use_dir ~dir_types path then (
        (* Fmt.pr "Process %S@." path; *)
        List.fold_left (merge_dep ~path) acc deps
      ) else (
        (* Fmt.pr "Skip %S@." path; *)
        acc
      )
    | x -> Fmt.failwith "Bad output from 'dune external-lib-deps': %a" Sexplib.Sexp.pp_hum x

  let parse = function
    | Sexplib.Sexp.List [Atom _ctx; List dirs] ->
      let dir_types = Hashtbl.create 10 in
      List.fold_left (merge_dir ~dir_types) Libraries.empty dirs
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
    | sexp -> parse (Sexplib.Sexp.of_string sexp)
end

module Csexp = struct
  type t =
    | Atom of string
    | List of t list
end

module Sexp = Dune_csexp.Csexp.Make(Csexp)
module Library_map = Map.Make(String)

open Csexp

type index = [`Internal | `External] Library_map.t

let rec field name = function
  | [] -> Fmt.failwith "Field %S is missing!" name
  | List [Atom n; v] :: _ when n = name -> v
  | _ :: xs -> field name xs

let field_atom name xs =
  match field name xs with
  | Atom a -> a
  | List _ -> Fmt.failwith "Expected %S to be an atom!" name

let field_bool name xs =
  bool_of_string (field_atom name xs)

let index_lib acc fields =
  let name = field_atom "name" fields in
  let local = if field_bool "local" fields then `Internal else `External in
  Library_map.add name local acc

let index_item acc = function
  | List [Atom "library"; List fields] -> index_lib acc fields
  | _ -> acc

let make_index = function
  | List libs -> List.fold_left index_item Library_map.empty libs
  | Atom _ -> failwith "Bad 'dune describe' output!"

let describe () =
  Bos.OS.Cmd.run_out (Bos.Cmd.(v "dune" % "describe" % "--format=csexp" % "--lang=0.1"))
  |> Bos.OS.Cmd.to_string
  |> or_die
  |> Sexp.parse_string
  |> function
  | Error (_, e) -> Fmt.failwith "Error parsing 'dune describe' output: %s" e
  | Ok x -> make_index x

let lookup = Library_map.find_opt
