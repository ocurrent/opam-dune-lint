open Types

module Copy_rules = struct

  let sexp_of_file file =
    try Sexp.load_sexps file with
    | Sexp.Parse_error _ as e ->
      (Fmt.pr "Error parsing 'dune describe external-lib-deps' output:\n"; raise e)

  type t =
    {
      target: string;
      from_name: string;
      to_name: string;
      package: string
    }

  let dump_copy = {
    target = "";
    from_name = "";
    to_name = "";
    package = ""
  }

  let rules = Hashtbl.create 10

  let copy_rules_of_sexp sexps =
    let is_action_copy sexp =
      sexp
      |> (function
          | Sexp.List l -> l
          | _ -> Fmt.failwith "This is not a Sexp.List")
      |> (fun l -> if List.mem (Sexp.Atom "rule") l then Some l else None)
      |> Option.map (fun l ->
          List.exists (function
              | Sexp.List [ Atom "action"; List [ Atom "copy"; _]] -> true
              | _ -> false) l)
      |> Option.is_some
    in
    let copy_rule_of_sexp sexp =
      match sexp with
      | Sexp.List sexps ->
        List.fold_left (fun copy sexp ->
            match sexp with
            | Sexp.List [Atom "action"; List [ _; Atom f; Atom t]] -> {{copy with from_name = f } with to_name = t}
            | Sexp.List [Atom "deps"; List [_; Atom s]]            -> {copy with package = s}
            | Sexp.List [Atom "target"; Atom s ]                   -> { copy with target = s }
            | Sexp.Atom "rule"                                     -> copy
            | s -> Fmt.failwith "%s is not a good format decoding an item" (Sexp.to_string s)
          ) dump_copy sexps
      | s -> Fmt.failwith "%s is not a rule" (Sexp.to_string s)
    in
    sexps
    |> List.filter is_action_copy
    |> List.map copy_rule_of_sexp

  let copy_rules_map =
    List.fold_left (fun map copy -> Item_map.add copy.from_name copy map) Item_map.empty

  let get_copy_rules file =
    match Hashtbl.find_opt rules file with
    | None ->
      let copy_rules = copy_rules_of_sexp (sexp_of_file file) in
      Hashtbl.add rules file copy_rules; copy_rules
    | Some copy_rules -> copy_rules

  let rec find_dest_name ~name rules =
    match Item_map.find_opt name rules with
    | None   -> name
    | Some t -> find_dest_name ~name:t.to_name rules
end
