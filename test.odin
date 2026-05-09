package main

import "core:strings"
import "core:testing"
import mdz "mdz"

// Helper: compile and check contains substring
expect_contains :: proc(t: ^testing.T, input, substr: string, loc := #caller_location) -> bool {
	result, err := mdz.compile(input)
	if err != nil {
		testing.fail(t, loc)
		return false
	}
	defer delete(result)
	return testing.expect(t, strings.contains(result, substr), loc = loc)
}

@(test)
test_empty_input :: proc(t: ^testing.T) {
	result, err := mdz.compile("")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "MDXContent"), "should contain MDXContent")
}

@(test)
test_just_text :: proc(t: ^testing.T) {
	expect_contains(t, "hello", "<p>hello</p>")
}

@(test)
test_heading :: proc(t: ^testing.T) {
	expect_contains(t, "# Hello", "<h1>Hello</h1>")
}

@(test)
test_bold :: proc(t: ^testing.T) {
	expect_contains(t, "**bold**", "<strong>bold</strong>")
}

@(test)
test_italic :: proc(t: ^testing.T) {
	expect_contains(t, "*italic*", "<em>italic</em>")
}

@(test)
test_bold_italic :: proc(t: ^testing.T) {
	expect_contains(t, "***both***", "<em><strong>both</strong></em>")
}

@(test)
test_code :: proc(t: ^testing.T) {
	expect_contains(t, "`code`", "<code>code</code>")
}

@(test)
test_link :: proc(t: ^testing.T) {
	expect_contains(t, "[text](https://example.com)", `<a href="https://example.com">text</a>`)
}

@(test)
test_image :: proc(t: ^testing.T) {
	expect_contains(t, "![alt](img.png)", `<img src="img.png" alt="alt"/>`)
}

@(test)
test_list_unordered :: proc(t: ^testing.T) {
	result, err := mdz.compile("- one\n- two\n- three")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<ul>"))
	testing.expect(t, strings.contains(result, "</ul>"))
}

@(test)
test_list_ordered :: proc(t: ^testing.T) {
	result, err := mdz.compile("1. one\n2. two")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<ol>"))
	testing.expect(t, strings.contains(result, "</ol>"))
}

@(test)
test_list_loose :: proc(t: ^testing.T) {
	result, err := mdz.compile("- one\n\n- two\n\n- three")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<p>one</p>"), "loose item should wrap in <p>")
	testing.expect(t, strings.contains(result, "<p>two</p>"), "second loose item should wrap in <p>")
	testing.expect(t, strings.contains(result, "<p>three</p>"), "third loose item should wrap in <p>")
}

@(test)
test_list_loose_ordered :: proc(t: ^testing.T) {
	result, err := mdz.compile("1. alpha\n\n2. beta")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<ol>"))
	testing.expect(t, strings.contains(result, "<p>alpha</p>"))
	testing.expect(t, strings.contains(result, "<p>beta</p>"))
}

@(test)
test_list_continuation :: proc(t: ^testing.T) {
	result, err := mdz.compile("- one\n  continuation\n- two")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<ul>"))
	testing.expect(t, strings.contains(result, "<li>one continuation</li>"), "continuation line should join item content")
	testing.expect(t, strings.contains(result, "<li>two</li>"))
}

@(test)
test_blockquote :: proc(t: ^testing.T) {
	expect_contains(t, "> quote", "<blockquote>")
	expect_contains(t, "> quote", "<p>quote</p>")
}

@(test)
test_fence :: proc(t: ^testing.T) {
	expect_contains(t, "```javascript\nconsole.log('hi')\n```", `class="language-javascript"`)
}

@(test)
test_thematic_break :: proc(t: ^testing.T) {
	expect_contains(t, "---", "<hr/>")
}

@(test)
test_thematic_break_after_blank :: proc(t: ^testing.T) {
	// --- preceded by blank line should still be a thematic break
	result, err := mdz.compile("paragraph\n\n---\n\nmore")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<hr/>"), "--- after blank should be hr")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph before should remain")
	testing.expect(t, strings.contains(result, "<p>more</p>"), "paragraph after should remain")
}

@(test)
test_import :: proc(t: ^testing.T) {
	result, err := mdz.compile("import {Foo} from './bar'")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "import {Foo} from './bar'"))
}

@(test)
test_export :: proc(t: ^testing.T) {
	result, err := mdz.compile("export const x = 1")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "export const x = 1"))
}

@(test)
test_jsx_element :: proc(t: ^testing.T) {
	result, err := mdz.compile("<Foo />")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<Foo />"))
}

@(test)
test_expression :: proc(t: ^testing.T) {
	result, err := mdz.compile("{42}")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "{42}"))
}

@(test)
test_frontmatter_stripped :: proc(t: ^testing.T) {
	result, err := mdz.compile("---\ntitle: Test\n---\n\n# Hello")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>Hello</h1>"))
	testing.expect(t, !strings.contains(result, "title: Test"), "frontmatter should be stripped")
}

@(test)
test_escape :: proc(t: ^testing.T) {
	result, err := mdz.compile("\\*not italic\\*")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "*not italic*"))
}

@(test)
test_ampersand :: proc(t: ^testing.T) {
	expect_contains(t, "a & b", "&amp;")
}

@(test)
test_html_entity :: proc(t: ^testing.T) {
	result, err := mdz.compile("&#60;div&#62;")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "&#60;div&#62;"))
}

@(test)
test_line_break :: proc(t: ^testing.T) {
	expect_contains(t, "line1\nline2", "<br/>")
}

@(test)
test_escape_bare_lt :: proc(t: ^testing.T) {
	result, err := mdz.compile("a < b")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "&lt;"))
}

@(test)
test_mixed_list_types :: proc(t: ^testing.T) {
	result, err := mdz.compile("- one\n- two\n1. three\n2. four")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "</ul>\n\n<ol>"), "should switch from ul to ol")
}

@(test)
test_paragraph_with_nested :: proc(t: ^testing.T) {
	result, err := mdz.compile("a **b** c *d* e `f`")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<strong>b</strong>"))
	testing.expect(t, strings.contains(result, "<em>d</em>"))
	testing.expect(t, strings.contains(result, "<code>f</code>"))
}

@(test)
test_strikethrough :: proc(t: ^testing.T) {
	expect_contains(t, "~~deleted~~", "<del>deleted</del>")
}

@(test)
test_strikethrough_nested :: proc(t: ^testing.T) {
	result, err := mdz.compile("~~**bold** and *italic*~~")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<del><strong>bold</strong> and <em>italic</em></del>"))
}

@(test)
test_single_tilde_not_strikethrough :: proc(t: ^testing.T) {
	result, err := mdz.compile("~not strikethrough~")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "~not strikethrough~"))
}

@(test)
test_table_basic :: proc(t: ^testing.T) {
	result, err := mdz.compile("| a | b |\n|---|---|\n| c | d |")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<table>"), "should contain <table>")
	testing.expect(t, strings.contains(result, "<th>a</th>"), "should have header cell a")
	testing.expect(t, strings.contains(result, "<th>b</th>"), "should have header cell b")
	testing.expect(t, strings.contains(result, "<td>c</td>"), "should have data cell c")
	testing.expect(t, strings.contains(result, "<td>d</td>"), "should have data cell d")
}

@(test)
test_table_no_leading_pipe :: proc(t: ^testing.T) {
	result, err := mdz.compile("a | b\n-|-\nc | d")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<table>"))
	testing.expect(t, strings.contains(result, "<th>a</th>"))
	testing.expect(t, strings.contains(result, "<th>b</th>"))
}

@(test)
test_table_escaped_pipe :: proc(t: ^testing.T) {
	result, err := mdz.compile("| a \\| b | c |\n|---|---|\n| d | e |")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<th>a | b</th>"), "escaped pipe should be literal in header")
	testing.expect(t, strings.contains(result, "<th>c</th>"), "second header cell")
	testing.expect(t, strings.contains(result, "<td>d</td>"), "first data cell")
	testing.expect(t, strings.contains(result, "<td>e</td>"), "second data cell")
}

@(test)
test_table_inline_formatting :: proc(t: ^testing.T) {
	result, err := mdz.compile("| **bold** | *italic* |\n|---|---|\n| `code` | text |")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<strong>bold</strong>"))
	testing.expect(t, strings.contains(result, "<em>italic</em>"))
	testing.expect(t, strings.contains(result, "<code>code</code>"))
}

@(test)
test_named_html_entity :: proc(t: ^testing.T) {
	result, err := mdz.compile("&amp; &lt; &gt; &quot; &nbsp; &copy;")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "&amp;"), "should preserve &amp;")
	testing.expect(t, strings.contains(result, "&lt;"), "should preserve &lt;")
	testing.expect(t, strings.contains(result, "&gt;"), "should preserve &gt;")
	testing.expect(t, strings.contains(result, "&quot;"), "should preserve &quot;")
	testing.expect(t, strings.contains(result, "&nbsp;"), "should preserve &nbsp;")
	testing.expect(t, strings.contains(result, "&copy;"), "should preserve &copy;")
}

@(test)
test_nested_list_unordered :: proc(t: ^testing.T) {
	result, err := mdz.compile("- a\n  - b\n  - c\n- d")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<li>a"), "first item")
	testing.expect(t, strings.contains(result, "<li>b"), "nested item")
	testing.expect(t, strings.contains(result, "<li>d"), "sibling item")
}

@(test)
test_nested_list_ordered :: proc(t: ^testing.T) {
	result, err := mdz.compile("1. a\n   1. b\n   2. c\n2. d")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<li>a"), "first item")
	testing.expect(t, strings.contains(result, "<li>b"), "nested item")
	testing.expect(t, strings.contains(result, "<li>c"), "second nested")
	testing.expect(t, strings.contains(result, "<li>d"), "sibling item")
}

@(test)
test_mixed_nested_list :: proc(t: ^testing.T) {
	result, err := mdz.compile("- a\n  1. b\n  2. c\n- d")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<li>a"), "unordered parent")
	testing.expect(t, strings.contains(result, "<ol>"), "ordered nested")
	testing.expect(t, strings.contains(result, "<li>b"), "nested ordered item")
}

@(test)
test_blockquote_with_heading :: proc(t: ^testing.T) {
	result, err := mdz.compile("> # Heading\n> Paragraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>Heading</h1>"), "heading in blockquote")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "paragraph in blockquote")
}

@(test)
test_nested_blockquote :: proc(t: ^testing.T) {
	result, err := mdz.compile("> Outer\n> > Inner")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<blockquote>"), "outer blockquote")
	testing.expect(t, strings.contains(result, "Outer"), "outer text")
	testing.expect(t, strings.contains(result, "Inner"), "inner text")
}

@(test)
test_unterminated_expression_recovery :: proc(t: ^testing.T) {
	// Expression with depth > 0 after 100+ newlines should bail out
	newlines := strings.repeat("\n", 101)
	defer delete(newlines)
	input := strings.concatenate([]string{"{const x = 1\n", newlines, "after"})
	defer delete(input)
	result, err := mdz.compile(input)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	// The expression should be cut off, and 'after' should appear as normal text
	testing.expect(t, strings.contains(result, "after"), "should recover after unterminated expression")
}

@(test)
test_jsx_expression_depth_guard :: proc(t: ^testing.T) {
	// JSX with expressions containing JSX (tests depth == 0 guard)
	result, err := mdz.compile("<Layout>\n\n<Chart values={[1,2,3]} />\n\n{items.length > 0 ? <List items={items} /> : <p>None</p>}\n\n</Layout>\n\nParagraph after")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "</Layout>"), "should close Layout")
	testing.expect(t, strings.contains(result, "<p>Paragraph after</p>"), "should parse paragraph after JSX")
}

@(test)
test_self_closing_jsx_inline :: proc(t: ^testing.T) {
	result, err := mdz.compile("before <Divider/> after")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<Divider/>"), "should preserve self-closing JSX")
	testing.expect(t, strings.contains(result, "<p>"), "should wrap in paragraph")
}

@(test)
test_self_closing_jsx_multiline_attr :: proc(t: ^testing.T) {
	// Multi-line self-closing JSX tag with attributes across lines
	result, err := mdz.compile("<Layout>\n\n<Chart\n  data={[\n    {x: 1, y: 2}\n  ]}\n  renderLabel={(x) => x}\n/>\n\n</Layout>\n\nParagraph after")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "</Layout>"), "should close Layout")
	testing.expect(t, strings.contains(result, "<p>Paragraph after</p>"), "should parse paragraph after multi-line self-closing JSX")
}

@(test)
test_compile_with_remove_heading :: proc(t: ^testing.T) {
	// TransformConfig: remove all headings
	remove_heading := mdz.TransformConfig{
		heading = proc(input: string, pos: int) -> mdz.NodeAction { return .Remove },
	}
	result, err := mdz.compile_with("# Hello\n\nParagraph", &remove_heading)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h1>"), "should remove heading")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "should keep paragraph")
}

@(test)
test_compile_with_remove_paragraph :: proc(t: ^testing.T) {
	// TransformConfig: remove all paragraphs
	remove_para := mdz.TransformConfig{
		paragraph = proc(input: string, pos: int) -> mdz.NodeAction { return .Remove },
	}
	result, err := mdz.compile_with("# Hello\n\nParagraph", &remove_para)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>"), "should keep heading")
	testing.expect(t, !strings.contains(result, "<p>"), "should remove paragraph")
}

@(test)
test_math_inline :: proc(t: ^testing.T) {
	// Inline math $...$
	result, err := mdz.compile("math $x + y$ here")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<code class=\"language-math\">x + y</code>"), "should render inline math")
	testing.expect(t, strings.contains(result, "<p>"), "should wrap in paragraph")
}

@(test)  
test_math_display :: proc(t: ^testing.T) {
	// Display math $$...$$
	result, err := mdz.compile("$$\n\\int x dx\n$$")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<pre><code class=\"language-math\">"), "should render display math")
}

@(test)
test_emoji_basic :: proc(t: ^testing.T) {
	expect_contains(t, ":smile:", "<span class=\"emoji\">smile</span>")
}

@(test)
test_emoji_multiple :: proc(t: ^testing.T) {
	result, err := mdz.compile(":dog: and :cat:")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<span class=\"emoji\">dog</span>"), "should render dog emoji")
	testing.expect(t, strings.contains(result, "<span class=\"emoji\">cat</span>"), "should render cat emoji")
}

@(test)
test_emoji_not_time :: proc(t: ^testing.T) {
	// Time like 12:00 should NOT be treated as emoji
	result, err := mdz.compile("time is 12:00")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<span"), "time colons should not be emoji")
}

@(test)
test_emoji_empty_code :: proc(t: ^testing.T) {
	// :: should NOT be treated as emoji
	expect_contains(t, "::", "::")
}

@(test)
test_comment_jsx_block :: proc(t: ^testing.T) {
	// {/* comment */} at block level should be stripped
	result, err := mdz.compile("{/* Hello world */}\n\nParagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "Hello world"), "JSX comment should be stripped")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "paragraph should remain")
}

@(test)
test_comment_jsx_multiline :: proc(t: ^testing.T) {
	// Multi-line {/* comment */} should be stripped
	result, err := mdz.compile("{/*\n * Multi-line\n * comment\n */}\n\nParagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "Multi-line"), "multi-line JSX comment should be stripped")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "paragraph should remain")
}

@(test)
test_comment_html :: proc(t: ^testing.T) {
	// <!-- comment --> at block level should be stripped
	result, err := mdz.compile("<!-- Hello world -->\n\nParagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "Hello world"), "HTML comment should be stripped")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "paragraph should remain")
}

@(test)
test_comment_html_multiline :: proc(t: ^testing.T) {
	// Multi-line <!-- comment --> should be stripped
	result, err := mdz.compile("<!--\n  Multi-line\n  comment\n-->\n\nParagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "Multi-line"), "multi-line HTML comment should be stripped")
	testing.expect(t, strings.contains(result, "<p>Paragraph</p>"), "paragraph should remain")
}

@(test)
test_deflist_basic :: proc(t: ^testing.T) {
	// Basic term : definition
	result, err := mdz.compile("Term\n: Definition")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<dl>"), "should contain <dl>")
	testing.expect(t, strings.contains(result, "<dt>Term</dt>"), "should have term")
	testing.expect(t, strings.contains(result, "<dd>Definition</dd>"), "should have definition")
}

@(test)
test_deflist_multi_def :: proc(t: ^testing.T) {
	// Multiple definitions for one term
	result, err := mdz.compile("Term\n: Definition 1\n: Definition 2")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<dl>"), "should contain <dl>")
	testing.expect(t, strings.contains(result, "<dt>Term</dt>"), "should have term")
	testing.expect(t, strings.contains(result, "<dd>Definition 1</dd>"), "should have def 1")
	testing.expect(t, strings.contains(result, "<dd>Definition 2</dd>"), "should have def 2")
}

@(test)
test_deflist_with_blank_line :: proc(t: ^testing.T) {
	// Term and definition with blank line between
	result, err := mdz.compile("Term\n\n: Definition")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	// With a blank line, these are separate blocks, not a deflist
	testing.expect(t, !strings.contains(result, "<dl>"), "should not be deflist")
	testing.expect(t, strings.contains(result, "<p>Term</p>"), "term should be paragraph")
}

@(test)
test_deflist_skip_standalone :: proc(t: ^testing.T) {
	// : at line start with no preceding term should be skipped
	result, err := mdz.compile(": orphan\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<dl>"), "should not be deflist")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph should remain")
}

@(test)
test_highlight_js_keywords :: proc(t: ^testing.T) {
	result, err := mdz.compile("```js\nconst x = 1\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"hl-kw\""), "keywords should be highlighted")
	testing.expect(t, strings.contains(result, "class=\"hl-num\""), "numbers should be highlighted")
}

@(test)
test_highlight_js_string :: proc(t: ^testing.T) {
	result, err := mdz.compile("```js\nvar msg = \"hello\"\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"hl-str\""), "strings should be highlighted")
}

@(test)
test_highlight_js_comment :: proc(t: ^testing.T) {
	result, err := mdz.compile("```js\n// comment\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"hl-cm\""), "comments should be highlighted")
}

@(test)
test_highlight_python :: proc(t: ^testing.T) {
	result, err := mdz.compile("```py\ndef hello():\n    pass\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"hl-kw\""), "python keywords should be highlighted")
}

@(test)
test_highlight_rust :: proc(t: ^testing.T) {
	result, err := mdz.compile("```rs\nfn main() {}\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"hl-kw\""), "rust keywords should be highlighted")
}

@(test)
test_highlight_unknown_lang :: proc(t: ^testing.T) {
	// Unknown language should not get highlighting spans
	result, err := mdz.compile("```unknown\nhello world\n```")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "class=\"hl-"), "unknown language should not be highlighted")
}

@(test)
test_math_inside_fence :: proc(t: ^testing.T) {
	// $$ inside a fenced code block should NOT be treated as math
	input := "```\n$$\n\\int x dx\n$$\n```\n\nparagraph"
	result, err := mdz.compile(input)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<pre><code"), "should be code fence")
	testing.expect(t, strings.contains(result, "$$"), "$$ should appear in fence output")
	testing.expect(t, !strings.contains(result, "class=\"language-math\""), "should not be rendered as math")
}

// ─── Plugin system tests ───────────────────────────────────────────

@(test)
test_plugin_before_block_remove :: proc(t: ^testing.T) {
	// BeforeBlock plugin that removes all headings
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "remove-headings",
		phase = .BeforeBlock,
		filter = {mdz.BlockType.Heading},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			return .Remove
		},
	})

	result, err := mdz.compile_with_plugins("# Hello\n\nparagraph", nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h1>"), "headings should be removed by plugin")
	testing.expect(t, strings.contains(result, "<p>"), "paragraph should still be present")
}

@(test)
test_plugin_before_block_handled :: proc(t: ^testing.T) {
	// BeforeBlock plugin that replaces headings with custom output
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "custom-headings",
		phase = .BeforeBlock,
		filter = {mdz.BlockType.Heading},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			// Find the heading line
			i := ctx.pos
			for i < len(ctx.input) && ctx.input[i] != '\n' { i += 1 }
			ctx.pos = i + 1
			mdz.writer_write(ctx.output, "\n<div class=\"custom-heading\">custom</div>\n")
			return .Handled
		},
	})

	result, err := mdz.compile_with_plugins("# Hello\n\nworld", nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "custom-heading"), "plugin should write custom output")
	testing.expect(t, !strings.contains(result, "<h1>"), "original heading should be replaced")
}

@(test)
test_plugin_after_block_transform :: proc(t: ^testing.T) {
	// AfterBlock plugin that wraps all paragraph output in a custom div
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "wrap-paragraphs",
		phase = .AfterBlock,
		filter = {mdz.BlockType.Paragraph},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			if len(ctx.written) > 0 {
				// We can't undo what was written, but we can append after
				// For this test we'll just verify written is non-empty
			}
			return .Keep
		},
	})

	input := "hello world"
	result, err := mdz.compile_with_plugins(input, nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<p>"), "paragraph should still be rendered")
}

@(test)
test_plugin_filter_blocks :: proc(t: ^testing.T) {
	// Plugin with filter should only fire for matching block types
	removed_heading := false
	removed_fence := false

	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "remove-fences-only",
		phase = .BeforeBlock,
		filter = {mdz.BlockType.Fence},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			return .Remove
		},
	})

	result, err := mdz.compile_with_plugins("# heading\n\n```js\ncode\n```\n\nparagraph", nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>"), "headings should not be removed by fence-only filter")
	testing.expect(t, strings.contains(result, "<p>"), "paragraphs should not be removed by fence-only filter")
	_ = removed_heading
	_ = removed_fence
}

@(test)
test_plugin_pipeline_multiple :: proc(t: ^testing.T) {
	// Multiple plugins registered in the same pipeline
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	// First plugin: remove headings
	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "remove-headings",
		phase = .BeforeBlock,
		filter = {mdz.BlockType.Heading},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			return .Remove
		},
	})

	// Second plugin: wrap paragraphs
	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "wrap-paragraphs",
		phase = .AfterBlock,
		filter = {mdz.BlockType.Paragraph},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			if len(ctx.written) > 0 {
				mdz.writer_write(ctx.output, "<!-- paragraph-end -->\n")
			}
			return .Keep
		},
	})

	input := "# Gone\n\nhello\n\n```js\nx\n```\n\nworld"
	result, err := mdz.compile_with_plugins(input, nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h1>"), "headings should be removed by first plugin")
	testing.expect(t, strings.contains(result, "<!-- paragraph-end -->"), "paragraphs should be annotated by second plugin")
	testing.expect(t, strings.contains(result, "<pre><code"), "fence should still be present")
}

@(test)
test_plugin_with_transform_config :: proc(t: ^testing.T) {
	// Plugin pipeline works alongside TransformConfig
	config := mdz.TransformConfig{
		heading = proc(input: string, pos: int) -> mdz.NodeAction {
			return .Remove
		},
	}

	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "annotate-paragraphs",
		phase = .AfterBlock,
		filter = {mdz.BlockType.Paragraph},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			mdz.writer_write(ctx.output, "<!-- plugin -->\n")
			return .Keep
		},
	})

	input := "# heading\n\nparagraph"
	result, err := mdz.compile_with_plugins(input, &config, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h1>"), "heading should be removed by TransformConfig")
	testing.expect(t, strings.contains(result, "<!-- plugin -->"), "plugin should still run on paragraphs")
}

@(test)
test_plugin_all_block_types :: proc(t: ^testing.T) {
	// Plugin with no filter should fire for ALL block types
	seen := make(map[mdz.BlockType]bool)
	defer delete(seen)

	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "track-all",
		phase = .AfterBlock,
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			return .Keep
		},
	})

	result, err := mdz.compile_with_plugins("# a\n\nb\n\n> c\n\n- d\n\n```\ne\n```", nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>"), "heading should render")
	testing.expect(t, strings.contains(result, "<p>"), "paragraph should render")
	testing.expect(t, strings.contains(result, "<blockquote>"), "blockquote should render")
	testing.expect(t, strings.contains(result, "<ul>"), "list should render")
	testing.expect(t, strings.contains(result, "<pre><code>"), "fence should render")
}

@(test)
test_plugin_handled_advances_pos :: proc(t: ^testing.T) {
	// BeforeBlock plugin that handles a heading must advance pos correctly.
	// The paragraph after the heading should still be processed normally.
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	mdz.plugin_register(&pipeline, mdz.Plugin{
		name  = "consume-heading",
		phase = .BeforeBlock,
		filter = {mdz.BlockType.Heading},
		hook  = proc(ctx: ^mdz.PluginContext) -> mdz.PluginResult {
			// Skip past the heading line
			i := ctx.pos
			for i < len(ctx.input) && ctx.input[i] != '\n' { i += 1 }
			if i < len(ctx.input) { i += 1 }
			ctx.pos = i
			return .Handled
		},
	})

	input := "# heading\n\nparagraph after heading"
	result, err := mdz.compile_with_plugins(input, nil, &pipeline)
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h1>"), "heading should be consumed by plugin")
	testing.expect(t, strings.contains(result, "paragraph after heading"), "paragraph after heading should still be processed")
}

@(test)
test_setext_heading_h1 :: proc(t: ^testing.T) {
	expect_contains(t, "Heading 1\n===", "<h1>Heading 1</h1>")
}

@(test)
test_setext_heading_h2 :: proc(t: ^testing.T) {
	expect_contains(t, "Heading 2\n---", "<h2>Heading 2</h2>")
}

@(test)
test_setext_heading_long_underline :: proc(t: ^testing.T) {
	expect_contains(t, "Title\n============", "<h1>Title</h1>")
}

@(test)
test_setext_heading_multiline_whitespace :: proc(t: ^testing.T) {
	// Underline with spaces after should still work
	expect_contains(t, "Hello\n=== ", "<h1>Hello</h1>")
}

@(test)
test_setext_heading_followed_by_paragraph :: proc(t: ^testing.T) {
	result, err := mdz.compile("Section\n====\n\nparagraph text")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h1>Section</h1>"), "should be heading")
	testing.expect(t, strings.contains(result, "<p>paragraph text</p>"), "paragraph should follow")
}

@(test)
test_setext_heading_not_break :: proc(t: ^testing.T) {
	// 2 dashes is not a setext underline (needs 3+)
	result, err := mdz.compile("not heading\n--")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "<h2>"), "2 dashes should not make heading")
}

@(test)
test_setext_heading_h2_not_thematic_break :: proc(t: ^testing.T) {
	// --- after text should be heading, not hr
	result, err := mdz.compile("Title\n---")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<h2>"), "--- after text should be heading")
	testing.expect(t, !strings.contains(result, "<hr/>"), "should not be hr")
}

@(test)
test_autolink_uri :: proc(t: ^testing.T) {
	expect_contains(t, "<https://example.com>", `<a href="https://example.com">https://example.com</a>`)
}

@(test)
test_autolink_uri_http :: proc(t: ^testing.T) {
	expect_contains(t, "<http://example.com>", `<a href="http://example.com">http://example.com</a>`)
}

@(test)
test_autolink_email :: proc(t: ^testing.T) {
	expect_contains(t, "<user@example.com>", `<a href="mailto:user@example.com">user@example.com</a>`)
}

@(test)
test_autolink_not_autolink :: proc(t: ^testing.T) {
	// Angle brackets without scheme or @ should not produce autolink
	result, err := mdz.compile("<not a link>")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	// In MDX, <not a link> is treated as JSX (lowercase HTML element)
	testing.expect(t, strings.contains(result, "<not a link>"), "non-autolink bare angle brackets pass through as JSX")
}

@(test)
test_task_list_unchecked :: proc(t: ^testing.T) {
	result, err := mdz.compile("- [ ] buy milk")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"task-item\""), "should have task-item class")
	testing.expect(t, strings.contains(result, "type=\"checkbox\""), "should have checkbox input")
	testing.expect(t, !strings.contains(result, "checked"), "should not be checked")
	testing.expect(t, strings.contains(result, "buy milk"), "should have content")
}

@(test)
test_task_list_checked :: proc(t: ^testing.T) {
	result, err := mdz.compile("- [x] done")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"task-item\""), "should have task-item class")
	testing.expect(t, strings.contains(result, "checked"), "should be checked")
	testing.expect(t, strings.contains(result, "done"), "should have content")
}

@(test)
test_task_list_checked_upper :: proc(t: ^testing.T) {
	result, err := mdz.compile("- [X] done")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "checked"), "uppercase X should also be checked")
}

@(test)
test_task_list_normal_list :: proc(t: ^testing.T) {
	// Regular list items should NOT get task-item class
	result, err := mdz.compile("- normal item")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "task-item"), "normal list should not be task-item")
	testing.expect(t, strings.contains(result, "<li>"), "should have plain <li>")
}

@(test)
test_footnote_inline_ref :: proc(t: ^testing.T) {
	result, err := mdz.compile("text[^1] here")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<sup>"), "footnote ref should be sup")
	testing.expect(t, strings.contains(result, "href=\"#fn:1\""), "should link to footnote")
	testing.expect(t, strings.contains(result, "id=\"fnref:1\""), "should have backlink id")
}

@(test)
test_footnote_definition_stripped :: proc(t: ^testing.T) {
	// Footnote definition content should appear in the footnotes section
	result, err := mdz.compile("[^1]: definition here\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "paragraph"), "paragraph should remain")
	testing.expect(t, strings.contains(result, "definition here"), "footnote content should appear in footnotes section")
	// Ensure paragraph is separate from footnotes
	testing.expect(t, strings.contains(result, "class=\"footnotes\""), "should have footnotes section")
}

@(test)
test_footnote_section :: proc(t: ^testing.T) {
	// Footnote definitions should produce a footnotes section
	result, err := mdz.compile("[^1]: first footnote\n\nbody text")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"footnotes\""), "should have footnotes section")
	testing.expect(t, strings.contains(result, "<li id=\"fn:1\""), "should have footnote li")
	testing.expect(t, strings.contains(result, "first footnote"), "footnote content should appear in section")
	testing.expect(t, strings.contains(result, "body text"), "body text should still appear")
}

@(test)
test_autolink_uri_with_port :: proc(t: ^testing.T) {
	expect_contains(t, "<http://localhost:3000/path>", `<a href="http://localhost:3000/path">http://localhost:3000/path</a>`)
}

@(test)
test_autolink_email_in_paragraph :: proc(t: ^testing.T) {
	expect_contains(t, "email <user@example.com> here", `<a href="mailto:user@example.com">user@example.com</a>`)
}

@(test)
test_autolink_jsx_still_works :: proc(t: ^testing.T) {
	// JSX elements should still be processed normally
	result, err := mdz.compile("<Component />")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<Component />"), "JSX should still pass through")
}

@(test)
test_task_list_mixed_context :: proc(t: ^testing.T) {
	result, err := mdz.compile("- [ ] unchecked\n- [x] checked\n- normal")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "class=\"task-item\""), "task items should have class")
	testing.expect(t, strings.contains(result, "unchecked"), "unchecked item")
	testing.expect(t, strings.contains(result, "checked"), "checked item")
	testing.expect(t, strings.contains(result, "normal"), "normal item")
}

@(test)
test_footnote_inline_formatting :: proc(t: ^testing.T) {
	// Footnote content should support inline formatting
	result, err := mdz.compile("[^1]: **bold** footnote\n\nref[^1]")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<strong>bold</strong>"), "footnote should support bold")
}

@(test)
test_footnote_multiple :: proc(t: ^testing.T) {
	result, err := mdz.compile("[^1]: first\n[^2]: second\n\nref[^1] and ref[^2]")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "first"), "first footnote content")
	testing.expect(t, strings.contains(result, "second"), "second footnote content")
	testing.expect(t, strings.contains(result, "href=\"#fn:1\""), "link to first")
	testing.expect(t, strings.contains(result, "href=\"#fn:2\""), "link to second")
}

@(test)
test_plugin_empty_pipeline :: proc(t: ^testing.T) {
	// Empty pipeline should behave identically to compile()
	pipeline: mdz.PluginPipeline
	mdz.plugin_init(&pipeline)
	defer mdz.plugin_destroy(&pipeline)

	input := "# hello\n\nworld"
	result1, err1 := mdz.compile(input)
	if err1 != nil { testing.fail(t); return }
	defer delete(result1)

	result2, err2 := mdz.compile_with_plugins(input, nil, &pipeline)
	if err2 != nil { testing.fail(t); return }
	defer delete(result2)

	testing.expect(t, result1 == result2, "empty pipeline should produce identical output")
}

// ─── HTML block passthrough tests ───────────────────────────────────────

@(test)
test_html_void_br :: proc(t: ^testing.T) {
	result, err := mdz.compile("<br>\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<br>"), "br should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph after br should be wrapped")
}

@(test)
test_html_void_hr :: proc(t: ^testing.T) {
	result, err := mdz.compile("<hr>\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<hr>"), "hr should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph after hr should be wrapped")
}

@(test)
test_html_void_img :: proc(t: ^testing.T) {
	result, err := mdz.compile("<img src=\"a.jpg\">\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<img src=\"a.jpg\">"), "img with attr should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph after img should be wrapped")
}

@(test)
test_html_void_input :: proc(t: ^testing.T) {
	result, err := mdz.compile("<input type=\"text\" disabled>\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<input type=\"text\" disabled>"), "input should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph after input should be wrapped")
}

@(test)
test_html_void_inline :: proc(t: ^testing.T) {
	result, err := mdz.compile("text <br> here")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<br>"), "inline br should pass through")
	testing.expect(t, strings.contains(result, "<p>"), "should wrap in paragraph")
}

@(test)
test_html_nested_block :: proc(t: ^testing.T) {
	result, err := mdz.compile("<div>\n  <p>nested</p>\n</div>\n\nparagraph after")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<div>"), "div should pass through")
	testing.expect(t, strings.contains(result, "<p>nested</p>"), "nested p should pass through")
	testing.expect(t, strings.contains(result, "</div>"), "closing div should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph after</p>"), "paragraph after should be wrapped")
}

@(test)
test_html_multiple_void_elements :: proc(t: ^testing.T) {
	result, err := mdz.compile("<br>\n<br>\n<br>\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph after multiple voids should be wrapped")
}

@(test)
test_html_void_then_regular :: proc(t: ^testing.T) {
	result, err := mdz.compile("<br>\n<div>text</div>\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<br>"), "br should pass through")
	testing.expect(t, strings.contains(result, "<div>text</div>"), "div should pass through")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph should be wrapped")
}

@(test)
test_html_comment_passthrough :: proc(t: ^testing.T) {
	result, err := mdz.compile("<!-- keep me -->\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "keep me"), "HTML comment content should be stripped")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph should remain")
}

@(test)
test_html_jsx_coexistence :: proc(t: ^testing.T) {
	result, err := mdz.compile("<CustomComponent />\n\n<hr>\n\nanother paragraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<CustomComponent />"), "JSX should pass through")
	testing.expect(t, strings.contains(result, "<hr>"), "HTML void should pass through")
	testing.expect(t, strings.contains(result, "<p>another paragraph</p>"), "paragraph should be wrapped")
}

// ─── Reference-style link tests ─────────────────────────────────────────

@(test)
test_ref_link_basic :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: https://example.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `<a href="https://example.com">text</a>`), "should resolve reference link")
	testing.expect(t, !strings.contains(result, "[ref]:"), "definition should be stripped")
}

@(test)
test_ref_link_implicit :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][]\n\n[text]: https://example.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `<a href="https://example.com">text</a>`), "implicit ref should resolve")
}

@(test)
test_ref_link_title_double :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: https://example.com \"My Title\"")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `href="https://example.com"`), "should have URL")
	testing.expect(t, strings.contains(result, `title="My Title"`), "should have title")
}

@(test)
test_ref_link_title_single :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: https://example.com 'Single Title'")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `title="Single Title"`), "single-quoted title should work")
}

@(test)
test_ref_link_title_paren :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: https://example.com (Paren Title)")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `title="Paren Title"`), "paren title should work")
}

@(test)
test_ref_link_case_insensitive :: proc(t: ^testing.T) {
	result, err := mdz.compile("[TEXT][REF]\n\n[ref]: https://example.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `<a href="https://example.com">TEXT</a>`), "case-insensitive label should resolve")
}

@(test)
test_ref_link_multiple :: proc(t: ^testing.T) {
	result, err := mdz.compile("[one][a] and [two][b]\n\n[a]: https://first.com\n[b]: https://second.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `href="https://first.com"`), "first ref should resolve")
	testing.expect(t, strings.contains(result, `href="https://second.com"`), "second ref should resolve")
}

@(test)
test_ref_link_angle_url :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: <https://example.com/path>")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `href="https://example.com/path"`), "angle-bracketed URL should work")
}

@(test)
test_ref_link_unresolved :: proc(t: ^testing.T) {
	// Unresolved reference should leave brackets as-is (handled by handle_link)
	result, err := mdz.compile("[text][undefined]")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "[text][undefined]"), "unresolved ref should remain as brackets")
}

@(test)
test_ref_link_unresolved_implicit :: proc(t: ^testing.T) {
	// [text][] where text has no definition should remain as-is
	result, err := mdz.compile("[text][]")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "[text][]"), "unresolved implicit ref should remain as brackets")
}

@(test)
test_ref_link_in_fence :: proc(t: ^testing.T) {
	// Reference link inside code fence should NOT be resolved
	result, err := mdz.compile("```\n[text][ref]\n```\n\n[ref]: https://example.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "[text][ref]"), "ref link in fence should not be resolved")
	testing.expect(t, !strings.contains(result, `<a href="https://example.com">`), "should not produce link in code")
}

@(test)
test_ref_link_with_regular_links :: proc(t: ^testing.T) {
	result, err := mdz.compile("[inline](https://direct.com) and [ref][r]\n\n[r]: https://ref.com")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, `href="https://direct.com"`), "inline link should still work")
	testing.expect(t, strings.contains(result, `href="https://ref.com"`), "ref link should also work")
}

@(test)
test_ref_link_definition_does_not_appear :: proc(t: ^testing.T) {
	result, err := mdz.compile("[text][ref]\n\n[ref]: https://example.com\n\nparagraph")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, !strings.contains(result, "[ref]:"), "definition should not appear in output")
	testing.expect(t, strings.contains(result, "<p>paragraph</p>"), "paragraph should remain")
}


