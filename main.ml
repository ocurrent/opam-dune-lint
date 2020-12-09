module Libraries = Set.Make(String)
module Paths = Map.Make(String)

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let () =
  Findlib.init ()

let index = Index.create ()

(* todo: we should probably select machine readable output.
   But passing --sexp just tells you to use unstable mode anyway.
   We use [tmp_dir] so that "--only-packages" doesn't invalidate the existing build. *)
let dune_external_lib_deps ~tmp_dir ~pkg ~target =
  let tmp_dir = Fpath.to_string tmp_dir in
  Bos.Cmd.(v "dune" % "external-lib-deps" % "--only-packages" % pkg % "--build-dir" % tmp_dir % target)

let dune_build_install =
  Bos.Cmd.(v "dune" % "build" %% (on (Unix.(isatty stderr)) (v "--display=progress")) % "@install")

(* Get the ocamlfind dependencies of [pkg]. *)
let get_libraries ~pkg ~target =
  Bos.OS.Dir.with_tmp "dune-opam-lint-%s" (fun tmp_dir () ->
      Bos.OS.Cmd.run_out (dune_external_lib_deps ~tmp_dir ~pkg ~target)
      |> Bos.OS.Cmd.to_lines
      |> or_die
    ) ()
  |> or_die
  |> List.filter_map (fun line ->
      match Astring.String.cut ~sep:" " line with
      | Some ("-", lib) -> Some lib
      | _ -> None
    )
  |> Libraries.of_list

let rec flatten : _ OpamFormula.formula -> _ list = function
  | Empty -> []
  | Atom (name, f) -> [(OpamPackage.Name.to_string name, f)]
  | Block x -> flatten x
  | And (x, y) -> flatten x @ flatten y
  | Or (x, y) -> flatten x @ flatten y

let to_opam lib =
  let lib = Astring.String.take ~sat:((<>) '.') lib in
  match Index.Owner.find_opt lib index with
  | Some pkg -> pkg
  | None ->
    Fmt.pr "WARNING: can't find opam package providing %S!" lib;
    OpamPackage.create (OpamPackage.Name.of_string lib) (OpamPackage.Version.of_string "0")

let to_opam_set libs =
  Libraries.fold (fun lib acc -> OpamPackage.Set.add (to_opam lib) acc) libs OpamPackage.Set.empty

(* with-test dependencies are not available in the plain build environment. *)
let build_env x =
  match OpamVariable.Full.to_string x with
  | "with-test" -> Some (OpamTypes.B false)
  | _ -> None

let available_in_build_env =
  let open OpamTypes in function
  | Filter f -> OpamFilter.eval_to_bool ~default:true build_env f
  | Constraint _ -> true

let classify =
  List.fold_left (fun acc (name, formula) ->
      let ty = if OpamFormula.eval available_in_build_env formula then `Build else `Test in
      OpamPackage.Name.Map.add (OpamPackage.Name.of_string name) ty acc
    ) OpamPackage.Name.Map.empty

let get_opam_files () =
  Sys.readdir "."
  |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".opam")
  |> List.fold_left (fun acc path ->
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      Paths.add path opam acc
    ) Paths.empty

let pp_name = Fmt.using OpamPackage.Name.to_string Fmt.(quote string)

let check_identical path a b =
  match a, b with
  | Some a, Some b ->
    if OpamFile.OPAM.effectively_equal a b then None
    else Fmt.failwith "%S changed after 'dune build @install'!" path
  | Some _, None -> Fmt.failwith "%S deleted by 'dune build @install'!" path
  | None, Some _ -> Fmt.failwith "%S was missing" path
  | None, None -> assert false

let pp_problem f = function
  | `Remove_with_test name -> Fmt.pf f "%a (remove {with-test})" pp_name name
  | `Add_with_test name -> Fmt.pf f "%a {with-test} (missing {with-test} annotation)" pp_name name
  | `Add_build_dep dep -> Fmt.pf f "%a {>= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep)
  | `Add_test_dep dep -> Fmt.pf f "%a {with-test & >= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep)

let pp_report f = function
  | [] -> Fmt.pf f " %a" Fmt.(styled `Green string) "OK"
  | problems -> Fmt.pf f "@,%a" Fmt.(list ~sep:cut pp_problem) problems

let display path report =
  let pkg = Filename.chop_suffix path ".opam" in
  Fmt.pr "@[<v2>%a.opam:%a@]@."
    Fmt.(styled `Bold string) pkg
    pp_report report

let generate_report ~opam pkg =
  let build = get_libraries ~pkg ~target:"@install" |> to_opam_set in
  let test = get_libraries ~pkg ~target:"@runtest" |> to_opam_set in
  let opam_deps = OpamFile.OPAM.depends opam |> flatten |> classify in
  let build_problems =
    OpamPackage.Set.to_seq build
    |> List.of_seq
    |> List.concat_map (fun dep ->
        let dep_name = OpamPackage.name dep in
        match OpamPackage.Name.Map.find_opt dep_name opam_deps with
        | Some `Build -> []
        | Some `Test -> [`Remove_with_test dep_name]
        | None -> [`Add_build_dep dep]
      )
  in
  let test_problems =
    OpamPackage.Set.diff test build
    |> OpamPackage.Set.to_seq
    |> List.of_seq
    |> List.concat_map (fun dep ->
        let dep_name = OpamPackage.name dep in
        match OpamPackage.Name.Map.find_opt dep_name opam_deps with
        | Some `Test -> []
        | Some `Build -> [`Add_with_test dep_name]
        | None -> [`Add_test_dep dep]
      )
  in
  build_problems @ test_problems

let scan ~dir =
  Sys.chdir dir;
  let old_opam_files = get_opam_files () in
  Bos.OS.Cmd.run dune_build_install |> or_die;
  let opam_files = get_opam_files () in
  if Paths.is_empty opam_files then failwith "No *.opam files found!";
  let _ : _ Paths.t = Paths.merge check_identical old_opam_files opam_files in
  opam_files |> Paths.mapi (fun path opam ->
      generate_report ~opam (Filename.chop_suffix path ".opam")
    )
  |> fun report ->
  Paths.iter display report;
  if Paths.exists (fun _ -> function [] -> false | _ -> true) report then exit 1

let () =
  Fmt_tty.setup_std_outputs ();
  try
    match Sys.argv with
    | [| _prog; dir |] -> scan ~dir
    | [| _prog |] -> scan ~dir:"."
    | _ -> failwith "usage: dune-opam-lint DIR"
  with Failure msg ->
    Fmt.epr "%s@." msg;
    exit 1
