package mdz

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"

// compile transforms an MDX source string into a JSX module string.
// Pre-allocates output buffer with input * 2 to accommodate JSX expansion.
// The caller owns the returned string and should delete it.
compile :: proc(input: string) -> (string, Error) {
	return compile_with(input, nil)
}

// compile_with is like compile but accepts an optional TransformConfig.
// Pass nil for default behavior (all blocks processed normally).
compile_with :: proc(input: string, config: ^TransformConfig) -> (string, Error) {
	return _compile(input, config, nil)
}

// compile_with_plugins is like compile_with but also accepts a plugin pipeline.
// Plugins can intercept block processing (BeforeBlock) or transform output
// after processing (AfterBlock). TransformConfig still applies first.
compile_with_plugins :: proc(input: string, config: ^TransformConfig, pipeline: ^PluginPipeline) -> (string, Error) {
	return _compile(input, config, pipeline)
}

@(private)
_compile :: proc(input: string, config: ^TransformConfig, pipeline: ^PluginPipeline) -> (string, Error) {
	module_w, body_w: Writer
	writer_init(&module_w, len(input) / 4)
	writer_init(&body_w, len(input) * 2)
	defer {
		writer_destroy(&module_w)
		writer_destroy(&body_w)
	}

	// Pre-process: extract $$...$$ and $...$ math into placeholders so
	// multi-line display math survives the per-line paragraph processing.
	use_preprocessed := input
	math_subs: [dynamic]string
	defer delete(math_subs)
	when Math {
		ok := preprocess_math(input, &use_preprocessed, &math_subs)
		if ok != nil {
			return "", Compile_Error{message = "math preprocess failed"}
		}
	}

	// Pre-process: convert setext headings (underlined === / ---) to # / ## syntax.
	use_preprocessed = preprocess_setext_headings(use_preprocessed)

	// Pre-process: extract footnote definitions ([^id]: content) and
	// strip them from the input stream so they don't appear as paragraphs.
	footnote_defs: [dynamic]FootnoteDef
	defer delete(footnote_defs)
	when Footnote {
		fok := preprocess_footnotes(use_preprocessed, &use_preprocessed, &footnote_defs)
		if fok != nil {
			return "", Compile_Error{message = "footnote preprocess failed"}
		}
	}

	// Pre-process: resolve reference-style links ([text][ref]) by collecting
	// definitions and replacing references with inline links.
	when ReferenceLink {
		use_preprocessed = preprocess_reference_links(use_preprocessed)
	}

	pos := 0
	for pos < len(use_preprocessed) {
		pos = skip_blank_lines(use_preprocessed, pos)
		if pos >= len(use_preprocessed) {
			break
		}

		bt := classify_block(use_preprocessed, pos)

		// Check transform config for early exit
		action := NodeAction.Keep
		if config != nil {
			action = get_action(config, bt, use_preprocessed, pos)
		}
		if action == .Remove {
			skip_removed_block(use_preprocessed, &pos, bt)
			continue
		}

		// Run before-block plugins — they can take over or remove
		if pipeline != nil {
			plugin_result := run_before_plugins(pipeline, use_preprocessed, &pos, &body_w, &module_w, bt)
			if plugin_result == .Remove {
				skip_removed_block(use_preprocessed, &pos, bt)
				continue
			}
			if plugin_result == .Handled {
				// pos was already advanced by the plugin
				continue
			}
		}

		// Capture output start position for after-block plugins
		body_before := len(body_w.buf)

		#partial switch bt {
		case .Frontmatter:
			process_frontmatter(use_preprocessed, &pos)

		case .Fence:
			process_fence(use_preprocessed, &pos, &body_w)

		case .Import, .Export, .JS_Module:
			process_js_block(use_preprocessed, &pos, &module_w)

		case .JSX_Element, .JS_Expression:
			process_js_block(use_preprocessed, &pos, &body_w)

		case .Heading:
			process_heading(use_preprocessed, &pos, &body_w)

		case .Blockquote:
			process_blockquote(use_preprocessed, &pos, &body_w)

		case .List:
			process_list(use_preprocessed, &pos, &body_w)

		case .ThematicBreak:
			process_thematic_break(use_preprocessed, &pos, &body_w)

		case .DefList:
			when DefList {
				// Standalone : line with no preceding term — skip
				pos = skip_line(use_preprocessed, pos)
			} else {
				return "", Compile_Error{offset = pos, message = "unhandled block type"}
			}

		case .Comment:
			when Comment {
				process_comment(use_preprocessed, &pos)
			} else {
				return "", Compile_Error{offset = pos, message = "unhandled block type"}
			}

		case .Table:
			when Tables {
				process_table(use_preprocessed, &pos, &body_w)
			} else {
				process_paragraph(use_preprocessed, &pos, &body_w)
			}

		case .Paragraph:
			when DefList {
				if is_deflist_next(use_preprocessed, pos) {
					process_definition_list(use_preprocessed, &pos, &body_w)
					break
				}
			}
			process_paragraph(use_preprocessed, &pos, &body_w)

		case .BlankLine:
			pos += 1

		case .Unknown:
			return "", Compile_Error{offset = pos, message = "unrecognized block"}

		case:
			return "", Compile_Error{offset = pos, message = "unhandled block type"}
		}

		// Run after-block plugins with what was just written
		if pipeline != nil && bt != .BlankLine && bt != .Unknown {
			written := string(body_w.buf[body_before:])
			run_after_plugins(pipeline, use_preprocessed, pos, &body_w, &module_w, bt, written)
		}
	}

	// Append footnotes section at the end of body
	when Footnote {
		if len(footnote_defs) > 0 {
			append_footnotes_section(&body_w, &footnote_defs)
		}
	}

	// Assemble final output: module code + wrapped body.
	output := strings.concatenate([]string{
		writer_get(&module_w),
		"\nfunction MDXContent(props = {}) {\n  return <>\n",
		writer_get(&body_w),
		"\n  </>\n}\n\nexport default MDXContent\n",
	})

	// Restore math placeholders in output
	when Math {
		if len(math_subs) > 0 {
			result := restore_math(output, &math_subs)
			delete(output)
			return result, nil
		}
	}

	return output, nil
}

// skip_removed_block advances pos past a block that was removed by config/plugin.
skip_removed_block :: proc(input: string, pos: ^int, bt: BlockType) {
	#partial switch bt {
	case .JSX_Element, .JS_Expression, .Import, .Export, .JS_Module:
		pos^ = find_js_block_end(input, pos^)
	case .Fence:
		pos^ = skip_fence(input, pos^)
	case .Comment:
		process_comment(input, pos)
	case:
		pos^ += 1
	}
}

// preprocess_math scans the input for $$...$$ display math regions and
// replaces them with placeholders. Inline $...$ is handled by handle_math.
preprocess_math :: proc(input: string, output: ^string, subs: ^[dynamic]string) -> Error {
    buf := strings.builder_make_len_cap(0, len(input) + 256, context.temp_allocator)
    i := 0
    idx := 0
    for i < len(input) {
        // Skip fenced code blocks — $$ inside fences is not math
        if input[i] == '`' || input[i] == '~' {
            fence_len := count_leading(input[i:], input[i])
            if fence_len >= 3 {
                marker := input[i]
                fence_start := i
                i += fence_len
                for i < len(input) && input[i] != '\n' { i += 1 }
                if i < len(input) && input[i] == '\n' { i += 1 }
                for i < len(input) {
                    if input[i] == marker && count_leading(input[i:], marker) >= fence_len {
                        i += fence_len
                        for i < len(input) && input[i] != '\n' { i += 1 }
                        if i < len(input) && input[i] == '\n' { i += 1 }
                        break
                    }
                    for i < len(input) && input[i] != '\n' { i += 1 }
                    if i < len(input) { i += 1 }
                }
                strings.write_string(&buf, input[fence_start:i])
                continue
            }
        }

        if input[i] == '$' && i + 1 < len(input) && input[i + 1] == '$' {
            i += 2
            math_start := i
            for i < len(input) {
                if input[i] == '$' && i + 1 < len(input) && input[i + 1] == '$' {
                    math_content := input[math_start:i]
                    i += 2
                    placeholder := fmt.tprintf("\x00MATH_%d\x00", idx, context.temp_allocator)
                    strings.write_string(&buf, placeholder)
                    append(subs, math_content)
                    idx += 1
                    break
                }
                if input[i] == '\\' && i + 1 < len(input) && input[i + 1] == '$' {
                    i += 2
                    continue
                }
                i += 1
            }
            if i >= len(input) {
                strings.write_string(&buf, "$$")
                strings.write_string(&buf, input[math_start:])
            }
            continue
        }
        strings.write_byte(&buf, input[i])
        i += 1
    }
    output^ = strings.to_string(buf)
    return nil
}

// restore_math replaces math placeholders with the original math text wrapped in math HTML.
restore_math :: proc(output: string, subs: ^[dynamic]string) -> string {
    buf := strings.builder_make_len_cap(0, len(output) + 1024)
    i := 0
    for i < len(output) {
        if output[i] == 0 && i + 7 < len(output) && output[i:i+6] == "\x00MATH_" {
            j := i + 6
            num_start := j
            for j < len(output) && output[j] != '\x00' { j += 1 }
            if j < len(output) && num_start < j {
                index, ok := strconv.parse_int(output[num_start:j], 10)
                if ok && index >= 0 && index < len(subs) {
                    strings.write_string(&buf, "<pre><code class=\"language-math\">")
                    write_escaped_to_builder(subs[index], &buf)
                    strings.write_string(&buf, "</code></pre>")
                    i = j + 1
                    continue
                }
            }
        }
        strings.write_byte(&buf, output[i])
        i += 1
    }
    return strings.to_string(buf)
}

// write_escaped_to_builder writes s to a strings.Builder with HTML entities escaped.
write_escaped_to_builder :: proc(s: string, b: ^strings.Builder) {
    for i in 0 ..< len(s) {
        switch s[i] {
        case '&': strings.write_string(b, "&amp;")
        case '<': strings.write_string(b, "&lt;")
        case '>': strings.write_string(b, "&gt;")
        case '"': strings.write_string(b, "&quot;")
        case '\'': strings.write_string(b, "&#39;")
        case: strings.write_byte(b, s[i])
        }
    }
}

// get_action returns the NodeAction from config for the given block type.
get_action :: proc(config: ^TransformConfig, bt: BlockType, input: string, pos: int) -> NodeAction {
    #partial switch bt {
    case .Heading:
        if config.heading != nil { return config.heading(input, pos) }
    case .Paragraph:
        if config.paragraph != nil { return config.paragraph(input, pos) }
    case .Fence:
        if config.fence != nil { return config.fence(input, pos) }
    case .Blockquote:
        if config.blockquote != nil { return config.blockquote(input, pos) }
    case .List:
        if config.list != nil { return config.list(input, pos) }
    case .Table:
        when Tables {
            if config.table != nil { return config.table(input, pos) }
        }
    case .JS_Expression:
        if config.expression != nil { return config.expression(input, pos) }
    case .JSX_Element:
        if config.jsx != nil { return config.jsx(input, pos) }
    case .DefList:
        when DefList {
            if config.deflist != nil { return config.deflist(input, pos) }
        }
    case .Comment:
        when Comment {
            if config.comment != nil { return config.comment(input, pos) }
        }
    }
    return .Keep
}

// preprocess_setext_headings converts setext heading underlines (=== / ---)
// to # / ## syntax so the single-pass compiler handles them as regular headings.
// A line of only === (3+) preceded by non-blank content → H1 (#)
// A line of only --- (3+) preceded by non-blank content → H2 (##)
preprocess_setext_headings :: proc(input: string) -> string {
    buf := strings.builder_make_len_cap(0, len(input), context.temp_allocator)

    lines := make([dynamic]string)
    defer delete(lines)

    line_start := 0
    for i := 0; i <= len(input); i += 1 {
        if i == len(input) || input[i] == '\n' {
            append(&lines, input[line_start:i])
            line_start = i + 1
        }
    }

    i := 0
    for i < len(lines) {
        // Skip frontmatter regions (--- ... ---) so setext detection
        // doesn't misidentify the closing --- as a heading underline.
        if trim_space(lines[i]) == "---" {
            // Check if this starts frontmatter (only at position 0)
            fm_end := -1
            if i == 0 {
                for j := i + 1; j < len(lines); j += 1 {
                    if trim_space(lines[j]) == "---" {
                        fm_end = j
                        break
                    }
                }
            }
            if fm_end >= 0 {
                for j := i; j <= fm_end; j += 1 {
                    strings.write_string(&buf, lines[j])
                    if j + 1 < len(lines) {
                        strings.write_byte(&buf, '\n')
                    }
                }
                i = fm_end + 1
                continue
            }
        }
        // Look ahead: if next line is a setext underline, convert current + next to heading
        if i + 1 < len(lines) {
            trimmed := trim_space(lines[i + 1])
            level := 0
            if len(trimmed) >= 3 {
                eq_count := count_leading(trimmed, '=')
                if eq_count >= 3 && eq_count == len(trimmed) {
                    level = 1
                }
                if level == 0 {
                    dash_count := count_leading(trimmed, '-')
                    if dash_count >= 3 && dash_count == len(trimmed) {
                        level = 2
                    }
                }
            }
            if level > 0 && len(trim_space(lines[i])) > 0 {
                for j := 0; j < level; j += 1 {
                    strings.write_byte(&buf, '#')
                }
                strings.write_byte(&buf, ' ')
                strings.write_string(&buf, trim_space(lines[i]))
                strings.write_byte(&buf, '\n')
                i += 2
                continue
            }
        }
        strings.write_string(&buf, lines[i])
        if i + 1 < len(lines) {
            strings.write_byte(&buf, '\n')
        }
        i += 1
    }

    return strings.to_string(buf)
}

// FootnoteDef represents a single GFM footnote definition.
FootnoteDef :: struct { id, content: string }

// preprocess_footnotes scans input for GFM footnote definitions ([^id]: content).
// Strips them from the output and collects them into defs.
preprocess_footnotes :: proc(input: string, output: ^string, defs: ^[dynamic]FootnoteDef) -> Error {
    buf := strings.builder_make_len_cap(0, len(input), context.temp_allocator)
    i := 0
    for i < len(input) {
        // Check if the current position starts a footnote definition
        j := i
        for j < len(input) && (input[j] == ' ' || input[j] == '\t') { j += 1 }
        if j + 3 < len(input) && input[j] == '[' && input[j + 1] == '^' {
            close_bracket := find_byte_from(input, ']', j + 2)
            if close_bracket >= 0 && close_bracket + 1 < len(input) && input[close_bracket + 1] == ':' {
                id := input[j + 2:close_bracket]
                content_start := close_bracket + 2
                for content_start < len(input) && input[content_start] == ' ' { content_start += 1 }
                line_end := content_start
                for line_end < len(input) && input[line_end] != '\n' { line_end += 1 }
                content := input[content_start:line_end]
                append(defs, FootnoteDef{id = id, content = content})
                i = line_end
                if i < len(input) && input[i] == '\n' { i += 1 }
                continue
            }
        }
        // Bulk copy to end of line for non-footnote lines
        line_end := i
        for line_end < len(input) && input[line_end] != '\n' { line_end += 1 }
        if line_end < len(input) { line_end += 1 }
        strings.write_string(&buf, input[i:line_end])
        i = line_end
    }
    output^ = strings.to_string(buf)
    return nil
}

// append_footnotes_section renders collected footnote definitions as HTML and
// appends them to the body writer.
append_footnotes_section :: proc(w: ^Writer, defs: ^[dynamic]FootnoteDef) {
    if len(defs) == 0 { return }
    writer_write(w, "\n<section class=\"footnotes\">\n<ol>\n")
    for def in defs {
        writer_write(w, "<li id=\"fn:")
        write_escaped(def.id, w)
        writer_write(w, "\">")
        convert_inline(def.content, w)
        writer_write(w, " <a href=\"#fnref:")
        write_escaped(def.id, w)
        writer_write(w, "\" class=\"footnote-backref\">↩</a>")
        writer_write(w, "</li>\n")
    }
    writer_write(w, "</ol>\n</section>\n")
}

// compile_file reads an MDX file and compiles it to a JSX module string.
// The caller owns the returned string and should delete it.
compile_file :: proc(path: string) -> (string, Error) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil {
        return "", Compile_Error{message = fmt.tprintf("failed to read file '%s': %v", path, err)}
    }
    defer delete(data)
    return compile(string(data))
}

// normalize_ref_label normalizes a reference label for lookup:
// lowercase, trim whitespace, collapse internal whitespace to single space.
normalize_ref_label :: proc(label: string) -> string {
    if len(label) == 0 { return label }
    buf := strings.builder_make_len_cap(0, len(label), context.temp_allocator)
    wrote_space := false
    wrote_char := false
    start := 0
    for start < len(label) && (label[start] == ' ' || label[start] == '\t' || label[start] == '\n') {
        start += 1
    }
    end := len(label)
    for end > start && (label[end-1] == ' ' || label[end-1] == '\t' || label[end-1] == '\n') {
        end -= 1
    }
    for i := start; i < end; i += 1 {
        ch := label[i]
        if ch == ' ' || ch == '\t' || ch == '\n' {
            if !wrote_space && wrote_char {
                strings.write_byte(&buf, ' ')
                wrote_space = true
            }
        } else {
            if ch >= 'A' && ch <= 'Z' {
                ch += 32
            }
            strings.write_byte(&buf, ch)
            wrote_char = true
            wrote_space = false
        }
    }
    return strings.to_string(buf)
}

// preprocess_reference_links scans the input for reference-style link definitions
// ([label]: url "title") and replaces all reference usages ([text][ref], [text][])
// with inline links ([text](url "title")). Definitions are stripped from output.
// Fenced code blocks are skipped during replacement.
preprocess_reference_links :: proc(input: string) -> string {
    // Phase 1: collect definitions and strip them from input
    RefEntry :: struct { url, title: string }
    defs := make(map[string]RefEntry, 16, context.temp_allocator)

    buf1 := strings.builder_make_len_cap(0, len(input), context.temp_allocator)
    i := 0
    for i < len(input) {
        line_start := i
        for i < len(input) && input[i] != '\n' { i += 1 }
        has_newline := i < len(input) && input[i] == '\n'
        line := input[line_start:i]
        if has_newline { i += 1 }

        // Check if this line is a reference definition: optional indent + [label]:
        trimmed := line
        indent := 0
        for indent < len(trimmed) && indent < 4 && (trimmed[indent] == ' ' || trimmed[indent] == '\t') {
            indent += 1
        }
        is_definition := false
        if indent < len(trimmed) && trimmed[indent] == '[' {
            close_bracket := find_byte(trimmed[indent+1:], ']')
            if close_bracket >= 0 && indent + 1 + close_bracket + 1 < len(trimmed) && trimmed[indent + 1 + close_bracket + 1] == ':' {
                label := trimmed[indent+1:][:close_bracket]
                rest := trimmed[indent + close_bracket + 3:]
                rest_start := 0
                for rest_start < len(rest) && rest[rest_start] == ' ' { rest_start += 1 }
                rest = rest[rest_start:]

                url: string
                title: string

                if len(rest) > 0 && rest[0] == '<' {
                    gt := find_byte(rest[1:], '>')
                    if gt >= 0 {
                        url = rest[1:][:gt]
                        rest = rest[gt+2:]
                    } else {
                        url = rest[1:]
                        rest = ""
                    }
                } else {
                    space := find_byte(rest, ' ')
                    if space >= 0 {
                        url = rest[:space]
                        rest = rest[space+1:]
                    } else {
                        url = rest
                        rest = ""
                    }
                }

                for len(rest) > 0 && (rest[0] == ' ' || rest[0] == '\t') {
                    rest = rest[1:]
                }
                if len(rest) > 0 {
                    if (rest[0] == '"' || rest[0] == '\'') && len(rest) >= 2 {
                        end_quote := find_byte(rest[1:], rest[0])
                        if end_quote >= 0 {
                            title = rest[1:][:end_quote]
                        }
                    } else if rest[0] == '(' {
                        close_paren := find_byte(rest[1:], ')')
                        if close_paren >= 0 {
                            title = rest[1:][:close_paren]
                        }
                    }
                }

                norm := normalize_ref_label(label)
                defs[norm] = RefEntry{url, title}
                is_definition = true
            }
        }

        if !is_definition {
            strings.write_string(&buf1, line)
            if has_newline {
                strings.write_byte(&buf1, '\n')
            }
        }
    }

    intermediate := strings.to_string(buf1)

    // Early exit: no definitions found, return original input unchanged.
    // This is the common case — most Markdown files have zero reference definitions,
    // and this avoids the Phase 2 allocation and full scan entirely.
    if len(defs) == 0 {
        return input
    }

    // Phase 2: replace [text][ref] and [text][] with [text](url "title")
    // Use range-based bulk writes instead of per-byte write_byte for the unchanged regions.
    buf2 := strings.builder_make_len_cap(0, len(intermediate), context.temp_allocator)
    range_start := 0
    j := 0
    for j < len(intermediate) {
        // Skip fenced code blocks
        if intermediate[j] == '`' && count_leading(intermediate[j:], '`') >= 3 {
            if range_start < j {
                strings.write_string(&buf2, intermediate[range_start:j])
            }
            fence_len := count_leading(intermediate[j:], '`')
            fence_start := j
            j += fence_len
            for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
            if j < len(intermediate) && intermediate[j] == '\n' { j += 1 }
            for j < len(intermediate) {
                if intermediate[j] == '`' && count_leading(intermediate[j:], '`') >= fence_len {
                    j += fence_len
                    for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
                    if j < len(intermediate) && intermediate[j] == '\n' { j += 1 }
                    break
                }
                for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
                if j < len(intermediate) { j += 1 }
            }
            strings.write_string(&buf2, intermediate[fence_start:j])
            range_start = j
            continue
        }

        // Skip tilde fences too
        if intermediate[j] == '~' && count_leading(intermediate[j:], '~') >= 3 {
            if range_start < j {
                strings.write_string(&buf2, intermediate[range_start:j])
            }
            fence_len := count_leading(intermediate[j:], '~')
            fence_start := j
            j += fence_len
            for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
            if j < len(intermediate) && intermediate[j] == '\n' { j += 1 }
            for j < len(intermediate) {
                if intermediate[j] == '~' && count_leading(intermediate[j:], '~') >= fence_len {
                    j += fence_len
                    for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
                    if j < len(intermediate) && intermediate[j] == '\n' { j += 1 }
                    break
                }
                for j < len(intermediate) && intermediate[j] != '\n' { j += 1 }
                if j < len(intermediate) { j += 1 }
            }
            strings.write_string(&buf2, intermediate[fence_start:j])
            range_start = j
            continue
        }

        // Check for [text][ref] or [text][]
        if intermediate[j] == '[' {
            close1 := find_byte(intermediate[j+1:], ']')
            if close1 >= 0 {
                after1 := j + 1 + close1 + 1
                // Must be followed by [ref] or []
                if after1 < len(intermediate) && intermediate[after1] == '[' {
                    close2 := find_byte(intermediate[after1+1:], ']')
                    if close2 >= 0 {
                        text := intermediate[j+1:][:close1]
                        ref_text := intermediate[after1+1:][:close2]
                        ref_key: string
                        if len(ref_text) == 0 {
                            // Implicit ref: [text][] — look up text as the ref
                            ref_key = normalize_ref_label(text)
                        } else {
                            ref_key = normalize_ref_label(ref_text)
                        }

                        entry, found := defs[ref_key]
                        if found {
                            // Flush accumulated plain text before the reference marker
                            if range_start < j {
                                strings.write_string(&buf2, intermediate[range_start:j])
                            }
                            // Replace with inline link [text](url "title")
                            strings.write_byte(&buf2, '[')
                            strings.write_string(&buf2, text)
                            strings.write_byte(&buf2, ']')
                            strings.write_byte(&buf2, '(')
                            strings.write_string(&buf2, entry.url)
                            if entry.title != "" {
                                strings.write_byte(&buf2, ' ')
                                strings.write_byte(&buf2, '"')
                                strings.write_string(&buf2, entry.title)
                                strings.write_byte(&buf2, '"')
                            }
                            strings.write_byte(&buf2, ')')
                            j = after1 + 1 + close2 + 1
                            range_start = j
                            continue
                        }
                    }
                }
            }
        }

        j += 1
    }

    // Flush remaining unchanged range
    if range_start < j {
        strings.write_string(&buf2, intermediate[range_start:j])
    }

    return strings.to_string(buf2)
}
