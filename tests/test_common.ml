(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open IrminLwt
open OUnit

let cmp_opt fn x y =
  match x, y with
  | Some x, Some y -> fn x y
  | None  , None   -> true
  | Some _, None
  | None  , Some _ -> false

let printer_opt fn = function
  | None   -> "<none>"
  | Some v -> fn v

let assert_key_equal msg =
  assert_equal ~msg ~cmp:Key.equal ~printer:Key.pretty

let assert_key_opt_equal msg =
  assert_equal ~msg ~cmp:(cmp_opt Key.equal) ~printer:(printer_opt Key.pretty)

let assert_keys_equal msg =
  assert_equal ~msg ~cmp:Key.Set.equal ~printer:Key.Set.pretty

let assert_value_equal msg =
  assert_equal ~msg ~cmp:Value.equal ~printer:Value.pretty

let assert_value_opt_equal msg =
  assert_equal ~msg ~cmp:(cmp_opt Value.equal) ~printer:(printer_opt Value.pretty)

let assert_tags_equal msg =
  assert_equal ~msg ~cmp:Tag.Set.equal ~printer:Tag.Set.pretty

let test_db = "test-db"

let clean test_db =
  if Sys.file_exists test_db then
    let cmd = Printf.sprintf "rm -rf %s" test_db in
    let _ = Sys.command cmd in
    ()

let with_db test_db fn =
  clean test_db;
  lwt () = Disk.init test_db in
  let t = Disk.create test_db in
  try_lwt fn t
  with e ->
    raise_lwt e

module PrettyPrint = struct

  let red fmt = Printf.sprintf "\027[31m%s\027[m" fmt
  let green fmt = Printf.sprintf "\027[32m%s\027[m" fmt
  let yellow fmt = Printf.sprintf "\027[33m%s\027[m" fmt
  let blue fmt = Printf.sprintf "\027[36m%s\027[m" fmt

  let with_process_in cmd f =
    let ic = Unix.open_process_in cmd in
    try
      let r = f ic in
      ignore (Unix.close_process_in ic) ; r
    with exn ->
      ignore (Unix.close_process_in ic) ; raise exn

  let get_terminal_columns () =
    let split s c =
      Re_str.split (Re_str.regexp (Printf.sprintf "[%c]" c)) s in
    try           (* terminfo *)
      with_process_in "tput cols"
        (fun ic -> int_of_string (input_line ic))
    with _ -> try (* GNU stty *)
        with_process_in "stty size"
          (fun ic ->
             match split (input_line ic) ' ' with
             | [_ ; v] -> int_of_string v
             | _ -> failwith "stty")
      with _ -> try (* shell envvar *)
          int_of_string (Sys.getenv "COLUMNS")
        with _ ->
          80

  let terminal_columns =
    let v = Lazy.lazy_from_fun get_terminal_columns in
    fun () ->
      if Unix.isatty Unix.stdout
      then Lazy.force v
      else max_int

  let indent_left s nb =
    let nb = nb - String.length s in
    if nb <= 0 then
      s
    else
      s ^ String.make nb ' '

  let indent_right s nb =
    let nb = nb - String.length s in
    if nb <= 0 then
      s
    else
      String.make nb ' ' ^ s

  let left_column = 70
  let right_column =
    terminal_columns () - left_column + 16 (* padding due to escape chars *)

  let error fmt =
    Printf.kprintf (fun str ->
        Printf.printf "%s\n%s\n" (indent_right (red "[ERROR]") right_column) str
      ) fmt

  let string_of_node ~head = function
    | ListItem i -> Printf.sprintf "%3d" i
    | Label l    -> if head then Printf.sprintf "%-20s" (blue l) else l

  let string_of_path path = match List.rev path with
    | []   -> "--"
    | h::t -> string_of_node ~head:true h
              ^ String.concat " " (List.map (string_of_node ~head:false) t)

  let print_result = function
    | RSuccess p     -> Printf.printf "%s\n" (indent_right (green "[OK]") right_column)
    | RFailure (_,s) -> error "Failure: %s\n" s
    | RError (_, s)  -> error "%s\n" s
    | RSkip _        -> ()
    | RTodo _        -> ()

  let print_event = function
    | EStart p  -> Printf.printf "%s" (indent_left (string_of_path p) left_column)
    | EResult r -> print_result r
    | EEnd p    -> ()

end

let success = function
  | RSuccess _ | RSkip _ -> true
  | _ -> false

let run_tests suite =
  let results = perform_test PrettyPrint.print_event suite in
  match List.filter (fun r -> not (success r)) results with
  | [] -> Printf.printf "%s\n" (PrettyPrint.green "Success!")
  | l  ->
    let msg = Printf.sprintf "%d errors." (List.length l) in
    Printf.printf "%s\n" (PrettyPrint.red msg);
    exit 1