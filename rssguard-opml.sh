#!/usr/bin/env bash
# Independent Bash implementation. Requires sqlite3 >= 3.33 with JSON, jq >= 1.6.
# Usage: bash rssguard-opml.sh /path/database.db [account-id]
set -euo pipefail
if (( $# < 1 || $# > 2 )); then
    printf 'Usage: %s database.db [account-id]\n' "$0" >&2; exit 2
fi
[[ -f "$1" ]] || { printf 'Database file not found: %s\n' "$1" >&2; exit 1; }
account=${2:-}
[[ -z "$account" || "$account" =~ ^[0-9]+$ ]] || { printf 'Invalid account ID\n' >&2; exit 2; }
command -v sqlite3 >/dev/null || { printf 'sqlite3 is required\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'jq is required\n' >&2; exit 1; }
# Absolute path prevents a leading dash being interpreted as an option.
db=$(cd -- "$(dirname -- "$1")" && printf '%s/%s' "$PWD" "$(basename -- "$1")")
# A single SELECT reads all three tables from one snapshot. No startup rc file.
data=$(sqlite3 -init /dev/null -batch -bail -readonly -noheader -list -cmd '.timeout 10000' "$db" <<'SQL'
SELECT json_object(
 'accounts', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'type',type)) FROM Accounts),
 'categories', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'parent',parent_id,'title',title,'description',description,'account_id',account_id)) FROM Categories),
 'feeds', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'parent',category,'title',title,'description',description,'source',source,'custom_data',custom_data,'account_id',account_id)) FROM Feeds)
);
SQL
)
stamp=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
# Buffer the complete result: failed exports do not emit partial OPML.
opml=$(jq -r --arg account "$account" --arg date "$stamp" '
def esc:
  (if . == null then "" else tostring end)
  | if test("[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]") then error("Invalid XML 1.0 character") else . end
  | @html | gsub("\t"; "&#9;") | gsub("\r"; "&#13;") | gsub("\n"; "&#10;");
def attr($name; $value): " " + $name + "=\"" + ($value|esc) + "\"";
def render($d; $a; $parent; $depth):
  if $depth > 200 then error("Folder nesting exceeds 200 levels") else
  ([ $d.categories[] | select(.account_id == $a.id and .parent == $parent) | . + {kind:"c"} ]
   + [ $d.feeds[] | select(.account_id == $a.id and .parent == $parent) | . + {kind:"f"} ])
  | sort_by(.ordr, .kind, .id)
  | map(. as $r | ("  " * ($depth + 2)) as $indent |
      ($indent + "<outline" + attr("text";.title) + attr("description";.description)) as $start |
      if .kind == "c" then
        render($d; $a; .id; $depth + 1) as $kids |
        {count: (1 + $kids.count), xml: ($start + ">\n" + $kids.xml + $indent + "</outline>\n")}
      else
        (if $a.type == "std-rss" then
          ((if (.custom_data // "") == "" then "{}" else .custom_data end) | fromjson) as $m |
          if ($m|type) != "object" then error("Feed custom_data must be a JSON object") else
          ({"0":"RSS","1":"RSS","2":"RSS1","3":"ATOM","4":"JSON","5":"Sitemap","9":"MediaWiki"}[($m.type // 0 | tostring)]) as $v |
          attr("encoding";$m.encoding) + attr("rssguard:xmlUrlType";($m.source_type // 0)) + attr("rssguard:postProcess";$m.post_process) +
          (if $v == null then "" else attr("version";$v) end) end
         else "" end) as $extra |
        {count:1, xml:($start + attr("type";"rss") + attr("title";.title) + attr("xmlUrl";.source) + $extra + " />\n")}
      end)
  | {count: (map(.count)|add // 0), xml: (map(.xml)|join(""))} end;
. as $input |
(if $account == "" then . else
  .accounts |= map(select(.id == ($account|tonumber))) |
  .categories |= map(select(.account_id == ($account|tonumber))) |
  .feeds |= map(select(.account_id == ($account|tonumber))) |
  if (.accounts|length) == 0 then error("Account ID not found") else . end end) as $d |
[$d.accounts | sort_by(.ordr,.id)[] | render($d; .; -1; 0)] as $parts |
if ($parts|map(.count)|add // 0) != (($d.categories|length)+($d.feeds|length)) then error("Orphaned rows or cyclic folders: export refused") else
"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
"<opml version=\"2.0\" xmlns:rssguard=\"https://github.com/martinrotter/rssguard\">\n" +
"  <head>\n    <title>RSS Guard</title>\n    <dateCreated>" + $date + "</dateCreated>\n  </head>\n  <body>\n" +
($parts|map(.xml)|join("")) + "  </body>\n</opml>" end

' <<< "$data")
printf '%s\n' "$opml"
