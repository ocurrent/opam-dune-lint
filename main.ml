open Types

let or_die = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

let () =
  Findlib.init ()

let dune_build_install =
  Bos.Cmd.(v "dune" % "build" %% (on (Unix.(isatty stderr)) (v "--display=progress")) % "@install")

let get_libraries ~pkg ~target =
  Dune_project.Deps.get_external_lib_deps ~pkg ~target
  |> Libraries.remove "threads"         (* META file is provided by ocamlfind, but dune doesn't need it *)
  |> Libraries.remove "str"
  |> Libraries.add "dune"               (* We always need dune *)

let to_opam ~index lib =
  let lib = Astring.String.take ~sat:((<>) '.') lib in
  match Index.Owner.find_opt lib index with
  | Some pkg -> pkg
  | None ->
    Fmt.pr "WARNING: can't find opam package providing %S!@." lib;
    OpamPackage.create (OpamPackage.Name.of_string lib) (OpamPackage.Version.of_string "0")

let to_opam_set ~project ~index libs =
  let libs = libs |> Libraries.filter (fun lib -> Dune_project.lookup lib project <> Some `Internal) in
  Libraries.fold (fun lib acc -> OpamPackage.Set.add (to_opam ~index lib) acc) libs OpamPackage.Set.empty

let get_opam_files () =
  Sys.readdir "."
  |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".opam")
  |> List.fold_left (fun acc path ->
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      Paths.add path opam acc
    ) Paths.empty

let check_identical _path a b =
  match a, b with
  | Some a, Some b ->
    if OpamFile.OPAM.effectively_equal a b then None
    else Some "changed"
  | Some _, None -> Some "deleted"
  | None, Some _ -> Some "added"
  | None, None -> assert false

let pp_problems f = function
  | [] -> Fmt.pf f " %a" Fmt.(styled `Green string) "OK"
  | problems -> Fmt.pf f " changes needed:@,%a" Fmt.(list ~sep:cut Change.pp) problems

let display path (_opam, problems) =
  let pkg = Filename.chop_suffix path ".opam" in
  Fmt.pr "@[<v2>%a.opam:%a@]@."
    Fmt.(styled `Bold string) pkg
    pp_problems problems

let generate_report ~project ~index ~opam pkg =
  let build = get_libraries ~pkg ~target:"@install" |> to_opam_set ~project ~index in
  let test = get_libraries ~pkg ~target:"@runtest" |> to_opam_set ~project ~index in
  let opam_deps = OpamFile.OPAM.depends opam |> Formula.classify in
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

let update_opam_file path = function
  | (_, []) -> ()
  | (opam, changes) ->
    let depends = List.fold_left Formula.update_depends opam.OpamFile.OPAM.depends changes in
    let opam = OpamFile.OPAM.with_depends depends opam in
    let path = OpamFile.make (OpamFilename.raw (path)) in
    OpamFile.OPAM.write path opam;
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

let main force dir =
  Sys.chdir dir;
  let index = Index.create () in
  let old_opam_files = get_opam_files () in
  Bos.OS.Cmd.run dune_build_install |> or_die;
  let opam_files = get_opam_files () in
  if Paths.is_empty opam_files then failwith "No *.opam files found!";
  let stale_files = Paths.merge check_identical old_opam_files opam_files in
  stale_files |> Paths.iter (fun path msg -> Fmt.pr "%s: %s after 'dune build @install'!@." path msg);
  let project = Dune_project.describe () in
  opam_files |> Paths.mapi (fun path opam ->
      (opam, generate_report ~project ~index ~opam (Filename.chop_suffix path ".opam"))
    )
  |> fun report ->
  Paths.iter display report;
  let have_changes = Paths.exists (fun _ -> function (_, []) -> false | _ -> true) report in
  if have_changes then (
    if force || confirm_with_user () then (
      let project = Dune_project.parse () in
      if Dune_project.generate_opam_enabled project then (
        project
        |> Dune_project.update report
        |> Dune_project.write_project_file;
        Bos.OS.Cmd.run dune_build_install |> or_die;
      ) else (
        Paths.iter update_opam_file report
      )
    )
  );
  if have_changes then exit 1;
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
  Term.(const main $ force $ dir),
  Term.info "opam-dune-lint" ~doc

let () =
  Fmt_tty.setup_std_outputs ();
  Term.exit (Term.eval cmd : unit Term.result)
