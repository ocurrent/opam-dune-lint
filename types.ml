module Paths = Map.Make(String)

module Libraries = Set.Make(String)

module Change = struct
  type t =
    [ `Remove_with_test of OpamPackage.Name.t
    | `Add_with_test of OpamPackage.Name.t
    | `Add_build_dep of OpamPackage.t
    | `Add_test_dep of OpamPackage.t ]

  let pp_name = Fmt.using OpamPackage.Name.to_string Fmt.(quote string)

  let pp f t =
    let change, hint =
      match t with
      | `Remove_with_test name -> Fmt.str "%a" pp_name name, "(remove {with-test})"
      | `Add_with_test name -> Fmt.str "%a {with-test}" pp_name name, "(missing {with-test} annotation)"
      | `Add_build_dep dep -> Fmt.str "%a {>= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep), ""
      | `Add_test_dep dep -> Fmt.str "%a {with-test & >= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep), ""
    in
    if hint = "" then
      Fmt.string f change
    else
      Fmt.pf f "%-30s %s" change hint
end
