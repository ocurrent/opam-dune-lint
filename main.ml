module Libraries = Set.Make(String)

let () =
  Findlib.init ()

(* TODO: select machine readable output *)
let dune_external_lib_deps ~pkg ~target =
  Bos.Cmd.(v "dune" % "external-lib-deps" % "-p" % pkg % target)

(* Get the ocamlfind dependencies of [pkg]. *)
let get_libraries ~pkg ~target =
  Bos.OS.Cmd.run_out (dune_external_lib_deps ~pkg ~target)
  |> Bos.OS.Cmd.to_lines
  |> function
  | Error (`Msg m) -> failwith m
  | Ok lines ->
    lines
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
  match Findlib.package_directory lib with
  | dir -> Some (Filename.basename dir)
  | exception Fl_package_base.No_such_package _ -> None

let is_build_dep dep opam_deps = List.mem_assoc dep opam_deps

let scan ~dir =
  Sys.chdir dir;
  let packages =
    Sys.readdir "."
    |> Array.to_list
    |> List.filter_map (fun name -> Filename.chop_suffix_opt name ~suffix:".opam")
  in
  if packages = [] then failwith "No *.opam files found!";
  packages |> List.iter (fun pkg ->
      let path = pkg ^ ".opam" in
      let build = get_libraries ~pkg ~target:"@install" |> Libraries.filter_map to_opam in
      (* let test = get_libraries ~pkg ~target:"@runtest" in *)
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      let opam_deps = OpamFile.OPAM.depends opam |> flatten in
      let build_missing = build |> Libraries.filter (fun dune_build_dep -> not (is_build_dep dune_build_dep opam_deps)) in
      if Libraries.is_empty build_missing
      then Fmt.pr "%a.opam: %a@."
          Fmt.(styled `Bold string) pkg
          Fmt.(styled `Green string) "OK"
      else Fmt.pr "@[<v2>%a.opam is missing dependencies:@,%a@]@."
          Fmt.(styled `Bold string) pkg
          Fmt.(seq ~sep:cut (quote string)) (Libraries.to_seq build_missing)
    )

let () =
  Fmt_tty.setup_std_outputs ();
  match Sys.argv with
  | [| _prog; dir |] -> scan ~dir
  | [| _prog |] -> scan ~dir:"."
  | _ -> failwith "usage: dune-opam-lint DIR"
