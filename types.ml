module Paths = Map.Make(String)

module Libraries = Set.Make(String)

module Change = struct
  type t =
    [ `Remove_with_test of OpamPackage.Name.t
    | `Add_with_test of OpamPackage.Name.t
    | `Add_build_dep of OpamPackage.t
    | `Add_test_dep of OpamPackage.t ]

  let pp_name = Fmt.using OpamPackage.Name.to_string Fmt.(quote string)

  let pp f = function
    | `Remove_with_test name -> Fmt.pf f "%a (remove {with-test})" pp_name name
    | `Add_with_test name -> Fmt.pf f "%a {with-test} (missing {with-test} annotation)" pp_name name
    | `Add_build_dep dep -> Fmt.pf f "%a {>= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep)
    | `Add_test_dep dep -> Fmt.pf f "%a {with-test & >= %s}" pp_name (OpamPackage.name dep) (OpamPackage.version_to_string dep)
end
