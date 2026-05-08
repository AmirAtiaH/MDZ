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
	testing.expect(t, strings.contains(result, "</ul>\n<ol>"), "should switch from ul to ol")
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
test_table_inline_formatting :: proc(t: ^testing.T) {
	result, err := mdz.compile("| **bold** | *italic* |\n|---|---|\n| `code` | text |")
	if err != nil { testing.fail(t); return }
	defer delete(result)
	testing.expect(t, strings.contains(result, "<strong>bold</strong>"))
	testing.expect(t, strings.contains(result, "<em>italic</em>"))
	testing.expect(t, strings.contains(result, "<code>code</code>"))
}
