open Types

type check = Added | Deleted | Changed

let string_of_check = function
  | Added -> "added"
  | Deleted -> "deleted"
  | Changed -> "changed"

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let dune_describe_opam_files = Bos.Cmd.(v "dune" % "describe" % "opam-files")

let () =
  (* When run as a plugin, opam helpfully scrubs the environment.
     Get the settings back again. *)
  let env =
    Bos.Cmd.(v "opam" % "config" % "env" % "--sexp")
    |> Bos.OS.Cmd.run_out
    |> Bos.OS.Cmd.to_string
    |> or_die
    |> Sexplib.Sexp.of_string
  in
  match env with
  | Sexplib.Sexp.List vars ->
    vars |> List.iter (function
        | Sexplib.Sexp.List [Atom name; Atom value] -> Unix.putenv name value
        | x -> Fmt.epr "WARNING: bad sexp from opam config env: %a@." Sexplib.Sexp.pp_hum x
      )
  | x -> Fmt.epr "WARNING: bad sexp from opam config env: %a@." Sexplib.Sexp.pp_hum x

let get_libraries ~pkg ~target = Dune_project.Deps.get_external_lib_deps ~pkg ~target

let to_opam ~index lib =
  match Astring.String.take ~sat:((<>) '.') lib with
  | "threads" | "unix" | "str" | "compiler-libs"
  | "bigarray" | "dynlink" | "ocamldoc" | "stdlib"
  | "bytes" | "runtime_events" -> None          (* Distributed with OCaml *)
  | lib ->
    match Index.Owner.find_opt lib index with
    | Some pkg -> Some pkg
    | None ->
      Fmt.pr "WARNING: can't find opam package providing %S!@." lib;
      Some (OpamPackage.create (OpamPackage.Name.of_string lib) (OpamPackage.Version.of_string "0"))

(* Convert a map of (ocamlfind-library -> hints) to a map of (opam-package -> hints). *)
let to_opam_set ~index libs =
  Libraries.fold (fun lib dirs acc ->
      match to_opam ~index lib with
      | Some pkg -> OpamPackage.Map.update pkg (Dir_set.union dirs) Dir_set.empty acc
      | None -> acc
    ) libs OpamPackage.Map.empty

let get_opam_files () =
  Sys.readdir "."
  |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".opam")
  |> List.fold_left (fun acc path ->
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      Paths.add path opam acc
    ) Paths.empty

let updated_opam_files_content () =
  sexp dune_describe_opam_files
  |> Dune_items.Describe_opam_files.opam_files_of_sexp
  |> List.fold_left (fun acc (path,opam) -> Paths.add path opam acc) Paths.empty

let check_identical _path a b =
  match a, b with
  | Some a, Some b ->
    if OpamFile.OPAM.effectively_equal a b then None
    else Some Changed
  | Some _, None -> Some Deleted
  | None, Some _ -> Some Added
  | None, None -> assert false

let pp_problems f = function
  | [] -> Fmt.pf f " %a" Fmt.(styled `Green string) "OK"
  | problems -> Fmt.pf f " changes needed:@,%a" Fmt.(list ~sep:cut Change_with_hint.pp) problems

let display path (_opam, problems) =
  let pkg = Filename.chop_suffix path ".opam" in
  Fmt.pr "@[<v2>%a.opam:%a@]@."
    Fmt.(styled `Bold string) pkg
    pp_problems problems

let generate_report ~index ~opam pkg =
  let build = get_libraries ~pkg ~target:`Install |> to_opam_set ~index in
  let test = get_libraries ~pkg ~target:`Runtest |> to_opam_set ~index in
  let opam_deps =
    OpamFormula.And (OpamFile.OPAM.depends opam, OpamFile.OPAM.depopts opam)
    |> Formula.classify in
  let build_problems =
    OpamPackage.Map.to_seq build
    |> List.of_seq
    |> List.concat_map (fun (dep, hint) ->
        let dep_name = OpamPackage.name dep in
        match OpamPackage.Name.Map.find_opt dep_name opam_deps with
        | Some `Build -> []
        | Some `Test -> [`Remove_with_test dep_name, hint]
        | None -> [`Add_build_dep dep, hint]
      )
  in
  let test_problems =
    test
    |> OpamPackage.Map.to_seq
    |> List.of_seq
    |> List.concat_map (fun (dep, hint) ->
        if OpamPackage.Map.mem dep build then []
        else (
          let dep_name = OpamPackage.name dep in
          match OpamPackage.Name.Map.find_opt dep_name opam_deps with
          | Some `Test -> []
          | Some `Build -> [`Add_with_test dep_name, hint]
          | None -> [`Add_test_dep dep, hint]
        )
      )
  in
  build_problems @ test_problems

let update_opam_file path = function
  | (_, []) -> ()
  | (opam, changes) ->
    let depends = List.fold_left Formula.update_depends opam.OpamFile.OPAM.depends changes in
    let opam = OpamFile.OPAM.with_depends depends opam in
    let path = OpamFile.make (OpamFilename.raw (path)) in
    OpamFile.OPAM.write_with_preserved_format path opam;
    Fmt.pr "Wrote %S@." (OpamFile.to_string path)

let confirm_with_user () =
  if Unix.(isatty stdin) then (
    prerr_string "Write changes? [y] ";
    flush stderr;
    match input_line stdin |> String.lowercase_ascii with
    | "" | "y" | "yes" -> true
    | _ ->
      Fmt.pr "Aborted.@.";
      false
  ) else (
    Fmt.pr "Run with -f to apply changes in non-interactive mode.@.";
    false
  )

let write_file path content =
  let chan = open_out path in
  output_string chan content;
  flush chan;
  close_out chan

let main force dir =
  Sys.chdir dir;
  let index = Index.create () in
  let project = Dune_project.parse () in
  let old_opam_files = get_opam_files () in
  let packages = Dune_project.packages project in

  (* some dune project file has no package description
   * and avoid removing all the opam files *)
  if not (Paths.is_empty packages) then (
    old_opam_files |> Paths.iter (fun path _ -> if not (Paths.mem path packages) then Sys.remove path)
    (* prevent `dune describe opam-files` to fail when there is a opam file `*.opam`
     * that its package description is missing in dune-project file.
     * The error from dune will be:
     *   Error: This opam file doesn't have a corresponding (package ...) stanza in
     *   the dune-project file. Since you have at least one other (package ...) stanza
     *   in your dune-project file, you must a (package ...) stanza for each opam
     *   package in your project. *)
  );

  let opam_files_content = updated_opam_files_content () in
  let opam_files =
    opam_files_content
    |> Paths.mapi (fun path content ->
        let opamfile = Dune_items.Describe_opam_files.opamfile_of_content content in
        match Paths.find_opt path old_opam_files with
        | None -> opamfile
        | Some opam ->
          let depends = OpamFile.OPAM.depends opam in
          OpamFile.OPAM.with_depends depends opamfile)
  in
  if Paths.is_empty opam_files then failwith "No *.opam files found!";
  let stale_files = Paths.merge check_identical old_opam_files opam_files in
  stale_files |> Paths.iter (fun path msg ->
      (match msg with
       | Added   -> write_file path (Paths.find path opam_files_content)
       | Deleted -> () (* Already removed*)
       | Changed ->
         OpamFile.OPAM.write_with_preserved_format (OpamFile.make (OpamFilename.raw (path))) (Paths.find path opam_files)
      );
      Fmt.pr "%s: %s after its upgrade from 'dune describe opam-files'!@." path (string_of_check msg)
    );
  opam_files |> Paths.mapi (fun path opam ->
      (opam, generate_report ~index ~opam (Filename.chop_suffix path ".opam"))
    )
  |> fun report ->
  Paths.iter display report;
  if Paths.exists (fun _ (_, changes) -> List.exists Change_with_hint.includes_version changes) report then
    Fmt.pr "Note: version numbers are just suggestions based on the currently installed version.@.";
  let report = Paths.map (fun (opam, changes) -> opam, List.map Change_with_hint.remove_hint changes) report in
  let have_changes = Paths.exists (fun _ -> function (_, []) -> false | _ -> true) report in
  if have_changes then (
    if force || confirm_with_user () then (
      if Dune_project.generate_opam_enabled project then (
        project
        |> Dune_project.update report
        |> Dune_project.write_project_file;
        updated_opam_files_content () |> Paths.iter (fun path content -> write_file path content);
      ) else (
        Paths.iter update_opam_file report
      )
    ) else (
      exit 1
    )
  );
  let dune_version = Dune_project.version project in
  get_opam_files ()
  |> Paths.to_seq
  |> List.of_seq
  |> List.concat_map (fun (path, opam) ->
      let pkg_name = (OpamPackage.Name.of_string (Filename.chop_suffix path ".opam")) in
      Dune_constraints.check_dune_constraints ~errors:[] ~dune_version pkg_name opam)
  |> (fun errors ->
      Dune_constraints.print_msg_of_errors errors;
      List.find_opt (function (_, Dune_constraints.BadDuneConstraint _) -> true | _ -> false) errors
      |> function None -> () | Some _ -> exit 1
  );
  if not (Paths.is_empty stale_files) then exit 1

open Cmdliner

let dir =
  Arg.value @@
  Arg.pos 0 Arg.dir "." @@
  Arg.info
    ~doc:"Root of dune project to check"
    ~docv:"DIR"
    []

let force =
  Arg.value @@
  Arg.flag @@
  Arg.info
    ~doc:"Update files without confirmation"
    ["f"; "force"]

let cmd =
  let doc = "keep dune and opam files in sync" in
  let info = Cmd.info "opam-dune-lint" ~doc in
  let term = Term.(const main $ force $ dir) in
  Cmd.v info term

let () =
  Fmt_tty.setup_std_outputs ();
  exit @@ Cmd.eval cmd
