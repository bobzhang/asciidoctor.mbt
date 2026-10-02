///|
let css_attributes_src : String =
  #|align-content align-items align-self alignment-adjust
  #|alignment-baseline all anchor-point animation
  #|animation-delay animation-direction animation-duration
  #|animation-fill-mode animation-iteration-count animation-name
  #|animation-play-state animation-timing-function appearance
  #|azimuth backface-visibility background background-attachment
  #|background-clip background-color background-image
  #|background-origin background-position background-repeat
  #|background-size baseline-shift binding bleed bookmark-label
  #|bookmark-level bookmark-state bookmark-target border
  #|border-bottom border-bottom-color border-bottom-left-radius
  #|border-bottom-right-radius border-bottom-style
  #|border-bottom-width border-collapse border-color
  #|border-image border-image-outset border-image-repeat
  #|border-image-slice border-image-source border-image-width
  #|border-left border-left-color border-left-style
  #|border-left-width border-radius border-right
  #|border-right-color border-right-style border-right-width
  #|border-spacing border-style border-top border-top-color
  #|border-top-left-radius border-top-right-radius
  #|border-top-style border-top-width border-width bottom
  #|box-align box-decoration-break box-direction box-flex
  #|box-flex-group box-lines box-ordinal-group box-orient
  #|box-pack box-shadow box-sizing break-after break-before
  #|break-inside caption-side clear clip clip-path
  #|clip-rule color color-profile columns column-count
  #|column-fill column-gap column-rule column-rule-color
  #|column-rule-style column-rule-width column-span
  #|column-width content counter-increment counter-reset
  #|crop cue cue-after cue-before cursor direction display
  #|dominant-baseline drop-initial-after-adjust
  #|drop-initial-after-align drop-initial-before-adjust
  #|drop-initial-before-align drop-initial-size
  #|drop-initial-value elevation empty-cells filter fit
  #|fit-position flex flex-basis flex-direction flex-flow
  #|flex-grow flex-shrink flex-wrap float float-offset
  #|font font-family font-feature-settings
  #|font-kerning font-language-override font-size
  #|font-size-adjust font-stretch font-style font-synthesis
  #|font-variant font-variant-alternates font-variant-caps
  #|font-variant-east-asian font-variant-ligatures
  #|font-variant-numeric font-variant-position font-weight
  #|grid-cell grid-column grid-column-align grid-column-sizing
  #|grid-column-span grid-columns grid-flow grid-row
  #|grid-row-align grid-row-sizing grid-row-span
  #|grid-rows grid-template hanging-punctuation height
  #|hyphenate-after hyphenate-before hyphenate-character
  #|hyphenate-lines hyphenate-resource hyphens icon
  #|image-orientation image-rendering image-resolution
  #|ime-mode inline-box-align justify-content
  #|left letter-spacing line-break line-height
  #|line-stacking line-stacking-ruby line-stacking-shift
  #|line-stacking-strategy list-style list-style-image
  #|list-style-position list-style-type margin
  #|margin-bottom margin-left margin-right margin-top
  #|mark marker-offset marks mark-after mark-before
  #|marquee-direction marquee-loop marquee-play-count
  #|marquee-speed marquee-style mask max-height max-width
  #|min-height min-width move-to nav-down
  #|nav-index nav-left nav-right nav-up object-fit
  #|object-position opacity order orphans outline
  #|outline-color outline-offset outline-style
  #|outline-width overflow overflow-style overflow-wrap
  #|overflow-x overflow-y padding padding-bottom
  #|padding-left padding-right padding-top
  #|page page-break-after page-break-before
  #|page-break-inside page-policy pause pause-after
  #|pause-before perspective perspective-origin
  #|phonemes pitch pitch-range play-during pointer-events
  #|position presentation-level punctuation-trim quotes
  #|rendering-intent resize rest rest-after rest-before
  #|richness right rotation rotation-point ruby-align
  #|ruby-overhang ruby-position ruby-span size speak
  #|speak-as speak-header speak-numeral speak-punctuation
  #|speech-rate src stress string-set
  #|tab-size table-layout target target-name
  #|target-new target-position text-align
  #|text-align-last text-combine-horizontal
  #|text-decoration text-decoration-color
  #|text-decoration-line text-decoration-skip
  #|text-decoration-style text-emphasis
  #|text-emphasis-color text-emphasis-position
  #|text-emphasis-style text-height text-indent
  #|text-justify text-orientation text-outline
  #|text-overflow text-rendering text-shadow
  #|text-space-collapse text-transform
  #|text-underline-position text-wrap top
  #|transform transform-origin transform-style
  #|transition transition-delay transition-duration
  #|transition-property transition-timing-function
  #|unicode-bidi vertical-align
  #|visibility voice-balance voice-duration
  #|voice-family voice-pitch voice-pitch-range
  #|voice-range voice-rate voice-stress voice-volume
  #|volume white-space widows width word-break
  #|word-spacing word-wrap writing-mode z-index

///|
let css_builtins_src : String =
  #|above absolute always armenian aural auto avoid left bottom
  #|baseline behind below bidi-override blink block bold bolder
  #|both bottom capitalize center center-left center-right circle
  #|cjk-ideographic close-quote collapse condensed continuous crop
  #|cross crosshair cursive dashed decimal decimal-leading-zero
  #|default digits disc dotted double e-resize embed expanded
  #|extra-condensed extra-expanded fantasy far-left far-right fast
  #|faster fixed georgian groove hebrew help hidden hide high higher
  #|hiragana hiragana-iroha icon inherit inline inline-table inset
  #|inside invert italic justify katakana katakana-iroha landscape
  #|large larger left left-side leftwards level lighter line-through
  #|list-item loud low lower lower-alpha lower-greek lower-roman
  #|lowercase ltr medium message-box middle mix monospace n-resize
  #|narrower ne-resize no-close-quote no-open-quote no-repeat none
  #|normal nowrap nw-resize oblique once open-quote outset outside
  #|overline pointer portrait px relative repeat repeat-x repeat-y
  #|rgb ridge right right-side rightwards s-resize sans-serif scroll
  #|se-resize semi-condensed semi-expanded separate serif show
  #|silent slow slower small-caps small-caption smaller soft solid
  #|spell-out square static status-bar super sw-resize table-caption
  #|table-cell table-column table-column-group table-footer-group
  #|table-header-group table-row table-row-group text text-bottom
  #|text-top thick thin top transparent ultra-condensed
  #|ultra-expanded underline upper-alpha upper-latin upper-roman
  #|uppercase url visible w-resize wait wider x-fast x-high x-large
  #|x-loud x-low x-small x-soft xx-large xx-small yes

///|
let css_constants_src : String =
  #|indigo gold firebrick indianred yellow darkolivegreen
  #|darkseagreen mediumvioletred mediumorchid chartreuse
  #|mediumslateblue black springgreen crimson lightsalmon brown
  #|turquoise olivedrab cyan silver skyblue gray darkturquoise
  #|goldenrod darkgreen darkviolet darkgray lightpink teal
  #|darkmagenta lightgoldenrodyellow lavender yellowgreen thistle
  #|violet navy orchid blue ghostwhite honeydew cornflowerblue
  #|darkblue darkkhaki mediumpurple cornsilk red bisque slategray
  #|darkcyan khaki wheat deepskyblue darkred steelblue aliceblue
  #|gainsboro mediumturquoise floralwhite coral purple lightgrey
  #|lightcyan darksalmon beige azure lightsteelblue oldlace
  #|greenyellow royalblue lightseagreen mistyrose sienna lightcoral
  #|orangered navajowhite lime palegreen burlywood seashell
  #|mediumspringgreen fuchsia papayawhip blanchedalmond peru
  #|aquamarine white darkslategray ivory dodgerblue lemonchiffon
  #|chocolate orange forestgreen slateblue olive mintcream
  #|antiquewhite darkorange cadetblue moccasin limegreen saddlebrown
  #|darkslateblue lightskyblue deeppink plum aqua darkgoldenrod
  #|maroon sandybrown magenta tan rosybrown pink lightblue
  #|palevioletred mediumseagreen dimgray powderblue seagreen snow
  #|mediumblue midnightblue paleturquoise palegoldenrod whitesmoke
  #|darkorchid salmon lightslategray lawngreen lightgreen tomato
  #|hotpink lightyellow lavenderblush linen mediumaquamarine green
  #|blueviolet peachpuff

///|
/// Vendor prefixes, from
/// http://www.w3.org/TR/CSS21/syndata.html#vendor-keyword-history
let css_vendor_prefixes_src : String =
  #|-ah- -atsc- -hp- -khtml- -moz- -ms- -o- -rim- -ro- -tc- -wap-
  #|-webkit- -xv- mso- prince-

///|
/// `CSS.attributes` (also used by the Sass lexers).
let css_attributes : Set[String] = word_set(css_attributes_src)

///|
/// `CSS.builtins` (also used by the Sass lexers).
let css_builtins : Set[String] = word_set(css_builtins_src)

///|
/// `CSS.constants` (also used by the Sass lexers).
let css_constants : Set[String] = word_set(css_constants_src)

///|
let css_vendor_prefixes : Array[String] = words(css_vendor_prefixes_src)

///|
/// Rouge's `CSS` (lexers/css.rb).
pub fn css(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("css", options~)
  // Documentation: https://www.w3.org/TR/CSS21/syndata.html#characters
  let identifier_src = "[\\p{L}_-][\\p{Word}\\p{Cf}-]*"
  let identifier = rx(identifier_src)
  let number = rx("-?(?:[0-9]+(\\.[0-9]+)?|\\.[0-9]+)")
  lx.state("root", fn(s) {
    s.mix_in("basics")
    s.rule("{", "Punctuation", next="stanza")
    s.rule(":[:]?\{identifier}", "Name.Decorator")
    s.rule("\\.\{identifier}", "Name.Class")
    s.rule("#\{identifier}", "Name.Function")
    s.rule("@\{identifier}", "Keyword", next="at_rule")
    s.rule(identifier_src, "Name.Tag")
    s.rule("[~^*!%&\\[\\]()<>|+=@:;,./?-]", "Operator")
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"])*\"", "Literal.String.Single")
    s.rule("'(\\\\\\\\|\\\\'|[^'])*'", "Literal.String.Double")
  })
  lx.state("value", fn(s) {
    s.mix_in("basics")
    s.rule("url\\(.*?\\)", "Literal.String.Other")
    s.rule("#[0-9a-f]{1,6}", "Literal.Number", flags="i") // colors
    s.rule(
      "\{number}(?:%|(?:em|px|pt|pc|in|mm|cm|ex|rem|ch|vw|vh|vmin|vmax|dpi|dpcm|dppx|deg|grad|rad|turn|s|ms|Hz|kHz)\\b)?",
      "Literal.Number",
    )
    s.rule("[\\[\\]():\\/.,]", "Punctuation")
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"])*\"", "Literal.String.Single")
    s.rule("'(\\\\\\\\|\\\\'|[^'])*'", "Literal.String.Double")
    s.call(identifier_src, fn(lx, m) {
      if css_constants.contains(m.matched()) {
        lx.token("Name.Constant")
      } else if css_builtins.contains(m.matched()) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name")
      }
    })
  })
  lx.state("at_rule", fn(s) {
    s.rule(
      "{(?=\\s*\{identifier}\\s*:)",
      "Punctuation",
      flags="m",
      next="at_stanza",
    )
    s.rule("{", "Punctuation", next="at_body")
    s.rule(";", "Punctuation", next="#pop")
    s.mix_in("value")
  })
  lx.state("at_body", fn(s) {
    s.mix_in("at_content")
    s.mix_in("root")
  })
  lx.state("at_stanza", fn(s) {
    s.mix_in("at_content")
    s.mix_in("stanza")
  })
  lx.state("at_content", fn(s) {
    s.call("}", fn(lx, _) {
      lx.token("Punctuation")
      lx.pop(times=2)
    })
  })
  lx.state("basics", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("/\\*(?:.*?)\\*/", "Comment", flags="m")
  })
  lx.state("stanza", fn(s) {
    s.mix_in("basics")
    s.rule("}", "Punctuation", next="#pop")
    s.call(
      "(\{identifier})(\\s*)(:)",
      fn(lx, m) {
        let name = group_text(m, 1)
        let name_tok = if css_attributes.contains(name) {
          "Name.Label"
        } else if css_vendor_prefixes.iter().any(p => name.has_prefix(p)) {
          "Name.Label"
        } else {
          "Name.Property"
        }
        lx.groups([name_tok, "Text", "Punctuation"])
        lx.push("stanza_value")
      },
      flags="m",
    )
  })
  lx.state("stanza_value", fn(s) {
    s.rule(";", "Punctuation", next="#pop")
    s.call("(?=})", fn(lx, _) { lx.pop() })
    s.rule("!\\s*important\\b", "Comment.Preproc")
    s.rule("^@.*?$", "Comment.Preproc")
    s.mix_in("value")
  })
  lx
}
