(lang dune 3.10)

(name opam-dune-lint)

(formatting disabled)

(generate_opam_files true)

(source
 (github ocurrent/opam-dune-lint))

(authors "talex5@gmail.com")

(maintainers "alpha@tarides.com" "Tim McGilchrist <timmcgil@gmail.com>")

(license ISC)

(cram enable)

(package
 (name opam-dune-lint)
 (synopsis "Ensure dune and opam dependencies are consistent")
 (description
  "opam-dune-lint checks that all ocamlfind libraries listed as dune dependencies have corresponding opam dependencies listed in the opam files. If not, it offers to add them (either to your opam files, or to your dune-project if you're generating your opam files from that).")
 (depends
  (fpath
   (>= 0.7.3))
  (astring
   (>= 0.8.5))
  (sexplib
   (>= v0.14.0))
  (cmdliner
   (>= 1.1.0))
  (stdune
   (>= 3.10.0))
  (ocaml
   (>= 4.08.0))
  (bos
   (>= 0.2.0))
  (fmt
   (>= 0.8.9))
  (opam-state
   (>= 2.1.0))
  opam-format))
