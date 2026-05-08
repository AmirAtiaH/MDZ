package mdz

// ─── Block-level markdown → JSX ──────────────────────────────────────────────
//
// Each process_* function reads one block from the input at the given position,
// emits the corresponding JSX to the writer, and updates pos to point past the
// consumed input.

// ─── Heading ────────────────────────────────────────────────────────────────

process_heading :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^
    // Count # characters
    level := 0
    i := start
    for i < len(input) && input[i] == '#' {
        level += 1
        i += 1
    }
    if level > 6 {
        level = 6
    }

    // Skip spaces after ###
    for i < len(input) && (input[i] == ' ' || input[i] == '\t') {
        i += 1
    }

    // Find end of line
    line_end := i
    for line_end < len(input) && input[line_end] != '\n' {
        line_end += 1
    }

    // Strip trailing # characters and spaces
    content_end := line_end
    for content_end > i && input[content_end - 1] == '#' {
        content_end -= 1
    }
    for content_end > i && (input[content_end - 1] == ' ' || input[content_end - 1] == '\t') {
        content_end -= 1
    }

    // Emit <hN>content</hN>
    level_byte := byte('0' + level)
    writer_write(w, "\n<h")
    writer_write_byte(w, level_byte)
    writer_write(w, ">")
    convert_inline(input[i:content_end], w)
    writer_write(w, "</h")
    writer_write_byte(w, level_byte)
    writer_write(w, ">\n")

    // Advance past newline
    if line_end < len(input) && input[line_end] == '\n' {
        pos^ = line_end + 1
    } else {
        pos^ = line_end
    }
}

// ─── Paragraph ──────────────────────────────────────────────────────────────

process_paragraph :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^

    // Read all lines that form this paragraph.
    // A paragraph ends at a blank line or when the next line starts a new block.
    end := start
    for end < len(input) {
        line_start := end
        // Skip to end of this line
        for end < len(input) && input[end] != '\n' {
            end += 1
        }
        if end < len(input) {
            end += 1 // skip \n
        }

        // If we've consumed the current line, check what the next line looks like
        next := end
        // Skip whitespace at start of next line
        for next < len(input) && (input[next] == ' ' || input[next] == '\t') {
            next += 1
        }
        if next >= len(input) {
            // End of input — paragraph ends
            break
        }

        ch := input[next]
        paragraph_ends := false

        switch ch {
        case '\n':
            // Blank line — paragraph ends
            paragraph_ends = true
        case '#', '>':
            // Heading or blockquote — paragraph ends
            paragraph_ends = true
        case '-', '*':
            if next + 1 < len(input) && input[next + 1] == ' ' {
                paragraph_ends = true
            } else if is_line_thematic_break(input, next) {
                paragraph_ends = true
            }
            // Otherwise continue paragraph (e.g. "*emphasis* at line start")
        case '`', '~':
            if count_leading(input[next:], ch) >= 3 {
                paragraph_ends = true
            }
            // Single backtick continues paragraph
        case:
            if is_digit(ch) && is_ordered_list_start(input, next) {
                paragraph_ends = true
            }
        }

        if paragraph_ends {
            break
        }
        // Otherwise continue looping to include this next line in the paragraph
    }

    // Trim trailing newlines from content
    content := input[start:end]
    for len(content) > 0 && content[len(content) - 1] == '\n' {
        content = content[:len(content) - 1]
    }

    if len(content) > 0 {
        writer_write(w, "\n<p>")
        line_start := 0
        for i in 0 ..< len(content) {
            if content[i] == '\n' {
                convert_inline(content[line_start:i], w)
                writer_write(w, "<br/>\n")
                line_start = i + 1
            }
        }
        convert_inline(content[line_start:], w)
        writer_write(w, "</p>\n")
    }

    pos^ = end
}

// ─── Blockquote ────────────────────────────────────────────────────────────

process_blockquote :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^

    // Collect all lines that are part of this blockquote
    // Each line starts with >
    i := start
    writer_write(w, "\n<blockquote>\n")

    for i < len(input) {
        // Skip whitespace
        j := i
        for j < len(input) && (input[j] == ' ' || input[j] == '\t') {
            j += 1
        }
        if j >= len(input) || input[j] != '>' {
            break
        }
        j += 1 // skip >

        // Skip optional space after >
        if j < len(input) && input[j] == ' ' {
            j += 1
        }

        // Find end of line
        line_end := j
        for line_end < len(input) && input[line_end] != '\n' {
            line_end += 1
        }

        // Emit content
        writer_write(w, "<p>")
        convert_inline(input[j:line_end], w)
        writer_write(w, "</p>\n")

        // Advance past newline
        if line_end < len(input) && input[line_end] == '\n' {
            i = line_end + 1
        } else {
            i = line_end
        }

        // Check if next line is also a blockquote
        if i >= len(input) {
            break
        }
        next := i
        for next < len(input) && (input[next] == ' ' || input[next] == '\t') {
            next += 1
        }
        if next >= len(input) || input[next] != '>' {
            break
        }
    }

    writer_write(w, "</blockquote>\n")
    pos^ = i
}

// ─── List (ordered and unordered) ─────────────────────────────────────────-

process_list :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^

    // Determine if ordered or unordered
    i := start
    for i < len(input) && (input[i] == ' ' || input[i] == '\t') {
        i += 1
    }
    ch := input[i]
    is_ordered := is_digit(ch)

    if is_ordered {
        writer_write(w, "\n<ol>\n")
    } else {
        writer_write(w, "\n<ul>\n")
    }

    for i < len(input) {
        // Skip whitespace
        j := i
        for j < len(input) && (input[j] == ' ' || input[j] == '\t') {
            j += 1
        }
        if j >= len(input) {
            break
        }

        // Check for ordered or unordered marker
        is_item_ordered := false
        if is_digit(input[j]) {
            k := j
            for k < len(input) && is_digit(input[k]) {
                k += 1
            }
            if k >= len(input) || (input[k] != '.' && input[k] != ')') {
                break
            }
            if k + 1 >= len(input) || input[k + 1] != ' ' {
                break
            }
            j = k + 2
            is_item_ordered = true
        } else if (input[j] == '-' || input[j] == '*') && j + 1 < len(input) && input[j + 1] == ' ' {
            j += 2
        } else {
            break
        }

        // If list type changed, close current and open new
        if is_item_ordered != is_ordered {
            if is_item_ordered {
                // was unordered -> ordered
                writer_write(w, "</ul>\n<ol>\n")
            } else {
                // was ordered -> unordered
                writer_write(w, "</ol>\n<ul>\n")
            }
            is_ordered = is_item_ordered
        }

        // Read the rest of the line
        line_end := j
        for line_end < len(input) && input[line_end] != '\n' {
            line_end += 1
        }

        // Emit list item
        writer_write(w, "<li>")
        convert_inline(input[j:line_end], w)
        writer_write(w, "</li>\n")

        // Advance past newline
        if line_end < len(input) && input[line_end] == '\n' {
            i = line_end + 1
        } else {
            i = line_end
        }

        // Check if next line is also a list item
        if i >= len(input) {
            break
        }
        // Skip whitespace-only lines (loose list items)
        next := i
        for next < len(input) && (input[next] == ' ' || input[next] == '\t' || input[next] == '\n') {
            next += 1
        }
        if next >= len(input) {
            break
        }
        nc := input[next]
        if is_digit(nc) {
            if !is_ordered_list_start(input, next) {
                break
            }
        } else if (nc == '-' || nc == '*') && next + 1 < len(input) && input[next + 1] == ' ' {
            // continue list
        } else {
            break
        }
    }

    // Note: when the list type tracks correctly, we close whatever we're in.
    // Since calling code dispatches on the *first* list marker of the block,
    // we emit the closing tag(s) for whatever list we're currently tracking.
    // We may need to close multiple lists if the type changes, but in our
    // model we handle this by detecting type changes and closing/reopening
    // within the loop. Here at the end, is_ordered reflects the most recent
    // list type, so a single close is correct.
    if is_ordered {
        writer_write(w, "</ol>\n")
    } else {
        writer_write(w, "</ul>\n")
    }

    pos^ = i
}

// ─── Code fence ────────────────────────────────────────────────────────────

process_fence :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^
    i := start

    // Determine fence marker and length
    marker := input[i]
    fence_len := count_leading(input[i:], marker)
    i += fence_len

    // Get language (rest of the opening fence line)
    lang_start := i
    for i < len(input) && input[i] != '\n' {
        i += 1
    }
    lang := trim_space(input[lang_start:i])

    // Skip newline
    if i < len(input) && input[i] == '\n' {
        i += 1
    }

    // Find closing fence (same marker, same or longer length)
    content_start := i
    found := false
    for i < len(input) {
        if input[i] == marker && count_leading(input[i:], marker) >= fence_len {
            // Check that the rest of this line is only whitespace
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
                found = true
                break
            }
        }
        // Skip to next line
        for i < len(input) && input[i] != '\n' {
            i += 1
        }
        if i < len(input) {
            i += 1
        }
    }

    content := input[content_start:i]
    // Remove trailing newline from content
    for len(content) > 0 && content[len(content) - 1] == '\n' {
        content = content[:len(content) - 1]
    }

    // Emit <pre><code>
    writer_write(w, "\n<pre><code")
    if lang != "" {
        writer_write(w, " class=\"language-")
        write_escaped(lang, w)
        writer_write(w, "\"")
    }
    writer_write(w, ">")
    write_escaped(content, w)
    writer_write(w, "</code></pre>\n")

    // Advance past closing fence
    if found {
        i += fence_len
        // Skip to end of line
        for i < len(input) && input[i] != '\n' {
            i += 1
        }
        if i < len(input) && input[i] == '\n' {
            i += 1
        }
    }

    pos^ = i
}

// ─── Thematic break ───────────────────────────────────────────────────────

process_thematic_break :: proc(input: string, pos: ^int, w: ^Writer) {
    writer_write(w, "\n<hr/>\n")
    pos^ = skip_line(input, pos^)
}

// ─── Table ─────────────────────────────────────────────────────────────────

process_table :: proc(input: string, pos: ^int, w: ^Writer) {
    i := pos^

    writer_write(w, "\n<table>\n")

    // Collect table rows: raw lines
    rows := make([dynamic]string)
    defer delete(rows)

    for i < len(input) {
        line_end := i
        for line_end < len(input) && input[line_end] != '\n' {
            line_end += 1
        }
        line := input[i:line_end]

        if is_table_separator_line(input, i) || has_pipe_in_line(input, i) {
            append(&rows, line)
        } else {
            break
        }

        if line_end < len(input) && input[line_end] == '\n' {
            i = line_end + 1
        } else {
            i = line_end
        }

        if i >= len(input) {
            break
        }
        // Peek next non-blank line
        next := i
        for next < len(input) && (input[next] == ' ' || input[next] == '\t' || input[next] == '\n') {
            next += 1
        }
        if next >= len(input) || (!has_pipe_in_line(input, next) && !is_table_separator_line(input, next)) {
            break
        }
    }

    // Find separator row index
    sep_idx := -1
    for k in 0 ..< len(rows) {
        if is_table_separator_line_from_str(rows[k]) {
            sep_idx = k
            break
        }
    }

    // Parse alignment from separator
    alignments: [dynamic]string
    defer delete(alignments)
    if sep_idx >= 0 {
        sep_cells := split_table_cells(rows[sep_idx])
        for sc in sep_cells {
            s := trim_space(sc)
            if len(s) >= 3 {
                left := s[0] == ':'
                right := s[len(s) - 1] == ':'
                if left && right {
                    append(&alignments, "center")
                } else if right {
                    append(&alignments, "right")
                } else if left {
                    append(&alignments, "left")
                } else {
                    append(&alignments, "")
                }
            } else {
                append(&alignments, "")
            }
        }
        delete(sep_cells)
    }

    // Header row: rows before separator
    if sep_idx > 0 {
        writer_write(w, "<thead>\n<tr>\n")
        cells := split_table_cells(rows[0])
        for ci in 0 ..< len(cells) {
            writer_write(w, "<th")
            if ci < len(alignments) && alignments[ci] != "" {
                writer_write(w, " style=\"text-align: ")
                writer_write(w, alignments[ci])
                writer_write(w, "\"")
            }
            writer_write(w, ">")
            convert_inline(trim_space(cells[ci]), w)
            writer_write(w, "</th>\n")
        }
        writer_write(w, "</tr>\n</thead>\n")
        delete(cells)
    }

    // Body rows: rows after separator
    has_body := false
    for ri := sep_idx + 1; ri < len(rows); ri += 1 {
        if !has_body {
            writer_write(w, "<tbody>\n")
            has_body = true
        }
        writer_write(w, "<tr>\n")
        cells := split_table_cells(rows[ri])
        for ci in 0 ..< len(cells) {
            writer_write(w, "<td")
            if ci < len(alignments) && alignments[ci] != "" {
                writer_write(w, " style=\"text-align: ")
                writer_write(w, alignments[ci])
                writer_write(w, "\"")
            }
            writer_write(w, ">")
            convert_inline(trim_space(cells[ci]), w)
            writer_write(w, "</td>\n")
        }
        writer_write(w, "</tr>\n")
        delete(cells)
    }

    if has_body {
        writer_write(w, "</tbody>\n")
    }
    writer_write(w, "</table>\n")

    pos^ = i
}

// split_table_cells splits a table row by pipe, trimming leading/trailing pipes.
split_table_cells :: proc(line: string) -> []string {
    s := line
    if len(s) > 0 && s[0] == '|' {
        s = s[1:]
    }
    if len(s) > 0 && s[len(s) - 1] == '|' {
        s = s[:len(s) - 1]
    }
    if len(s) == 0 {
        return {}
    }

    count := 1
    for i in 0 ..< len(s) {
        if s[i] == '|' {
            count += 1
        }
    }

    result := make([]string, count)
    cell_idx := 0
    cell_start := 0
    pos := 0
    for pos < len(s) {
        if s[pos] == '|' {
            result[cell_idx] = s[cell_start:pos]
            cell_idx += 1
            pos += 1
            for pos < len(s) && s[pos] == ' ' {
                pos += 1
            }
            cell_start = pos
        } else {
            pos += 1
        }
    }
    if cell_start <= len(s) {
        result[cell_idx] = s[cell_start:]
    }
    return result
}

// is_table_separator_line_from_str is like is_table_separator_line but takes a string.
is_table_separator_line_from_str :: proc(line: string) -> bool {
    has_dash := false
    for i in 0 ..< len(line) {
        ch := line[i]
        if ch == '-' || ch == ':' {
            if ch == '-' {
                has_dash = true
            }
        } else if ch != ' ' && ch != '\t' && ch != '|' {
            return false
        }
    }
    return has_dash
}

// ─── JS/JSX block ─────────────────────────────────────────────────────────

process_js_block :: proc(input: string, pos: ^int, w: ^Writer) {
    start := pos^
    end := find_js_block_end(input, start)
    if end > start {
        block := input[start:end]

        for len(block) > 0 && (block[len(block) - 1] == '\n' || block[len(block) - 1] == ' ' || block[len(block) - 1] == '\t') {
            block = block[:len(block) - 1]
        }

        if len(block) > 0 {
            writer_write(w, block)
            writer_write(w, "\n")
        }
    }
    pos^ = end
}

// ─── Frontmatter ──────────────────────────────────────────────────────────

process_frontmatter :: proc(input: string, pos: ^int) {
    start := pos^ + 3 // skip opening ---
    // Find closing ---
    i := start
    for i + 2 < len(input) {
        if input[i] == '\n' && input[i + 1] == '-' && input[i + 2] == '-' && input[i + 3] == '-' {
            // Check it's on its own line
            j := i + 4
            for j < len(input) && input[j] != '\n' {
                if input[j] != ' ' && input[j] != '\t' {
                    // Not a proper closing
                    break
                }
                j += 1
            }
            // It's a valid closing
            pos^ = i + 4
            // Skip trailing newline
            if pos^ < len(input) && input[pos^] == '\n' {
                pos^ += 1
            }
            return
        }
        i += 1
    }
    // No closing frontmatter found — skip to end
    pos^ = len(input)
}

// ─── Helpers ──────────────────────────────────────────────────────────────

// is_line_thematic_break checks if the line at pos is a thematic break
is_line_thematic_break :: proc(input: string, pos: int) -> bool {
    i := pos
    if i >= len(input) {
        return false
    }
    ch := input[i]
    if ch != '-' && ch != '*' && ch != '_' {
        return false
    }
    count := count_leading(input[i:], ch)
    if count < 3 {
        return false
    }
    // Check rest of line is only whitespace
    rest := i + count
    for rest < len(input) && input[rest] != '\n' {
        if input[rest] != ' ' && input[rest] != '\t' {
            return false
        }
        rest += 1
    }
    return true
}

// is_ordered_list_start checks if position pos starts an ordered list item
is_ordered_list_start :: proc(input: string, pos: int) -> bool {
    i := pos
    if i >= len(input) || !is_digit(input[i]) {
        return false
    }
    for i < len(input) && is_digit(input[i]) {
        i += 1
    }
    if i >= len(input) {
        return false
    }
    if input[i] != '.' && input[i] != ')' {
        return false
    }
    if i + 1 >= len(input) || input[i + 1] != ' ' {
        return false
    }
    return true
}

// split_lines splits a string into lines (without newline characters)
split_lines :: proc(s: string) -> []string {
    if len(s) == 0 {
        return {} // make([]string, 0)
    }
    // First count lines
    count := 1
    for i in 0 ..< len(s) {
        if s[i] == '\n' {
            count += 1
        }
    }
    result := make([]string, count)
    line_idx := 0
    start := 0
    for i in 0 ..< len(s) {
        if s[i] == '\n' {
            result[line_idx] = s[start:i]
            line_idx += 1
            start = i + 1
        }
    }
    // Last line
    if start <= len(s) {
        result[line_idx] = s[start:]
    }
    return result
}

// trim_space removes leading and trailing whitespace
trim_space :: proc(s: string) -> string {
    start := 0
    for start < len(s) && (s[start] == ' ' || s[start] == '\t') {
        start += 1
    }
    end := len(s)
    for end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\n' || s[end - 1] == '\r') {
        end -= 1
    }
    return s[start:end]
}
