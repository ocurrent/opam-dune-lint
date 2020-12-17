module Paths = Map.Make(String)

module Libraries = Set.Make(String)

module Change = struct
  type t =
    [ `Remove_with_test of OpamPackage.Name.t
    | `Add_with_test of OpamPackage.Name.t
    | `Add_build_dep of OpamPackage.t
    | `Add_test_dep of OpamPackage.t ]

  let pp_name = Fmt.using OpamPackage.Name.to_string Fmt.(quote string)

  let version_to_string =
    if Sys.getenv_opt "OPAM_DUNE_LINT_TESTS" = Some "y" then Fun.const "1.0"
    else OpamPackage.version_to_string

  let includes_version = function
    | `Remove_with_test _
    | `Add_with_test _ -> false
    | `Add_build_dep _
    | `Add_test_dep _ -> true

  let pp f t =
    let change, hint =
      match t with
      | `Remove_with_test name -> Fmt.str "%a" pp_name name, "(remove {with-test})"
      | `Add_with_test name -> Fmt.str "%a {with-test}" pp_name name, "(missing {with-test} annotation)"
      | `Add_build_dep dep -> Fmt.str "%a {>= %s}" pp_name (OpamPackage.name dep) (version_to_string dep), ""
      | `Add_test_dep dep -> Fmt.str "%a {with-test & >= %s}" pp_name (OpamPackage.name dep) (version_to_string dep), ""
    in
    if hint = "" then
      Fmt.string f change
    else
      Fmt.pf f "%-30s %s" change hint
end
