Create a simple dune project:

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
    "dune" {>= "1.0"}
    "fmt" {>= "1.0"}                         [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "./test.opam"

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
    "dune" {>= *}
    "fmt" {>= *}
    "bos" {>= *& with-test}
    "opam-state" {>= *& with-test}
  ]
