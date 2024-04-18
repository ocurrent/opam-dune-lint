"dune describe opam-files" give an S-expression in which quoted string are escaped.
the string "%{" is escaped with `\` to gives "\%{". And OpamFile fails parsing this
output.


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
  >   ["dune" "build"  "--use-libev" "%{conf-libev:installed}%" ]
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
  opam-dune-lint: internal error, uncaught exception:
                  At ./<none>:5:35-5:35::
                  illegal escape sequence
                  
  [125]
