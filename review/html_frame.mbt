///|
fn review_html_escape(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn review_html_field(
  out : StringBuilder,
  label : String,
  value : String,
) -> Unit {
  out.write_string("<div class=\"field\"><dt>" + label + "</dt><dd>")
  out.write_string(
    review_html_escape(if value.is_empty() { "(none)" } else { value }),
  )
  out.write_string("</dd></div>\n")
}

///|
fn review_html_header(out : StringBuilder, review_id : String) -> Unit {
  out.write_string(
    (
      #|<!doctype html>
      #|<html lang="en">
      #|<head>
      #|<meta charset="utf-8">
      #|<meta name="viewport" content="width=device-width, initial-scale=1">
      #|<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
      #|<title>MoonChat review packet:
    ),
  )
  out.write_string(" " + review_html_escape(review_id))
  out.write_string(
    (
      #|</title>
      #|<style>
      #|:root { color-scheme: light; font: 16px/1.5 system-ui, sans-serif; color: #172638; background: #f4f6f8; }
      #|* { box-sizing: border-box; }
      #|body { margin: 0; }
      #|a { color: #164f92; text-underline-offset: .18em; }
      #|a:focus-visible { outline: 3px solid #b65c00; outline-offset: 3px; }
      #|header, main, footer { max-width: 1440px; margin: auto; padding: 1.5rem; }
      #|header { padding-bottom: .5rem; }
      #|h1 { margin: .2rem 0; font-size: 2rem; }
      #|h2 { font-size: 1.45rem; } h3 { font-size: 1.15rem; }
      #|h2, h3, li, article { scroll-margin-top: 1rem; }
      #|nav ul { display: flex; flex-wrap: wrap; gap: .5rem 1.5rem; padding-left: 1.25rem; }
      #|.notice { padding: 1rem; border-left: 4px solid #52687f; background: #e9eff5; }
      #|.columns { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 1.25rem; align-items: start; }
      #|section, article { min-width: 0; }
      #|.panel, article { background: white; border: 1px solid #c4cfd9; border-radius: .4rem; padding: 1.25rem; margin-bottom: 1rem; }
      #|.decision { border-left: 4px solid #52687f; padding-left: 1rem; margin-top: 1.5rem; }
      #|.objection { border-left: 4px solid #9b4e00; }
      #|dl { margin: .5rem 0; } .field { margin: .7rem 0; }
      #|#summary dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: .25rem 1.5rem; }
      #|dt { font-weight: 650; font-size: .85rem; color: #425469; }
      #|dd { margin: .15rem 0 0; white-space: pre-wrap; overflow-wrap: anywhere; }
      #|.source-lines { list-style: none; margin: 0; padding: 0; font: .9rem/1.6 ui-monospace, monospace; }
      #|.source-lines li { display: grid; grid-template-columns: 3.5em minmax(0, 1fr); min-height: 1.6em; }
      #|.source-lines a { padding-right: 1em; text-align: right; color: #52687f; user-select: none; }
      #|.source-lines span { white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4; }
      #|:target { outline: 2px solid #9b4e00; outline-offset: 3px; }
      #|.back { font-size: .85rem; } .skip { display: inline-block; margin-bottom: .5rem; }
      #|@media (max-width: 850px) { .columns { display: block; } header, main, footer { padding: 1rem; } }
      #|@media print { :root { background: white; font-size: 10pt; } .columns { display: block; } header, main, footer { padding: 0; } nav, .skip, .back { display: none; } .panel, article { border-radius: 0; } h2, h3, dt { break-after: avoid; } a { color: inherit; } :target { outline: none; } }
      #|</style>
      #|</head>
      #|<body>
      #|<header id="top">
      #|<a class="skip" href="#discussion">Skip to review discussion</a>
      #|<h1>MoonChat review packet</h1>
      #|<p class="notice">Read-only derived view. Retain the original bundle JSON and exact source bytes. This packet cannot record decisions, authenticate reviewers, deliver receipts or accept knowledge for a receiving product.</p>
      #|<nav aria-label="Packet sections"><ul><li><a href="#summary">Review scope</a></li><li><a href="#decision-index">Decision index</a></li><li><a href="#source">Source text</a></li><li><a href="#discussion">Discussion and receipts</a></li><li><a href="#participants">Participants</a></li></ul></nav>
      #|</header>
      #|<main>
      #|
    ),
  )
}
