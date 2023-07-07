Create a simple dune project:

  $ cat > dune-project << EOF
  > (lang dune 2.8)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package")
  >  (depends
  >   (ocamlfind (>= 1.0))
  >   libfoo))
  > EOF

  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (public_name main)
  >  (modules main)
  >  (libraries findlib fmt))
  > (library
  >  (name lib)
  >  (package test)
  >  (modules lib)
  >  (libraries bos))
  > (test
  >  (package test)
  >  (name test)
  >  (modules test)
  >  (libraries bos opam-state))
  > EOF

  $ touch main.ml test.ml lib.ml
  $ dune build
  $ dune describe external-lib-deps
  (default
   ((executables
     ((names (main))
      (extensions (.exe))
      (package (test))
      (source_dir .)
      (external_deps
       ((findlib required)
        (fmt required)))
      (internal_deps ())))
    (library
     ((names (lib))
      (extensions ())
      (package (test))
      (source_dir .)
      (external_deps ((bos required)))
      (internal_deps ())))
    (tests
     ((names (test))
      (extensions
       (.bc .exe))
      (package (test))
      (source_dir .)
      (external_deps
       ((bos required)
        (opam-state required)))
      (internal_deps ())))))
  $ dune describe package-entries
  ((test
    (((source Dune)
      (entry
       ((src
         (In_build_dir default/META.test))
        (kind file)
        (dst META)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/.lib.objs/byte/lib.cmi))
        (kind file)
        (dst __private__/lib/.public_cmi/lib.cmi)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/.lib.objs/byte/lib.cmt))
        (kind file)
        (dst __private__/lib/.public_cmi/lib.cmt)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/lib.a))
        (kind file)
        (dst __private__/lib/lib.a)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/lib.cma))
        (kind file)
        (dst __private__/lib/lib.cma)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/.lib.objs/native/lib.cmx))
        (kind file)
        (dst __private__/lib/lib.cmx)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/lib.cmxa))
        (kind file)
        (dst __private__/lib/lib.cmxa)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/lib.ml))
        (kind file)
        (dst __private__/lib/lib.ml)
        (section LIB)
        (optional false))))
     ((source Dune)
      (entry
       ((src
         (In_build_dir default/test.dune-package))
        (kind file)
        (dst dune-package)
        (section LIB)
        (optional false))))
     ((source Dune)
      (entry
       ((src
         (In_build_dir default/test.opam))
        (kind file)
        (dst opam)
        (section LIB)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 6)
           (pos_bol 87)
           (pos_cnum 87)))
         (stop
          ((pos_lnum 10)
           (pos_bol 139)
           (pos_cnum 156))))))
      (entry
       ((src
         (In_build_dir default/lib.cmxs))
        (kind file)
        (dst __private__/lib/lib.cmxs)
        (section LIBEXEC)
        (optional false))))
     ((source
       (User
        ((pos_fname dune)
         (start
          ((pos_lnum 2)
           (pos_bol 12)
           (pos_cnum 19)))
         (stop
          ((pos_lnum 2)
           (pos_bol 12)
           (pos_cnum 23))))))
      (entry
       ((src
         (In_build_dir default/main.exe))
        (kind file)
        (dst main)
        (section BIN)
        (optional false)))))))
  $ dune describe opam-files
  ((test.opam
    "# This file is generated by dune, edit dune-project instead\nopam-version: \"2.0\"\nsynopsis: \"Test package\"\ndepends: [\n  \"dune\" {>= \"2.8\"}\n  \"ocamlfind\" {>= \"1.0\"}\n  \"libfoo\"\n  \"odoc\" {with-doc}\n]\nbuild: [\n  [\"dune\" \"subst\"] {dev}\n  [\n    \"dune\"\n    \"build\"\n    \"-p\"\n    name\n    \"-j\"\n    jobs\n    \"@install\"\n    \"@runtest\" {with-test}\n    \"@doc\" {with-doc}\n  ]\n]\n"))
