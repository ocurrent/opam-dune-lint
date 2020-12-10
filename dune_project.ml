open Types

type t = Dune_lang.t list

let atom = Dune_lang.atom
let dune_and x y =  Dune_lang.(List [atom "and"; x; y])
let lower_bound v = Dune_lang.(List [atom ">="; atom (OpamPackage.Version.to_string v)])

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
