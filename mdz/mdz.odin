package mdz

import "core:os"
import "core:fmt"
import "core:strings"

// compile transforms an MDX source string into a JSX module string.
// Pre-allocates output buffer with input * 2 to accommodate JSX expansion.
// The caller owns the returned string and should delete it.
compile :: proc(input: string) -> (string, Error) {
    module_w, body_w: Writer
    writer_init(&module_w, len(input) / 4)
    writer_init(&body_w, len(input) * 2)
    defer {
        writer_destroy(&module_w)
        writer_destroy(&body_w)
    }

    pos := 0
    for pos < len(input) {
        pos = skip_blank_lines(input, pos)
        if pos >= len(input) {
            break
        }

        bt := classify_block(input, pos)

        #partial switch bt {
        case .Frontmatter:
            process_frontmatter(input, &pos)

        case .Fence:
            process_fence(input, &pos, &body_w)

        case .Import, .Export:
            process_js_block(input, &pos, &module_w)

        case .JSX_Element, .JS_Expression:
            process_js_block(input, &pos, &body_w)

        case .Heading:
            process_heading(input, &pos, &body_w)

        case .Blockquote:
            process_blockquote(input, &pos, &body_w)

        case .List:
            process_list(input, &pos, &body_w)

        case .ThematicBreak:
            process_thematic_break(input, &pos, &body_w)

        case .Table:
            process_table(input, &pos, &body_w)

        case .Paragraph:
            process_paragraph(input, &pos, &body_w)

        case .BlankLine:
            pos += 1

        case .Unknown:
            return "", Compile_Error{offset = pos, message = "unrecognized block"}

        case:
            return "", Compile_Error{offset = pos, message = "unhandled block type"}
        }
    }

    // Assemble final output: module code + wrapped body.
    // strings.concatenate does one allocation + one copy pass (no extra clone).
    output := strings.concatenate([]string{
        writer_get(&module_w),
        "\nfunction MDXContent(props = {}) {\n  return <>\n",
        writer_get(&body_w),
        "\n  </>\n}\n\nexport default MDXContent\n",
    })
    return output, nil
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
