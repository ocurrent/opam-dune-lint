(lang dune 2.7)
(name dune-opam-lint)
(formatting disabled)

(generate_opam_files true)

(source (github talex5/dune-opam-lint))
(authors "talex5@gmail.com")
(maintainers "talex5@gmail.com")

(package
 (name dune-opam-lint)
 (synopsis "Ensure dune and opam dependencies are consistent")
 (depends
  ocamlfind
  bos
  fmt
  opam-format))