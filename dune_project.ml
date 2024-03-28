open Types

module Deps = Deps

type t = Sexp.t list

let atom s = Sexp.Atom s
let dune_and x y =  Sexp.(List [atom "and"; x; y])
let lower_bound v = Sexp.(List [atom ">="; atom (OpamPackage.Version.to_string v)])

let with_open_out fn file =
  let out_file = open_out file in
  let r = fn out_file in
  (flush out_file; close_out out_file; r)

(* Dune description stanza admit some quote starting like "\>" or "|>" which fails
   when using Sexplib to parse dune-project file.*)
let remove_quoted_string dune_project_s =
  let is_quote s =
    if String.length s > 2 then
      let quote = String.sub s 0 3 in
      String.equal quote "\"\\>" || String.equal quote "\"\\|"
    else false
  in
  let first_quote = ref false in
  dune_project_s
  (* |> Astring.String.cuts ~sep:"\n" *)
  |> List.filter_map (fun s ->
    let is_quote = is_quote @@ String.trim s in
    if is_quote && not (!first_quote) then
      (first_quote := true; Some "\"\"")
    else if is_quote then None
    else Some s)
  |> String.concat "\n"

let parse () =
  Stdune.Path.Build.(set_build_dir (Stdune.Path.Outside_build_dir.of_string (Sys.getcwd ())));
  Fpath.of_string "dune-project"
  |> Stdlib.Result.get_ok
  |> Bos.OS.File.read_lines
  |> Stdlib.Result.get_ok
  |> remove_quoted_string
  |> fun s -> String.concat " " ["(__dune_project__\n";s;"\n)"]
  |> Sexp.of_string |> function
  | Sexp.List ((Atom "__dune_project__")::sexps) -> sexps
  | _ -> Fmt.failwith "Fails to parse 'dune-project' file"

let generate_opam_enabled =
  List.exists (function
      | Sexp.List [Sexp.Atom "generate_opam_files"; Atom v] -> bool_of_string v
      | Sexp.List [Sexp.Atom "generate_opam_files"] -> true
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
      match Paths.find_opt (String.cat name ".opam") changes with
      | None -> items
      | Some (_opam, changes) -> update_or_create "depends" (apply_changes ~changes) items
  in
  List.map (map_if "package" update_package) t

let packages t =
  List.filter_map (function
      | Sexp.List ((Atom "package")::sexps) ->
        Option.some @@ List.filter_map (function
            | Sexp.List [Atom "name"; Atom name] -> Some (name ^ ".opam")
            | _ -> None) sexps
      | _ -> None) t
  |> List.flatten
  |> fun v -> List.combine v v
  |> List.to_seq
  |> Libraries.of_seq

let version t =
  List.find_map (function
      | Sexp.List [Atom "lang"; Atom "dune"; Atom version] -> Some version
      | _ -> None) t
  |> function
     | None -> Fmt.failwith "dune-project file without `(lang dune _)` stanza"
     | Some version -> version

let dune_format dune =
  Bos.OS.Cmd.(in_string dune |> run_io Bos.Cmd.(v "dune" % "format-dune-file") |> out_string)
  |> Bos.OS.Cmd.success
  |> or_die

let write_project_file t =
  with_open_out (fun ch ->
    let f = Format.formatter_of_out_channel ch in
    Fmt.str "%a" (Fmt.list ~sep:Fmt.cut Sexp.pp) t |> dune_format |> Fmt.pf f "%s";
  ) "dune-project";
  Fmt.pr "Wrote %S@." "dune-project"
