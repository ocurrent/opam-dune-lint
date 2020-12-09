open OpamTypes

val classify : filtered_formula -> [`Build | `Test] OpamPackage.Name.Map.t

val update_depends :
  filtered_formula ->
  [< `Add_build_dep of package
  | `Add_test_dep of package
  | `Add_with_test of name
  | `Remove_with_test of name ] ->
  filtered_formula
