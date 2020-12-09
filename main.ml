module Libraries = Set.Make(String)

module Packages = Map.Make(String)

let () =
  Findlib.init ()

let index = Index.create ()

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
      let build = get_libraries ~pkg ~target:"@install" |> to_opam_set in
      let test = get_libraries ~pkg ~target:"@runtest" |> to_opam_set in
      let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw path)) in
      let opam_deps = OpamFile.OPAM.depends opam |> flatten |> classify in
      Fmt.pr "@[<v2>%a.opam:" Fmt.(styled `Bold string) pkg;
      let problems = ref 0 in
      let problem fmt =
        incr problems;
        Fmt.pr ("@," ^^ fmt)
      in
      build |> OpamPackage.Set.iter (fun dep ->
          let dep_name = OpamPackage.name_to_string dep in
          match Packages.find_opt dep_name opam_deps with
          | Some `Build -> ()
          | Some `Test -> problem "%S (remove {with-test})" dep_name
          | None -> problem "%S {>= %s}" dep_name (OpamPackage.version_to_string dep)
        );
      OpamPackage.Set.diff test build |> OpamPackage.Set.iter (fun dep ->
          let dep_name = OpamPackage.name_to_string dep in
          match Packages.find_opt dep_name opam_deps with
          | Some `Test -> ()
          | Some `Build -> problem "%S {with-test} (missing {with-test} annotation)" dep_name
          | None -> problem "%S {with-test & >= %s}" dep_name (OpamPackage.version_to_string dep)
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
