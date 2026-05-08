package mdz

// ─── Inline markdown → JSX converter ─────────────────────────────────────────
//
// This is the heart of the speed: no AST, no tokens, just direct byte-scanning
// of the input string and immediate JSX emission into the output buffer.
//
// Scan forward looking for trigger characters (*, `, [, !, {, <, \, &).
// Between triggers, raw text is copied verbatim. At each trigger we check
// if it starts a markdown construct; if so, emit the JSX wrapper and
// recurse into the content; if not, emit the literal character.

// convert_inline scans markdown text and emits JSX directly into w.
// It handles bold, italic, code, links, images, JSX expressions,
// inline JSX, and escaped characters.
convert_inline :: proc(text: string, w: ^Writer) {
    i := 0
    for i < len(text) {
        ch := text[i]
        // Fast path: batch-copy plain text until next trigger character.
        // Trigger set manually inlined (not a function call) to avoid
        // call/ret overhead — this runs for EVERY character.
        if ch != '*' && ch != '`' && ch != '[' && ch != '!' && ch != '{' && ch != '<' && ch != '~' && ch != '\\' && ch != '&' {
            start := i
            i += 1
            for i < len(text) {
                c := text[i]
                if c == '*' || c == '`' || c == '[' || c == '!' || c == '{' || c == '<' || c == '~' || c == '\\' || c == '&' {
                    break
                }
                i += 1
            }
            writer_write(w, text[start:i])
            continue
        }

        switch ch {
        case '*':
            i = handle_asterisk(text, i, w)
        case '`':
            i = handle_backtick(text, i, w)
        case '[':
            i = handle_link(text, i, w)
        case '!':
            if i + 1 < len(text) && text[i + 1] == '[' {
                i = handle_image(text, i, w)
            } else {
                writer_write_byte(w, '!')
                i += 1
            }
        case '{':
            i = handle_expression(text, i, w)
        case '<':
            // Could be inline JSX — try to match a JSX element
            n := try_jsx_element(text[i:], w)
            if n > 0 {
                i += n
            } else {
                writer_write(w, "&lt;")
                i += 1
            }
        case '~':
            i = handle_tilde(text, i, w)
        case '\\':
            if i + 1 < len(text) {
                writer_write_byte(w, text[i + 1])
                i += 2
            } else {
                writer_write_byte(w, '\\')
                i += 1
            }
        case '&':
            if i + 1 < len(text) && text[i + 1] == '#' {
                // HTML entity — pass through
                j := i + 2
                for j < len(text) && text[j] != ';' {
                    j += 1
                }
                if j < len(text) {
                    writer_write(w, text[i:j + 1])
                    i = j + 1
                } else {
                    writer_write(w, "&amp;")
                    i += 1
                }
            } else {
                writer_write(w, "&amp;")
                i += 1
            }
        case:
            // Trigger character that didn't match a construct — emit as literal
            writer_write_byte(w, ch)
            i += 1
        }
    }
}

// ─── Handle * (bold / italic) ──────────────────────────────────────────────

handle_asterisk :: proc(text: string, i: int, w: ^Writer) -> int {
    n := len(text)

    // ***bold italic***
    if i + 2 < n && text[i] == '*' && text[i + 1] == '*' && text[i + 2] == '*' {
        end := find_closing(text, i + 3, "***")
        if end >= 0 {
            writer_write(w, "<em><strong>")
            convert_inline(text[i + 3:end], w)
            writer_write(w, "</strong></em>")
            return end + 3
        }
    }

    // **bold**
    if i + 1 < n && text[i + 1] == '*' {
        end := find_closing(text, i + 2, "**")
        if end >= 0 {
            writer_write(w, "<strong>")
            convert_inline(text[i + 2:end], w)
            writer_write(w, "</strong>")
            return end + 2
        }
    }

    // *italic*
    end := find_closing(text, i + 1, "*")
    if end >= 0 && end - i > 1 {
        writer_write(w, "<em>")
        convert_inline(text[i + 1:end], w)
        writer_write(w, "</em>")
        return end + 1
    }

    // Not formatting — literal asterisk
    writer_write_byte(w, '*')
    return i + 1
}

// ─── Handle ~~strikethrough~~ ──────────────────────────────────────────────

handle_tilde :: proc(text: string, i: int, w: ^Writer) -> int {
    n := len(text)

    // ~~strikethrough~~
    if i + 1 < n && text[i + 1] == '~' {
        end := find_closing(text, i + 2, "~~")
        if end >= 0 && end - i > 2 {
            writer_write(w, "<del>")
            convert_inline(text[i + 2:end], w)
            writer_write(w, "</del>")
            return end + 2
        }
    }

    // Not strikethrough — literal tilde
    writer_write_byte(w, '~')
    return i + 1
}

// ─── Handle `backtick` (inline code) ───────────────────────────────────────

handle_backtick :: proc(text: string, i: int, w: ^Writer) -> int {
    n := len(text)
    // Count the opening backticks
    count := 0
    for i + count < n && text[i + count] == '`' {
        count += 1
    }

    // Build the closing marker
    close_marker: string
    switch count {
    case 1:
        close_marker = "`"
    case 2:
        close_marker = "``"
    case 3:
        close_marker = "```"
    case:
        // Unusual but handle it
        buf := make([]byte, count)
        for j in 0 ..< count {
            buf[j] = '`'
        }
        close_marker = string(buf)
        defer delete(buf)
    }

    end := find_closing(text, i + count, close_marker)
    if end >= 0 {
        writer_write(w, "<code>")
        // Escape HTML entities in code content
        write_escaped(text[i + count:end], w)
        writer_write(w, "</code>")
        return end + count
    }

    // Not a code span — emit literal backticks
    for j in 0 ..< count {
        writer_write_byte(w, '`')
    }
    return i + count
}

// ─── Handle [links](url) ───────────────────────────────────────────────────

handle_link :: proc(text: string, i: int, w: ^Writer) -> int {
    n := len(text)
    // Find the closing bracket
    close_bracket := find_byte(text[i + 1:], ']')
    if close_bracket < 0 {
        writer_write_byte(w, '[')
        return i + 1
    }
    close_bracket += i + 1

    // Check for following (url)
    if close_bracket + 1 < n && text[close_bracket + 1] == '(' {
        close_paren := find_byte(text[close_bracket + 2:], ')')
        if close_paren >= 0 {
            link_text := text[i + 1:close_bracket]
            url := text[close_bracket + 2 : close_bracket + 2 + close_paren]

            // Check for title: [text](url "title") or [text](url 'title')
            url_only := url
            title: string
            if len(url) >= 2 {
                last := url[len(url) - 1]
                if last == '"' || last == '\'' {
                    space_idx := -1
                    for k := len(url) - 2; k >= 0; k -= 1 {
                        if url[k] == ' ' || url[k] == '\t' {
                            space_idx = k
                            break
                        }
                    }
                    if space_idx >= 0 {
                        after_space := url[space_idx + 1:]
                        if (after_space[0] == '"' && last == '"') || (after_space[0] == '\'' && last == '\'') {
                            url_only = url[:space_idx]
                            title = after_space[1:len(after_space) - 1]
                        }
                    }
                }
            }

            writer_write(w, "<a href=\"")
            write_url_escaped(url_only, w)
            if title != "" {
                writer_write(w, "\" title=\"")
                write_escaped(title, w)
            }
            writer_write(w, "\">")
            convert_inline(link_text, w)
            writer_write(w, "</a>")
            return close_bracket + 2 + close_paren + 1
        }
    }

    // Check for reference-style link [text][ref]
    if close_bracket + 1 < n && text[close_bracket + 1] == '[' {
        close_ref := find_byte(text[close_bracket + 2:], ']')
        if close_ref >= 0 {
            ref := text[close_bracket + 2 : close_bracket + 2 + close_ref]
            _ = ref
            // For simplicity, emit link text without resolving reference
            writer_write(w, "<a>")
            convert_inline(text[i + 1:close_bracket], w)
            writer_write(w, "</a>")
            return close_bracket + 2 + close_ref + 1
        }
    }

    // Not a link — literal bracket
    writer_write_byte(w, '[')
    return i + 1
}

// ─── Handle ![images](url) ─────────────────────────────────────────────────

handle_image :: proc(text: string, i: int, w: ^Writer) -> int {
    n := len(text)
    // We already verified text[i] == '!' and text[i+1] == '['
    close_bracket := find_byte(text[i + 2:], ']')
    if close_bracket < 0 {
        writer_write_byte(w, '!')
        return i + 1
    }
    close_bracket += i + 2

    if close_bracket + 1 < n && text[close_bracket + 1] == '(' {
        close_paren := find_byte(text[close_bracket + 2:], ')')
        if close_paren >= 0 {
            alt := text[i + 2:close_bracket]
            url := text[close_bracket + 2 : close_bracket + 2 + close_paren]
            writer_write(w, "<img src=\"")
            write_url_escaped(url, w)
            writer_write(w, "\" alt=\"")
            write_escaped(alt, w)
            writer_write(w, "\"/>")
            return close_bracket + 2 + close_paren + 1
        }
    }

    writer_write_byte(w, '!')
    return i + 1
}

// ─── Handle {expressions} in markdown ──────────────────────────────────────

handle_expression :: proc(text: string, i: int, w: ^Writer) -> int {
    // Find matching closing brace, accounting for nesting
    depth := 1
    j := i + 1
    for j < len(text) && depth > 0 {
        switch text[j] {
        case '{':
            depth += 1
        case '}':
            depth -= 1
        case '\'', '"':
            // Skip over string contents
            quote := text[j]
            j += 1
            for j < len(text) && text[j] != quote {
                if text[j] == '\\' {
                    j += 1
                }
                j += 1
            }
        case '`':
            // Skip template literal
            j += 1
            for j < len(text) && text[j] != '`' {
                if text[j] == '\\' {
                    j += 1
                }
                j += 1
            }
        case:
            // nothing special
        }
        if depth > 0 {
            j += 1
        }
    }
    if depth == 0 {
        // Include the closing brace
        writer_write(w, text[i:j + 1])
        return j + 1
    }
    // Unmatched — emit as literal
    writer_write_byte(w, '{')
    return i + 1
}

// ─── Inline JSX detection ──────────────────────────────────────────────────

// try_jsx_element checks if text starts with a JSX element (<Tag> or <Tag/>).
// If so, it scans to find the end of the element and writes it to w.
// Returns the number of bytes consumed, or 0 if it's not JSX.
try_jsx_element :: proc(text: string, w: ^Writer) -> int {
    if len(text) == 0 || text[0] != '<' {
        return 0
    }

    // < followed by identifier (component or HTML tag)
    start := 1
    if start >= len(text) {
        return 0
    }

    // Self-closing: </
    if text[start] == '/' {
        start += 1
    }

    if start >= len(text) || !is_jsx_identifier_start(text[start]) {
        return 0
    }

    // Scan forward to find the matching >
    depth := 1
    in_string := false
    string_char: byte = 0
    in_self_close := false
    j := start

    for j < len(text) && depth > 0 {
        ch := text[j]
        if in_string {
            if ch == '\\' {
                j += 2
                continue
            }
            if ch == string_char {
                in_string = false
            }
            j += 1
            continue
        }

        switch ch {
        case '\'', '"':
            in_string = true
            string_char = ch
        case '{':
            depth += 1
        case '}':
            depth -= 1
        case '<':
            depth += 1
        case '>':
            depth -= 1
            if depth == 0 && j > 0 && text[j - 1] == '/' {
                in_self_close = true
            }
        case:
            // nothing special
        }
        if depth > 0 {
            j += 1
        }
    }

    if depth == 0 {
        writer_write(w, text[:j + 1])
        return j + 1
    }

    return 0
}

// ─── Closing delimiter search ──────────────────────────────────────────────

// find_closing searches for delimiter in text starting at start.
// It handles nesting of the same delimiter type (e.g. * inside **).
// Returns the index of the first character of the match, or -1.
find_closing :: proc(text: string, start: int, delimiter: string) -> int {
    if start >= len(text) {
        return -1
    }
    dlen := len(delimiter)
    if dlen == 0 {
        return -1
    }
    first := delimiter[0]

    // Single-char delimiter fast path: avoid substring comparison
    if dlen == 1 {
        idx := find_byte_from(text, first, start)
        if idx >= 0 && (idx == 0 || text[idx - 1] != '\\') {
            return idx
        }
        return -1
    }

    i := start
    for i < len(text) {
        idx := find_byte_from(text, first, i)
        if idx < 0 {
            return -1
        }
        if idx + dlen <= len(text) && text[idx:idx + dlen] == delimiter {
            if idx > 0 && text[idx - 1] == '\\' {
                i = idx + 1
                continue
            }
            return idx
        }
        i = idx + 1
    }
    return -1
}

// find_closing_brace finds the matching closing brace for an opening brace at start.
// Returns the index of '}', or -1.
find_closing_brace :: proc(text: string, start: int) -> int {
    depth := 1
    i := start
    for i < len(text) && depth > 0 {
        switch text[i] {
        case '{':
            depth += 1
        case '}':
            depth -= 1
        case '\'', '"':
            quote := text[i]
            i += 1
            for i < len(text) && text[i] != quote {
                if text[i] == '\\' {
                    i += 1
                }
                i += 1
            }
        }
        if depth > 0 {
            i += 1
        }
    }
    if depth == 0 {
        return i
    }
    return -1
}

// ─── Escaping utilities ───────────────────────────────────────────────────

// write_escaped writes s to w with HTML entities escaped
write_escaped :: proc(s: string, w: ^Writer) {
    i := 0
    for i < len(s) {
        ch := s[i]
        if ch != '&' && ch != '<' && ch != '>' && ch != '"' && ch != '\'' {
            start := i
            i += 1
            for i < len(s) {
                c := s[i]
                if c == '&' || c == '<' || c == '>' || c == '"' || c == '\'' {
                    break
                }
                i += 1
            }
            writer_write(w, s[start:i])
            continue
        }
        switch ch {
        case '&':
            writer_write(w, "&amp;")
        case '<':
            writer_write(w, "&lt;")
        case '>':
            writer_write(w, "&gt;")
        case '"':
            writer_write(w, "&quot;")
        case '\'':
            writer_write(w, "&#39;")
        }
        i += 1
    }
}

// write_url_escaped writes a URL to w, escaping quotes
write_url_escaped :: proc(s: string, w: ^Writer) {
    i := 0
    for i < len(s) {
        ch := s[i]
        if ch != '"' && ch != '&' {
            start := i
            i += 1
            for i < len(s) {
                c := s[i]
                if c == '"' || c == '&' {
                    break
                }
                i += 1
            }
            writer_write(w, s[start:i])
            continue
        }
        switch ch {
        case '"':
            writer_write(w, "&quot;")
        case '&':
            writer_write(w, "&amp;")
        }
        i += 1
    }
}
