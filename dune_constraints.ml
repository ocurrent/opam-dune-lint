(* This source code is comming from https://github.com/ocurrent/opam-repo-ci/blob/master/lib/lint.ml
 * with a slight modification *)

type error =
  | DuneConstraintMissing
  | DuneIsBuild
  | BadDuneConstraint of string * string

let is_dune name =
    OpamPackage.Name.equal name (OpamPackage.Name.of_string "dune")

let get_dune_constraint opam =
  let get_max = function
    | None, None -> None
    | Some x, None -> Some x
    | None, Some x -> Some x
    | Some x, Some y when OpamVersionCompare.compare x y >= 0 -> Some x
    | Some _, Some y -> Some y
  in
  let get_min = function
    | None, None | Some _, None | None, Some _ -> None
    | Some x, Some y when OpamVersionCompare.compare x y >= 0 -> Some y
    | Some x, Some _ -> Some x
  in
  let is_build = ref false in
  let rec get_lower_bound = function
    | OpamFormula.Atom (OpamTypes.Constraint ((`Gt | `Geq), OpamTypes.FString version)) -> Some version
    | Atom (Filter (FIdent (_, var, _))) when String.equal (OpamVariable.to_string var) "build" -> is_build := true; None (* TODO: remove this hack *)
    | Empty | Atom (Filter _) | Atom (Constraint _) -> None
    | Block x -> get_lower_bound x
    | And (x, y) -> get_max (get_lower_bound x, get_lower_bound y)
    | Or (x, y) -> get_min (get_lower_bound x, get_lower_bound y)
  in
  let rec aux = function
    | OpamFormula.Atom (pkg, constr) ->
      if is_dune pkg then
        let v = get_lower_bound constr in
        Some (Option.value ~default:"1.0" v)
      else
        None
    | Empty -> None
    | Block x -> aux x
    | And (x, y) -> get_max (aux x, aux y)
    | Or (x, y) -> get_min (aux x, aux y)
  in
  (!is_build, aux opam.OpamFile.OPAM.depends)

let check_dune_constraints ~errors ~dune_version pkg_name opam =
  let is_build, dune_constraint = get_dune_constraint opam in
  let errors =
    match dune_constraint with
    | None ->
      if is_dune pkg_name then
        errors
      else
        (pkg_name, DuneConstraintMissing) :: errors
    | Some dep ->
      if OpamVersionCompare.compare dep dune_version >= 0 then
        errors
      else
        (pkg_name, BadDuneConstraint (dep, dune_version)) :: errors
  in
  if is_build then (pkg_name, DuneIsBuild) :: errors else errors

let print_msg_of_errors =
    List.iter (fun (package, err) ->
      let pkg = OpamPackage.Name.to_string package in
      match err with
      | DuneConstraintMissing ->
          Fmt.epr "Warning in %s: The package has a dune-project file but no explicit dependency on dune was found.@." pkg
      | DuneIsBuild ->
          Fmt.epr "Warning in %s: The package tagged dune as a build dependency. \
                   Due to a bug in dune (https://github.com/ocaml/dune/issues/2147) this should never be the case. \
                   Please remove the {build} tag from its filter.@."
            pkg
      | BadDuneConstraint (dep, ver) ->
          Fmt.failwith
            "Error in %s: Your dune-project file indicates that this package requires at least dune %s \
             but your opam file only requires dune >= %s. Please check which requirement is the right one, and fix the other."
            pkg ver dep

    )
