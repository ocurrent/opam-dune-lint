open OpamTypes

let with_test = OpamVariable.of_string "with-test"

(* Before: "foo" {with-test}
   After:  "foo"
 *)
let rec remove_with_test : filter -> filter = function
  | FIdent ([], var, None) when OpamVariable.to_string var = "with-test" -> FBool true
  | FBool _ | FString _ | FIdent _ | FDefined _ | FUndef _ | FNot _ | FOr _ | FOp _ as x -> x
  | FAnd (x, y) -> FAnd (remove_with_test x, remove_with_test y)

let formula_of_filter = function
  | FBool true -> Empty
  | expr -> Atom (Filter expr)

let map_filter f = OpamFormula.map (function
    | Constraint x -> Atom (Constraint x)
    | Filter x -> formula_of_filter (f x)
  )

let apply_with_test_change (formula : filter filter_or_constraint OpamFormula.formula) = function
  | `Remove_with_test _name -> map_filter remove_with_test formula
  | `Add_with_test _name ->
    OpamFormula.ands [
      formula;
      formula_of_filter (FIdent ([], with_test, None))
    ]

let update_depends (depends : filtered_formula) = function
  | `Add_build_dep dep ->
    let expr = OpamFormula.Atom (Constraint (`Geq, FString (OpamPackage.version_to_string dep))) in
    OpamFormula.And (depends, OpamFormula.Atom (OpamPackage.name dep, expr))
  | `Add_test_dep dep ->
    let expr = OpamFormula.ands [
        OpamFormula.Atom (Constraint (`Geq, FString (OpamPackage.version_to_string dep)));
        OpamFormula.Atom (Filter (FIdent ([], with_test, None)));
      ]
    in
    OpamFormula.ands [depends; OpamFormula.Atom (OpamPackage.name dep, expr)]
  | `Remove_with_test name | `Add_with_test name as change ->
    let update (name2, formula) =
      if name <> name2 then OpamFormula.Atom (name2, formula)
      else OpamFormula.Atom (name, apply_with_test_change formula change)
    in
    OpamFormula.map update depends

let rec flatten : _ OpamFormula.formula -> _ list = function
  | Empty -> []
  | Atom (name, f) -> [(OpamPackage.Name.to_string name, f)]
  | Block x -> flatten x
  | And (x, y) -> flatten x @ flatten y
  | Or (x, y) -> flatten x @ flatten y

(* with-test dependencies are not available in the plain build environment. *)
let build_env x =
  match OpamVariable.Full.to_string x with
  | "with-test" -> Some (OpamTypes.B false)
  | _ -> None

let available_in_build_env =
  let open OpamTypes in function
  | Filter f -> OpamFilter.eval_to_bool ~default:true build_env f
  | Constraint _ -> true

let classify deps : [`Build | `Test] OpamPackage.Name.Map.t =
  flatten deps
  |> List.fold_left (fun acc (name, formula) ->
      let ty = if OpamFormula.eval available_in_build_env formula then `Build else `Test in
      let update x = match x, ty with
        | `Build, `Build | `Test, `Test -> x
        | `Test, `Build | `Build, `Test -> `Build
      in
      OpamPackage.Name.Map.update (OpamPackage.Name.of_string name) update ty acc
    ) OpamPackage.Name.Map.empty
