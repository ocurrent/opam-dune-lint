module Libraries = Set.Make(String)

module Packages = Map.Make(String)

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
  if lib = "findlib" then Some "ocamlfind"
  else match Findlib.package_directory lib with
    | dir -> Some (Filename.basename dir)
    | exception Fl_package_base.No_such_package _ -> None

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
      Packages.add name ty acc
    ) Packages.empty

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
      let test = get_libraries ~pkg ~target:"@runtest" |> Libraries.filter_map to_opam in
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      let opam_deps = OpamFile.OPAM.depends opam |> flatten |> classify in
      Fmt.pr "@[<v2>%a.opam:" Fmt.(styled `Bold string) pkg;
      let problems = ref 0 in
      let problem fmt =
        incr problems;
        Fmt.pr ("@," ^^ fmt)
      in
      build |> Libraries.iter (fun dep ->
          match Packages.find_opt dep opam_deps with
          | Some `Build -> ()
          | Some `Test -> problem "%S (remove {with-test})" dep
          | None -> problem "%S" dep
        );
      Libraries.diff test build |> Libraries.iter (fun dep ->
          match Packages.find_opt dep opam_deps with
          | Some `Test -> ()
          | Some `Build -> problem "%S {with-test} (missing {with-test} annotation)" dep
          | None -> problem "%S {with-test}" dep
        );
      if !problems = 0 then
        Fmt.pr "%a" Fmt.(styled `Green string) "OK";
      Fmt.pr "@]@.";
    )

let () =
  Fmt_tty.setup_std_outputs ();
  match Sys.argv with
  | [| _prog; dir |] -> scan ~dir
  | [| _prog |] -> scan ~dir:"."
  | _ -> failwith "usage: dune-opam-lint DIR"
