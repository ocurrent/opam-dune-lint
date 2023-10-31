Create a simple dune project: for testing opam-dune-lint, if dune constraint matches
the dune-project file


  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (package
  >  (name test)
  >  (synopsis "Test package"))
  > EOF

  $ cat > test.opam << EOF
  > # Preserve comments
  > opam-version: "2.0"
  > synopsis: "Test package"
  > build: [
  >   ["dune" "build"]
  > ]
  > depends: [
  >   "ocamlfind" {>= "1.0"}
  >   "libfoo"
  > ]
  > EOF

  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (public_name main)
  >  (modules main)
  >  (libraries findlib fmt))
  > (test
  >  (name test)
  >  (modules test)
  >  (libraries bos opam-state))
  > EOF

  $ touch main.ml test.ml
  $ dune build

Replace all version numbers with "1.0" to get predictable output.

  $ export OPAM_DUNE_LINT_TESTS=y

Check that the missing libraries get added:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "./test.opam"
  Warning in test: The package has a dune-project file but no explicit dependency on dune was found.

  $ cat test.opam | sed 's/= [^&)}]*/= */g'
  # Preserve comments
  opam-version: "2.0"
  synopsis: "Test package"
  build: [
    ["dune" "build"]
  ]
  depends: [
    "ocamlfind" {>= *}
    "libfoo"
    "fmt" {>= *}
    "bos" {>= *& with-test}
    "opam-state" {>= *& with-test}
  ]

  $ cat > test.opam << EOF
  > # Preserve comments
  > opam-version: "2.0"
  > synopsis: "Test package"
  > build: [
  >   ["dune" "build"]
  > ]
  > depends: [
  >   "ocamlfind" {>= "1.0"}
  >   "libfoo"
  >   "dune" {> "2.7" & build}
  > ]
  > EOF
  $ dune build

Check that the missing libraries get added:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "./test.opam"
  Warning in test: The package tagged dune as a build dependency. Due to a bug in dune (https://github.com/ocaml/dune/issues/2147) this should never be the case. Please remove the {build} tag from its filter.

  $ cat > test.opam << EOF
  > # Preserve comments
  > opam-version: "2.0"
  > synopsis: "Test package"
  > build: [
  >   ["dune" "build"]
  > ]
  > depends: [
  >   "ocamlfind" {>= "1.0"}
  >   "libfoo"
  >   "dune" {> "1.0" & build}
  > ]
  > EOF

  $ cat > test1.opam << EOF
  > # Preserve comments
  > opam-version: "2.0"
  > synopsis: "Test package"
  > build: [
  >   ["dune" "build"]
  > ]
  > depends: [
  >   "ocamlfind" {>= "1.0"}
  >   "libfoo"
  >   "dune" {> "1.0" & build}
  > ]
  > EOF

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (package
  >  (name test)
  >  (synopsis "Test package"))
  > (package
  >  (name test1)
  >  (synopsis "Test1 package"))
  > EOF

  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (public_name main)
  >  (package test)
  >  (modules main)
  >  (libraries findlib fmt))
  > (test
  >  (name test)
  >  (modules test)
  >  (libraries bos opam-state))
  > EOF
  $ dune build

Check that the missing libraries get added and print all errors before the exit:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  test1.opam: changes needed:
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "./test.opam"
  Wrote "./test1.opam"
  Warning in test: The package tagged dune as a build dependency. Due to a bug in dune (https://github.com/ocaml/dune/issues/2147) this should never be the case. Please remove the {build} tag from its filter.
  Error in test: Your dune-project file indicates that this package requires at least dune 2.7 but your opam file only requires dune >= 1.0. Please check which requirement is the right one, and fix the other.
  Warning in test1: The package tagged dune as a build dependency. Due to a bug in dune (https://github.com/ocaml/dune/issues/2147) this should never be the case. Please remove the {build} tag from its filter.
  Error in test1: Your dune-project file indicates that this package requires at least dune 2.7 but your opam file only requires dune >= 1.0. Please check which requirement is the right one, and fix the other.
  [1]
