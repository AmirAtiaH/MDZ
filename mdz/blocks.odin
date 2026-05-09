package mdz

import "core:strings"

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
    i := pos^

    // Collect all blockquote content (strip > prefixes)
    content_buf: Writer
    writer_init(&content_buf, len(input) / 4)
    defer writer_destroy(&content_buf)
    last_blank := true

    for i < len(input) {
        j := i
        for j < len(input) && (input[j] == ' ' || input[j] == '\t') {
            j += 1
        }
        if j >= len(input) || input[j] != '>' {
            break
        }
        j += 1 // skip >

        // Skip optional space after >
        if j < len(input) && (input[j] == ' ') {
            j += 1
        }

        // Find end of line
        line_end := j
        for line_end < len(input) && input[line_end] != '\n' {
            line_end += 1
        }

        // Handle nested blockquote (> >)
        content_start := j
        if content_start < len(input) && input[content_start] == '>' {
            // Preserve nested marker for recursive handling
            writer_write(&content_buf, "> ")
            content_start += 1
            if content_start < line_end && input[content_start] == ' ' {
                content_start += 1
            }
        }

        writer_write(&content_buf, input[content_start:line_end])
        writer_write(&content_buf, "\n")
        last_blank = false

        if line_end < len(input) && input[line_end] == '\n' {
            i = line_end + 1
        } else {
            i = line_end
        }

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

    // Now process the collected content as markdown blocks
    block_content := writer_get(&content_buf)
    writer_write(w, "\n<blockquote>\n")

    bpos := 0
    for bpos < len(block_content) {
        bpos = skip_blank_lines(block_content, bpos)
        if bpos >= len(block_content) {
            break
        }

        bt := classify_block(block_content, bpos)

        #partial switch bt {
        case .Fence:
            process_fence(block_content, &bpos, w)
        case .Heading:
            process_heading(block_content, &bpos, w)
        case .Blockquote:
            process_blockquote(block_content, &bpos, w)
        case .List:
            process_list(block_content, &bpos, w)
        case .ThematicBreak:
            process_thematic_break(block_content, &bpos, w)
        case .Paragraph:
            process_paragraph(block_content, &bpos, w)
        case .BlankLine:
            bpos += 1
        case:
            process_paragraph(block_content, &bpos, w)
        }
    }

    writer_write(w, "</blockquote>\n")
    pos^ = i
}

// ─── List (ordered and unordered) ─────────────────────────────────────────-

ListStackEntry :: struct {
    is_ordered: bool,
    indent:     int,
}

process_list :: proc(input: string, pos: ^int, w: ^Writer) {
    i := pos^

    stack: [dynamic]ListStackEntry
    defer delete(stack)

    indent_to_spaces :: proc(s: string, start: int) -> int {
        n := 0
        for idx := start; idx < len(s); idx += 1 {
            if s[idx] == ' ' {
                n += 1
            } else if s[idx] == '\t' {
                n += 4
            } else {
                return n
            }
        }
        return n
    }

    parse_marker :: proc(s: string, pos: int) -> (content_start: int, is_ordered: bool, ok: bool) {
        if pos >= len(s) {
            return 0, false, false
        }
        ch := s[pos]
        if is_digit(ch) {
            k := pos
            for k < len(s) && is_digit(s[k]) {
                k += 1
            }
            if k < len(s) && (s[k] == '.' || s[k] == ')') && k + 1 < len(s) && s[k + 1] == ' ' {
                return k + 2, true, true
            }
            return 0, false, false
        }
        if (ch == '-' || ch == '*') && pos + 1 < len(s) && s[pos + 1] == ' ' {
            return pos + 2, false, true
        }
        return 0, false, false
    }

    // First pass: collect all list items with their indent and content.
    // Continuation lines are absorbed into the item content.
    // Blank lines between items trigger loose list rendering.
    Item :: struct {
        indent:       int,
        is_ordered:   bool,
        content:      string,
        task_checked: int,  // -1 = not a task item, 0 = unchecked [ ], 1 = checked [x]
    }
    items := make([dynamic]Item)
    defer delete(items)
    is_loose := false

    for i < len(input) {
        indent := indent_to_spaces(input, i)
        j := i + indent

        content_start, is_ord, ok := parse_marker(input, j)
        if !ok {
            break
        }

        // Read first line of content after the marker
        line_end := content_start
        for line_end < len(input) && input[line_end] != '\n' {
            line_end += 1
        }

        // Check for GFM task list: [ ] or [x] after the marker
        task_checked := -1
        when TaskList {
            if content_start + 3 < len(input) && input[content_start] == '[' && input[content_start + 2] == ']' && input[content_start + 3] == ' ' {
                if input[content_start + 1] == ' ' {
                    task_checked = 0
                } else if input[content_start + 1] == 'x' || input[content_start + 1] == 'X' {
                    task_checked = 1
                }
                if task_checked >= 0 {
                    content_start += 4
                    line_end = content_start
                    for line_end < len(input) && input[line_end] != '\n' {
                        line_end += 1
                    }
                }
            }
        }

        // Build item content (first line, plus continuation lines)
        content_buf := strings.builder_make_len_cap(0, (line_end - content_start) + 64, context.temp_allocator)
        strings.write_string(&content_buf, input[content_start:line_end])

        // The content indent is the column (relative to line start) where item content begins
        content_indent := content_start - i

        // Advance past the first line's newline
        next := line_end
        if next < len(input) && input[next] == '\n' {
            next += 1
        }

        // Look ahead: absorb continuation lines, detect blank lines between items
        for next < len(input) {
            line_start2 := next
            line_end2 := next
            for line_end2 < len(input) && input[line_end2] != '\n' {
                line_end2 += 1
            }
            whole_line := input[line_start2:line_end2]

            // Blank line? (also handles \r\n Windows line endings)
            trimmed := whole_line
            for len(trimmed) > 0 && (trimmed[0] == ' ' || trimmed[0] == '\t' || trimmed[0] == '\r') {
                trimmed = trimmed[1:]
            }
            if len(trimmed) == 0 {
                is_loose = true
                next = line_end2
                if next < len(input) && input[next] == '\n' {
                    next += 1
                }
                continue
            }

            // Non-blank line — check if it's a new list marker
            next_indent := indent_to_spaces(input, line_start2)
            marker_pos := line_start2 + next_indent
            _, _, is_marker := parse_marker(input, marker_pos)
            if is_marker {
                break
            }

            // Continuation line? Must be indented at least as much as the content column
            if next_indent >= content_indent {
                strings.write_byte(&content_buf, ' ')
                strings.write_string(&content_buf, input[line_start2 + content_indent:line_end2])
                next = line_end2
                if next < len(input) && input[next] == '\n' {
                    next += 1
                }
                continue
            }

            // Not a marker, not a continuation — list is done
            break
        }

        append(&items, Item{
            indent       = indent,
            is_ordered   = is_ord,
            content      = strings.to_string(content_buf),
            task_checked = task_checked,
        })

        // Advance to next position (either next item's marker or end-of-list content)
        i = next
    }

    pos^ = i

    if len(items) == 0 {
        return
    }

    // Second pass: emit HTML using indent stack
    close_li := false

    close_list :: proc(w: ^Writer, ordered: bool) {
        if ordered {
            writer_write(w, "</ol>\n")
        } else {
            writer_write(w, "</ul>\n")
        }
    }

    open_list :: proc(w: ^Writer, ordered: bool) {
        if ordered {
            writer_write(w, "\n<ol>\n")
        } else {
            writer_write(w, "\n<ul>\n")
        }
    }

    for idx in 0 ..< len(items) {
        item := items[idx]
        indent := item.indent
        is_ord := item.is_ordered

        // Pop stack while current indent < top indent (going up; = means same level sibling)
        nested_closed := false
        for len(stack) > 0 && indent < stack[len(stack) - 1].indent {
            if close_li {
                writer_write(w, "</li>\n")
                close_li = false
            }
            close_list(w, stack[len(stack) - 1].is_ordered)
            pop(&stack)
            nested_closed = true
        }
        // If we came back up from a nested list, close the parent <li>
        // that was left open to contain the nested content.
        if nested_closed {
            close_li = true
        }

        // Check for sibling at same indent but different type (ordered → unordered)
        if len(stack) > 0 && indent == stack[len(stack) - 1].indent && is_ord != stack[len(stack) - 1].is_ordered {
            if close_li {
                writer_write(w, "</li>\n")
                close_li = false
            }
            close_list(w, stack[len(stack) - 1].is_ordered)
            pop(&stack)
        }

        // Open new list if needed
        if len(stack) == 0 || indent > stack[len(stack) - 1].indent {
            open_list(w, is_ord)
            append(&stack, ListStackEntry{is_ordered = is_ord, indent = indent})
        }

        // Close previous sibling <li>
        if close_li {
            writer_write(w, "</li>\n")
            close_li = false
        }

        // Emit <li>
        if item.task_checked >= 0 {
            writer_write(w, "<li class=\"task-item\">\n<input type=\"checkbox\" disabled")
            if item.task_checked == 1 {
                writer_write(w, " checked")
            }
            writer_write(w, "/> ")
        } else {
            writer_write(w, "<li>")
        }

        // Loose list: wrap content in <p> tags
        if is_loose && len(item.content) > 0 {
            writer_write(w, "\n<p>")
            convert_inline(item.content, w)
            writer_write(w, "</p>\n")
        } else {
            convert_inline(item.content, w)
        }

        // Check if next item is nested (deeper indent) — if so, don't close </li>
        if idx + 1 < len(items) && items[idx + 1].indent > indent {
            // Leave <li> open — the nested list goes inside it
            close_li = false
        } else {
            close_li = true
        }
    }

    // Close remaining
    if close_li {
        writer_write(w, "</li>\n")
    }
    for len(stack) > 0 {
        close_list(w, stack[len(stack) - 1].is_ordered)
        pop(&stack)
    }
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
    when Highlight {
        if lang != "" {
            writer_write(w, " class=\"language-")
            write_escaped(lang, w)
            writer_write(w, "\"")
        }
    }
    writer_write(w, ">")
    when Highlight {
        if lang != "" {
            highlight_write(content, lang, w)
        } else {
            write_escaped(content, w)
        }
    } else {
        write_escaped(content, w)
    }
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
        if s[i] == '|' && (i == 0 || s[i - 1] != '\\') {
            count += 1
        }
    }

    result := make([]string, count)
    cell_idx := 0
    cell_start := 0
    pos := 0
    for pos < len(s) {
        if s[pos] == '|' && (pos == 0 || s[pos - 1] != '\\') {
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

// ─── Definition list (term : definition) ────────────────────────────────

process_definition_list :: proc(input: string, pos: ^int, w: ^Writer) {
    i := pos^

    // Read term (current line)
    term_start := i
    term_end := i
    for term_end < len(input) && input[term_end] != '\n' { term_end += 1 }
    term := input[term_start:term_end]
    if term_end < len(input) && input[term_end] == '\n' {
        i = term_end + 1
    } else {
        i = term_end
    }

    // Skip blank lines
    for i < len(input) {
        ch := input[i]
        if ch == ' ' || ch == '\t' || ch == '\n' { i += 1 } else { break }
    }

    // Collect definitions
    defs := make([dynamic]string)
    defer delete(defs)

    for i < len(input) {
        // Skip leading whitespace
        j := i
        for j < len(input) && (input[j] == ' ' || input[j] == '\t') { j += 1 }
        if j >= len(input) || input[j] != ':' { break }
        k := j + 1
        for k < len(input) && (input[k] == ' ' || input[k] == '\t') { k += 1 }
        // Read definition content
        line_end := k
        for line_end < len(input) && input[line_end] != '\n' { line_end += 1 }
        append(&defs, input[k:line_end])
        if line_end < len(input) && input[line_end] == '\n' {
            i = line_end + 1
        } else {
            i = line_end
        }
        // Check next non-blank line
        next := i
        for next < len(input) && (input[next] == ' ' || input[next] == '\t' || input[next] == '\n') { next += 1 }
        if next >= len(input) || input[next] != ':' { break }
    }

    if len(defs) > 0 {
        writer_write(w, "\n<dl>\n<dt>")
        convert_inline(trim_space(term), w)
        writer_write(w, "</dt>\n")
        for def in defs {
            writer_write(w, "<dd>")
            convert_inline(trim_space(def), w)
            writer_write(w, "</dd>\n")
        }
        writer_write(w, "</dl>\n")
    }

    pos^ = i
}

// ─── Comment <!-- --> and {/* */} ────────────────────────────────────────

process_comment :: proc(input: string, pos: ^int) {
    i := pos^

    // HTML comment: <!-- ... -->
    if i + 3 < len(input) && input[i:i + 4] == "<!--" {
        i += 4
        for i + 2 < len(input) {
            if input[i:i + 3] == "-->" {
                i += 3
                if i < len(input) && input[i] == '\n' { i += 1 }
                pos^ = i
                return
            }
            i += 1
        }
        pos^ = len(input)
        return
    }

    // JSX comment: {/* ... */}
    if i + 2 < len(input) && input[i:i + 3] == "{/*" {
        i += 3
        for i + 1 < len(input) {
            if input[i] == '*' && input[i + 1] == '/' {
                i += 2
                if i < len(input) && input[i] == '}' { i += 1 }
                if i < len(input) && input[i] == '\n' { i += 1 }
                pos^ = i
                return
            }
            i += 1
        }
        pos^ = len(input)
        return
    }

    pos^ = skip_line(input, pos^)
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
