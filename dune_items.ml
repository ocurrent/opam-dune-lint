open Types

module Describe_external_lib = struct
  module Kind = struct
    type t = Required | Optional

    let merge = function
      | Required,_ | _, Required -> Required
      | Optional,Optional -> Optional

    let is_required = function
      | Required -> true
      | Optional -> false
  end

  type item =
    {
      name: string;
      package: string option;
      external_deps : (string * Kind.t) list;
      internal_deps : (string * Kind.t) list;
      source_dir: string;
      extensions: string list
    }

  let dump_item =
    {
      name = "";
      package = None;
      external_deps = [];
      internal_deps = [];
      source_dir = "";
      extensions = []
    }

  type t = Lib of item | Exe of item | Test of item

  let get_item = function
    | Lib item | Exe item | Test item -> item

  let is_exe_item = function
    | Exe _ -> true | _ -> false

  let is_lib_item = function
    | Lib _ -> true | _ -> false

  let string_of_atom = function
    | Sexp.Atom s -> s
    | s -> Fmt.failwith "%s is an atom" (Sexp.to_string s)

  let string_of_list_dep_sexp = function
    | Sexp.List [Atom name; Atom kind] ->
      if String.equal "required" kind then
        (name, Kind.Required)
      else
        (name, Kind.Optional)
    | s -> Fmt.failwith "%s is not 'List[Atom _; Atom _]'" (Sexp.to_string s)

  let decode_item sexps =
    let items =
      List.fold_left (fun items sexps ->
        match sexps with
        | Sexp.List [Atom "names"; List sexps] ->
          List.map (fun name -> {dump_item with name = name}) (List.map string_of_atom sexps)
        | _ -> items) [] sexps
    in
    List.fold_left (fun items sexps ->
        match sexps with
        | Sexp.List [Atom "names"; List _] -> items
        | Sexp.List [Atom "package"; List [Atom p] ] ->
          List.map (fun item -> {item with package = Some p}) items
        | Sexp.List [Atom "package"; List [] ] ->
          List.map (fun item -> {item with package = None}) items
        | Sexp.List [Atom "source_dir"; Atom s] ->
          List.map (fun item -> {item with source_dir = s}) items
        | Sexp.List [Atom "extensions" ; List sexps] ->
          List.map (fun item -> {item with extensions = List.map string_of_atom sexps}) items
        | Sexp.List [Atom "external_deps" ; List sexps] ->
          List.map (fun item ->
              {item with external_deps = List.map string_of_list_dep_sexp sexps}) items
        | Sexp.List [Atom "internal_deps" ; List sexps] ->
          List.map (fun item ->
              {item with internal_deps = List.map string_of_list_dep_sexp sexps}) items
        | s -> Fmt.failwith "%s is not a good format decoding an item" (Sexp.to_string s)
      ) items sexps

  let decode_items sexps : t list =
    sexps
    |> List.concat_map (function
      | Sexp.List [Atom "library"; List sexps] -> decode_item sexps |> List.map (fun item -> Lib item)
      | Sexp.List [Atom "tests"; List sexps] -> decode_item sexps |> List.map (fun item -> Test item)
      | Sexp.List [Atom "executables"; List sexps] -> decode_item sexps |> List.map (fun item -> Exe item)
      | s -> Fmt.failwith "%s is not a good format decoding items" (Sexp.to_string s))

  let describe_extern_of_sexp : Sexp.t -> t list = function
    | Sexp.List [Atom _ctx; List sexps] -> decode_items sexps
    | _ -> Fmt.failwith "Invalid format"

end

module Describe_entries = struct

  type item = {
    source_dir: string;
    bin_name: string;
    kind: string;
    dst: string;
    section: string;
    optional: string;
    package: string
  }

  let dump_item = {
    source_dir = "";
    bin_name = "";
    kind = "";
    dst = "";
    section = "";
    optional = "";
    package = ""
  }

  type entry = Bin of item | Other of item

  type t = string * entry list

  let string_of_atom = function
    | Sexp.Atom s -> s
    | s -> Fmt.failwith "%s is an atom" (Sexp.to_string s)

  (* With "default/lib/bin.exe" or "default/lib/bin.bc.js" gives bin, it gives "bin.exe" *)
  let bin_name s =
    Astring.String.cut ~sep:"/" ~rev:true s
    |> Option.map snd |> Option.get

  (* With "default/lib/bin.exe", it gives "default/lib" *)
  let source_dir s =
    Astring.String.cut ~sep:"/" ~rev:true s
    |> Option.map fst |> Option.map (Astring.String.cut ~sep:"/" ~rev:false) |> Option.join |> Option.map snd
    |> function None -> "." | Some dir -> dir

  let decode_item sexps =
    List.fold_left (fun item sexps ->
        match sexps with
        | Sexp.List [Atom "src"; List [_; Atom p] ] ->
          {item with source_dir = source_dir p; bin_name = bin_name p}
        | Sexp.List [Atom "kind"; Atom p ]    -> {item with kind = p}
        | Sexp.List [Atom "dst"; Atom p ]     -> {item with dst = p}
        | Sexp.List [Atom "section"; Atom p ] -> {item with section = p}
        | Sexp.List [Atom "optional"; Atom p ] -> {item with optional = p}
        | s -> Fmt.failwith "%s is not a good format decoding an item" (Sexp.to_string s)
      ) dump_item sexps
    |> (fun item -> match item.section with "BIN" -> Bin item | _ -> Other item)

  let decode_items : Sexp.t list -> entry list =
    List.filter_map (function
        | Sexp.List [List [Atom "source"; List [Atom "User" ; _ ]]; List [Atom "entry"; List sexps]] -> Some (decode_item sexps)
        | Sexp.List [List [Atom "entry"; List sexps]; List [Atom "source"; Atom "User"]] -> Some (decode_item sexps)
        | Sexp.List [List [Atom "source"; Atom "Dune"]; List _ ] -> None
        | s -> Fmt.failwith "%s is not a good format decoding items" (Sexp.to_string s))

  let decode_entries : Sexp.t -> t = function
    | Sexp.List [Atom package; List sexps] -> (package,decode_items sexps)
    | _ -> Fmt.failwith "Invalid format"

  let entries_of_sexp : Sexp.t -> t list = function
    | Sexp.List sexps ->
      sexps
      |> List.map (fun x -> decode_entries x |> (fun (package, entries) ->
          (package, List.map (function
               | Bin item   -> Bin {item with package = package}
               | Other item -> Other {item with package = package}) entries)))
    | _ -> Fmt.failwith "Invalid format"

  let items_bin_of_entries describe_entries =
    List.concat_map snd describe_entries
    |> List.filter_map (fun d_item ->
        d_item
        |> (function Bin item -> Some (item.bin_name,item) | Other _ -> None))
    |> List.to_seq |> Item_map.of_seq
end

module Describe_opam_files = struct

  (** String representing an opam file name eg. foo.opam *)
  type opam_file = string

  (** Representing the name and the content of an opam file *)
  type t = (opam_file * OpamFile.OPAM.t ) list

  (** Decode opam files from the command "dune describe opam-files" output. *)
  let opam_files_of_sexp = function
    | Sexp.List sexps ->
      sexps
      |> List.map (function
          | Sexp.List [Atom opam_file; Atom opam_content] ->
            (opam_file, OpamFile.OPAM.read_from_string opam_content)
          | s -> Fmt.failwith "%s is not a good format decoding an item" (Sexp.to_string s))
    | s -> Fmt.failwith "%s is not a good format decoding items" (Sexp.to_string s)

end
