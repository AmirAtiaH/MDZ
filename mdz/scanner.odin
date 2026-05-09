package mdz

// ─── Fast byte helpers ────────────────────────────────────────────────────────
// Hand-rolled single-byte search avoids overhead of general substring search.
// These get inlined and the compiler can vectorize the simple loop.

// find_byte returns the first index of b in s, or -1.
find_byte :: proc(s: string, b: byte) -> int {
    for i in 0 ..< len(s) {
        if s[i] == b {
            return i
        }
    }
    return -1
}

// find_byte_from returns the first index of b in s starting at start, or -1.
find_byte_from :: proc(s: string, b: byte, start: int) -> int {
    for i in start ..< len(s) {
        if s[i] == b {
            return i
        }
    }
    return -1
}

// count_leading counts how many times b appears at the start of s.
count_leading :: proc(s: string, b: byte) -> int {
    n := 0
    for n < len(s) && s[n] == b {
        n += 1
    }
    return n
}

// skip_blank_lines advances past any blank (whitespace-only) lines.
// Returns the new position.
skip_blank_lines :: proc(input: string, pos: int) -> int {
    i := pos
    for i < len(input) {
        ch := input[i]
        if ch == '\n' || ch == ' ' || ch == '\t' || ch == '\r' {
            i += 1
        } else {
            return i
        }
    }
    return i
}

// skip_line advances to the next newline and returns the new position
// (past the newline).
skip_line :: proc(input: string, pos: int) -> int {
    i := pos
    for i < len(input) && input[i] != '\n' {
        i += 1
    }
    if i < len(input) {
        i += 1 // skip \n
    }
    return i
}

// is_digit returns true if ch is an ASCII digit
is_digit :: proc(ch: byte) -> bool {
    return ch >= '0' && ch <= '9'
}

// is_letter returns true if ch is an ASCII letter
is_letter :: proc(ch: byte) -> bool {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

// is_jsx_identifier_start returns true if ch can start a JSX identifier
is_jsx_identifier_start :: proc(ch: byte) -> bool {
    return is_letter(ch) || ch == '_' || ch == '$'
}

// is_jsx_identifier_continue returns true if ch can continue a JSX identifier
is_jsx_identifier_continue :: proc(ch: byte) -> bool {
    return is_letter(ch) || is_digit(ch) || ch == '_' || ch == '$' || ch == '-'
}

// ─── Block classification ────────────────────────────────────────────────────

// classify_block determines the BlockType at the given position.
// It only examines the first line to decide — multi-line blocks
// (fences, JS blocks, lists) are handled by their processors.
classify_block :: proc(input: string, pos: int) -> BlockType {
    if pos >= len(input) {
        return .BlankLine
    }

    // Skip leading whitespace (but not newlines — blank lines are handled upstream)
    start := pos
    for start < len(input) && (input[start] == ' ' || input[start] == '\t') {
        start += 1
    }
    if start >= len(input) {
        return .BlankLine
    }

    ch := input[start]

    // Frontmatter — only at file position 0 (must be the first thing in the file).
    // This early-exit avoids an O(n) scan for closing `---` on every `---`
    // thematic break in the middle of the file.
    if pos == 0 && ch == '-' && start + 2 < len(input) && input[start:start + 3] == "---" {
        if start == 0 {
            // Quick scan for closing --- on a subsequent line
            has_closing := false
            ci := start + 3
            for ci + 3 < len(input) {
                nl := find_byte_from(input, '\n', ci)
                if nl < 0 {
                    break
                }
                if nl + 3 < len(input) && input[nl+1:nl+4] == "---" {
                    cj := nl + 4
                    for cj < len(input) && input[cj] != '\n' {
                        if input[cj] != ' ' && input[cj] != '\t' {
                            cj = -1
                            break
                        }
                        cj += 1
                    }
                    if cj >= 0 {
                        has_closing = true
                    }
                    break
                }
                ci = nl + 1
            }
            if has_closing {
                return .Frontmatter
            }
        }
    }

    // Code fence (``` or ~~~)
    if (ch == '`' || ch == '~') && count_leading(input[start:], ch) >= 3 {
        return .Fence
    }

    // Thematic break (---, ***, ___)
    if ch == '-' || ch == '*' || ch == '_' {
        // Check if the entire line is just the character (3+) and optional spaces
        count := count_leading(input[start:], ch)
        if count >= 3 {
            rest := start + count
            all_delim := true
            for rest < len(input) && input[rest] != '\n' {
                if input[rest] != ' ' && input[rest] != '\t' {
                    all_delim = false
                    break
                }
                rest += 1
            }
            if all_delim {
                return .ThematicBreak
            }
        }
        // If it's a list marker (- or * followed by space)
        if (ch == '-' || ch == '*') && start + 1 < len(input) && input[start + 1] == ' ' {
            return .List
        }
        // Otherwise it's probably a paragraph
        return .Paragraph
    }

    // Heading
    if ch == '#' {
        return .Heading
    }

    // Blockquote
    if ch == '>' {
        return .Blockquote
    }

    // Ordered list (digits followed by ". " or ") ")
    if is_digit(ch) {
        j := start
        for j < len(input) && is_digit(input[j]) {
            j += 1
        }
        if j < len(input) && (input[j] == '.' || input[j] == ')') && j + 1 < len(input) && input[j + 1] == ' ' {
            return .List
        }
    }

    // Comment: {/* ... */} or <!-- ... -->
    when Comment {
        if ch == '{' && start + 2 < len(input) && input[start:start + 3] == "{/*" {
            return .Comment
        }
        if ch == '<' && start + 3 < len(input) && input[start:start + 4] == "<!--" {
            return .Comment
        }
    }

    // Definition list: line starting with : or ::
    when DefList {
        if ch == ':' && start + 1 < len(input) && input[start + 1] == ' ' {
            return .DefList
        }
    }

    // JS block starts

    // Import statement
    if start + 6 <= len(input) && input[start:start + 6] == "import" {
        if start + 6 >= len(input) {
            return .Import
        }
        after := input[start + 6]
        if after == ' ' || after == '(' || after == '{' || after == '\'' || after == '"' {
            return .Import
        }
    }

    // Export statement
    if start + 6 <= len(input) && input[start:start + 6] == "export" {
        if start + 6 >= len(input) { return .Export }
        if input[start + 6] == ' ' { return .Export }
    }

    // JS module-level declarations (const, let, var, function, class, async)
    if input[start] == 'c' && start + 5 <= len(input) && input[start:start + 5] == "const" {
        if start + 5 == len(input) || input[start + 5] == ' ' { return .JS_Module }
    }
    if input[start] == 'l' && start + 3 <= len(input) && input[start:start + 3] == "let" {
        if start + 3 == len(input) || input[start + 3] == ' ' { return .JS_Module }
    }
    if input[start] == 'v' && start + 3 <= len(input) && input[start:start + 3] == "var" {
        if start + 3 == len(input) || input[start + 3] == ' ' { return .JS_Module }
    }
    if start + 8 <= len(input) && input[start:start + 8] == "function" {
        if start + 8 == len(input) || input[start + 8] == ' ' { return .JS_Module }
    }
    if start + 5 <= len(input) && input[start:start + 5] == "class" {
        if start + 5 == len(input) || input[start + 5] == ' ' { return .JS_Module }
    }
    if start + 5 <= len(input) && input[start:start + 5] == "async" {
        if start + 5 == len(input) || input[start + 5] == ' ' { return .JS_Module }
    }

    // JSX element at block level (< followed by identifier)
    if ch == '<' {
        when Autolink {
            // Check if this looks like a GFM autolink rather than a JSX element.
            // URI autolinks: <scheme://...> — scan for ://
            // Email autolinks: <user@domain> — scan for @
            is_autolink := false
            scan := start + 1
            for scan < len(input) && input[scan] != '\n' && input[scan] != ' ' && input[scan] != '\t' && input[scan] != '>' {
                if input[scan] == ':' && scan + 2 < len(input) && input[scan + 1] == '/' && input[scan + 2] == '/' {
                    is_autolink = true
                    break
                }
                scan += 1
            }
            if !is_autolink {
                scan = start + 1
                for scan < len(input) && input[scan] != '\n' && input[scan] != ' ' && input[scan] != '\t' && input[scan] != '>' {
                    if input[scan] == '@' && scan > start + 1 {
                        is_autolink = true
                        break
                    }
                    scan += 1
                }
            }
            if is_autolink {
                return .Paragraph
            }
        }
        return .JSX_Element
    }

    // Expression block ({...})
    if ch == '{' {
        return .JS_Expression
    }

    // GFM table: current line has `|` and next line is a separator
    when Tables {
        if has_pipe_in_line(input, start) {
            if !is_table_separator_line(input, start) {
                next_line := find_next_line(input, start)
                if next_line >= 0 && is_table_separator_line(input, next_line) {
                    return .Table
                }
            }
        }
    }

    // Default: paragraph
    return .Paragraph
}

// skip_fence advances past a code fence without emitting output.
// Returns the new position (past the closing fence).
skip_fence :: proc(input: string, pos: int) -> int {
    i := pos
    marker := input[i]
    fence_len := count_leading(input[i:], marker)
    i += fence_len

    // Skip language tag line
    for i < len(input) && input[i] != '\n' { i += 1 }
    if i < len(input) && input[i] == '\n' { i += 1 }

    // Find closing fence
    for i < len(input) {
        if input[i] == marker && count_leading(input[i:], marker) >= fence_len {
            rest := i + count_leading(input[i:], marker)
            is_closing := true
            for rest < len(input) && input[rest] != '\n' {
                if input[rest] != ' ' && input[rest] != '\t' {
                    is_closing = false
                    break
                }
                rest += 1
            }
            if is_closing {
                i += fence_len
                for i < len(input) && input[i] != '\n' { i += 1 }
                if i < len(input) && input[i] == '\n' { i += 1 }
                return i
            }
        }
        for i < len(input) && input[i] != '\n' { i += 1 }
        if i < len(input) { i += 1 }
    }
    return i
}

// ─── JS block boundary detection ────────────────────────────────────────────

// find_js_block_end scans forward from start to find where a JS/JSX block ends.
// It tracks brace/paren depth and string literals so it correctly handles
// multi-line import/export statements and JSX elements.
// Returns the position after the end of the JS block.
find_js_block_end :: proc(input: string, start: int) -> int {
    depth := 0       // {} depth
    parens := 0      // () depth
    jsx_depth := 0   // <> JSX tag depth
    in_string := false
    string_char: byte = 0
    newline_count := 0 // safety limit for unterminated blocks

    i := start
    for i < len(input) {
        ch := input[i]

        if in_string {
            if ch == '\\' {
                i += 2
                continue
            }
            if ch == string_char {
                in_string = false
            }
            i += 1
            continue
        }

        switch ch {
        case '\'':
            in_string = true
            string_char = '\''
        case '"':
            in_string = true
            string_char = '"'
        case '`':
            // Skip entire template literal in one scan, handling
            // ${} expressions and nested template literals.
            i += 1
            for i < len(input) {
                if input[i] == '`' {
                    i += 1
                    break
                }
                if input[i] == '\\' { i += 2; continue }
                if input[i] == '$' && i + 1 < len(input) && input[i + 1] == '{' {
                    i += 2
                    expr_depth := 1
                    for i < len(input) && expr_depth > 0 {
                        if input[i] == '{' { expr_depth += 1 }
                        if input[i] == '}' { expr_depth -= 1 }
                        if input[i] == '\\' { i += 1 }
                        if input[i] == '`' {
                            i += 1
                            for i < len(input) && input[i] != '`' {
                                if input[i] == '\\' { i += 1 }
                                i += 1
                            }
                        }
                        if expr_depth > 0 { i += 1 }
                    }
                }
                i += 1
            }
            continue
        case '{':
            depth += 1
        case '}':
            if depth > 0 {
                depth -= 1
            }
        case '(':
            parens += 1
        case ')':
            if parens > 0 {
                parens -= 1
            }
        case '<':
            // JSX tag tracking: only at depth 0 (not inside {} expressions)
            if depth == 0 && i + 1 < len(input) {
                if input[i + 1] == '/' && i + 2 < len(input) && is_jsx_identifier_start(input[i + 2]) {
                    if jsx_depth > 0 {
                        jsx_depth -= 1
                    }
                } else if is_jsx_identifier_start(input[i + 1]) {
                    // Check for self-closing: <Tag/> — scan for />
                    tag_start := i + 1
                    // Skip tag name
                    scan := tag_start
                    for scan < len(input) && is_jsx_identifier_continue(input[scan]) {
                        scan += 1
                    }
                    tag_name_end := scan
                    // Skip attributes (handling strings and braces)
                    for scan < len(input) && input[scan] != '>' {
                        if input[scan] == '{' {
                            // Skip attribute expression
                            expr_depth := 1
                            scan += 1
                            for scan < len(input) && expr_depth > 0 {
                                if input[scan] == '{' {
                                    expr_depth += 1
                                } else if input[scan] == '}' {
                                    expr_depth -= 1
                                } else if input[scan] == '\'' || input[scan] == '"' {
                                    quote := input[scan]
                                    scan += 1
                                    for scan < len(input) && input[scan] != quote {
                                        if input[scan] == '\\' {
                                            scan += 1
                                        }
                                        scan += 1
                                    }
                                }
                                if expr_depth > 0 {
                                    scan += 1
                                }
                            }
                        } else if input[scan] == '\'' || input[scan] == '"' {
                            quote := input[scan]
                            scan += 1
                            for scan < len(input) && input[scan] != quote {
                                if input[scan] == '\\' {
                                    scan += 1
                                }
                                scan += 1
                            }
                        }
                        scan += 1
                    }
                    // Check if self-closing: last char before > is /
                    is_self_closing := false
                    if scan > tag_start && scan < len(input) && input[scan - 1] == '/' {
                        is_self_closing = true
                    } else if tag_name_end > tag_start {
                        // Check for HTML void elements that don't require closing tags
                        tag_name := input[tag_start:tag_name_end]
                        if is_html_void_element(tag_name) {
                            is_self_closing = true
                        }
                    }
                    if !is_self_closing {
                        jsx_depth += 1
                    }
                }
            }
        case '\n':
            newline_count += 1
            // Safety: if we've seen too many newlines without closing depth,
            // assume unterminated expression and bail out.
            if newline_count > 100 && depth > 0 {
                return i
            }
            // At depth 0, check if the next line switches to markdown
            if depth == 0 && parens == 0 && jsx_depth == 0 {
                j := i + 1
                // Skip whitespace-only lines
                for j < len(input) {
                    cj := input[j]
                    if cj == ' ' || cj == '\t' || cj == '\n' {
                        j += 1
                    } else {
                        break
                    }
                }
                if j >= len(input) {
                    return i
                }
                // Check if next non-whitespace line starts markdown.
                // Continue JS block only for continuation markers: . , ) ] } = | & { [
                nc := input[j]
                if nc == '.' || nc == ',' || nc == ')' || nc == ']' || nc == '}' || nc == '=' || nc == '|' || nc == '&' || nc == '{' || nc == '[' {
                    // JS continuation — stay in JS block
                } else {
                    return j
                }
            }
        }
        i += 1
    }

    return i
}

// is_html_void_element returns true for HTML elements that cannot have children
// and thus don't require a closing tag. Per the HTML spec: area, base, br, col,
// embed, hr, img, input, link, meta, param, source, track, wbr.
is_html_void_element :: proc(name: string) -> bool {
    switch name {
    case "area", "base", "br", "col", "embed", "hr", "img", "input",
         "link", "meta", "param", "source", "track", "wbr":
        return true
    }
    return false
}

// ─── Table detection helpers ────────────────────────────────────────────────

// has_pipe_in_line returns true if the line at pos contains a pipe character.
has_pipe_in_line :: proc(input: string, pos: int) -> bool {
    i := pos
    for i < len(input) && input[i] != '\n' {
        if input[i] == '|' {
            return true
        }
        i += 1
    }
    return false
}

// find_next_line returns the start of the next line, or -1.
find_next_line :: proc(input: string, pos: int) -> int {
    i := pos
    for i < len(input) && input[i] != '\n' {
        i += 1
    }
    if i < len(input) {
        return i + 1
    }
    return -1
}

// is_deflist_next checks if the next immediate line starts a definition.
// Only returns true when the following line (non-blank) starts with : — a blank
// line between term and definition means they are separate blocks.
is_deflist_next :: proc(input: string, pos: int) -> bool {
    i := pos
    for i < len(input) && input[i] != '\n' { i += 1 }
    if i < len(input) && input[i] == '\n' { i += 1 }
    if i >= len(input) { return false }
    // Check the next line is not blank
    next_start := i
    j := next_start
    for j < len(input) && (input[j] == ' ' || input[j] == '\t') { j += 1 }
    if j >= len(input) || input[j] == '\n' { return false } // blank line
    if input[j] == ':' {
        k := j + 1
        if k < len(input) && (input[k] == ' ' || input[k] == '\t') {
            return true
        }
    }
    return false
}

// is_table_separator_line checks if the line at pos is a GFM table separator
// (contains `---` segments separated by `|` or just a dash-only line with pipes).
is_table_separator_line :: proc(input: string, pos: int) -> bool {
    i := pos
    has_dash := false
    for i < len(input) && input[i] != '\n' {
        ch := input[i]
        if ch == '-' || ch == ':' {
            if ch == '-' {
                has_dash = true
            }
            i += 1
        } else if ch == ' ' || ch == '\t' || ch == '|' {
            i += 1
        } else {
            return false
        }
    }
    return has_dash
}


