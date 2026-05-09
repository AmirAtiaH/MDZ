package mdz

// ─── Syntax highlighting for code fences ───────────────────────────────────
//
// Line-oriented tokenizer that emits <span class="hl-xxx"> wrappers for
// keywords, strings, comments, and numbers.  Supported language groups:
// js (JS/TS/JSX/TSX), css, html, py (Python), rs (Rust), go, sh (Bash),
// json, yaml.  Unknown languages pass through as plain escaped text.

TokenType :: enum u8 {
    Normal,
    Keyword,
    String,
    Comment,
    Number,
}

lang_group :: proc(lang: string) -> string {
    switch lang {
    case "js", "javascript", "jsx", "mjs", "cjs", "ts", "typescript", "tsx":
        return "js"
    case "css", "scss", "less", "sass":
        return "css"
    case "html", "xml", "svg":
        return "html"
    case "py", "python":
        return "py"
    case "rs", "rust":
        return "rs"
    case "go", "golang":
        return "go"
    case "sh", "bash", "zsh", "shell":
        return "sh"
    case "json":
        return "json"
    case "yaml", "yml":
        return "yaml"
    }
    return ""
}

highlight_write :: proc(code: string, lang: string, w: ^Writer) {
    group := lang_group(lang)
    if group == "" {
        write_escaped(code, w)
        return
    }

    i := 0
    for i < len(code) {
        start := i
        tt := next_token_type(code, &i, group)
        if tt == .Normal {
            write_escaped(code[start:i], w)
        } else {
            name := token_type_name(tt)
            writer_write(w, "<span class=\"hl-")
            writer_write(w, name)
            writer_write(w, "\">")
            write_escaped(code[start:i], w)
            writer_write(w, "</span>")
        }
    }
}

token_type_name :: proc(tt: TokenType) -> string {
    switch tt {
    case .Normal:  return ""
    case .Keyword: return "kw"
    case .String:  return "str"
    case .Comment: return "cm"
    case .Number:  return "num"
    }
    return ""
}

next_token_type :: proc(code: string, i: ^int, group: string) -> TokenType {
    pos := i^
    if pos >= len(code) { return .Normal }
    ch := code[pos]

    // Whitespace — one char, normal
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
        i^ += 1
        return .Normal
    }

    // Line comments
    if (group == "js" || group == "rs" || group == "go" || group == "css") &&
       ch == '/' && pos + 1 < len(code) && code[pos + 1] == '/' {
        for i^ < len(code) && code[i^] != '\n' { i^ += 1 }
        return .Comment
    }
    if (group == "py" || group == "sh" || group == "yaml") && ch == '#' {
        for i^ < len(code) && code[i^] != '\n' { i^ += 1 }
        return .Comment
    }

    // Block comments /* */ — js, rs, go, css
    if (group == "js" || group == "rs" || group == "go" || group == "css") &&
       ch == '/' && pos + 1 < len(code) && code[pos + 1] == '*' {
        i^ += 2
        for i^ + 1 < len(code) {
            if code[i^] == '*' && code[i^ + 1] == '/' { i^ += 2; return .Comment }
            i^ += 1
        }
        return .Comment
    }

    // Strings " ' `
    if ch == '"' || ch == '\'' || (group == "js" && ch == '`') {
        quote := ch
        i^ += 1
        for i^ < len(code) {
            if code[i^] == '\\' { i^ += 2; continue }
            if code[i^] == quote { i^ += 1; break }
            // Template interpolation ${} in JS
            if group == "js" && quote == '`' && code[i^] == '$' && i^ + 1 < len(code) && code[i^ + 1] == '{' {
                i^ += 2
                depth := 1
                for i^ < len(code) && depth > 0 {
                    if code[i^] == '{' { depth += 1 }
                    if code[i^] == '}' { depth -= 1 }
                    if code[i^] == '\\' { i^ += 1 }
                    if depth > 0 { i^ += 1 }
                }
                continue
            }
            i^ += 1
        }
        return .String
    }

    // HTML tags
    if group == "html" && ch == '<' {
        for i^ < len(code) && code[i^] != '>' { i^ += 1 }
        if i^ < len(code) { i^ += 1 }
        return .Keyword
    }

    // Numbers
    if is_digit(ch) || (ch == '-' && pos + 1 < len(code) && is_digit(code[pos + 1])) {
        if ch == '-' { i^ += 1 }
        // Check for 0x, 0b, 0o prefix
        if i^ < len(code) && code[i^] == '0' && i^ + 1 < len(code) {
            nxt := code[i^ + 1]
            if nxt == 'x' || nxt == 'X' || nxt == 'b' || nxt == 'B' || nxt == 'o' || nxt == 'O' {
                i^ += 2
                for i^ < len(code) && is_hex_digit(code[i^]) { i^ += 1 }
                return .Number
            }
        }
        // Decimal / float
        for i^ < len(code) && (is_digit(code[i^]) || code[i^] == '.' || code[i^] == 'e' || code[i^] == 'E' || code[i^] == 'f' || code[i^] == 'F') {
            i^ += 1
        }
        return .Number
    }

    // Identifiers — check for keywords
    if is_ident_start(ch) {
        start := pos
        i^ += 1
        for i^ < len(code) && is_ident_continue(code[i^]) { i^ += 1 }
        word := code[start:i^]
        if is_keyword(word, group) { return .Keyword }
        return .Normal
    }

    // Default: single char, normal
    i^ += 1
    return .Normal
}

is_ident_start :: proc(ch: byte) -> bool {
    return is_letter(ch) || ch == '_' || ch == '$'
}

is_ident_continue :: proc(ch: byte) -> bool {
    return is_letter(ch) || is_digit(ch) || ch == '_' || ch == '$'
}

is_keyword :: proc(word: string, group: string) -> bool {
    switch group {
    case "js":
        switch word {
        case "abstract", "arguments", "as", "async", "await", "break", "case",
             "catch", "class", "const", "continue", "debugger", "default",
             "delete", "do", "else", "enum", "export", "extends", "false",
             "finally", "for", "from", "function", "get", "if", "implements",
             "import", "in", "instanceof", "interface", "let", "module", "new",
             "null", "of", "package", "private", "protected", "public", "return",
             "set", "static", "super", "switch", "target", "this", "throw",
             "true", "try", "typeof", "undefined", "var", "void", "while",
             "with", "yield":
            return true
        }
    case "py":
        switch word {
        case "False", "None", "True", "and", "as", "assert", "async", "await",
             "break", "class", "continue", "def", "del", "elif", "else",
             "except", "finally", "for", "from", "global", "if", "import",
             "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
             "return", "try", "while", "with", "yield":
            return true
        }
    case "rs":
        switch word {
        case "as", "async", "await", "break", "const", "continue", "crate",
             "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
             "impl", "in", "let", "loop", "match", "mod", "move", "mut",
             "pub", "ref", "return", "self", "static", "struct", "super",
             "trait", "true", "type", "union", "unsafe", "use", "where",
             "while":
            return true
        }
    case "go":
        switch word {
        case "break", "case", "chan", "const", "continue", "default", "defer",
             "else", "fallthrough", "for", "func", "go", "goto", "if",
             "import", "interface", "map", "package", "range", "return",
             "select", "struct", "switch", "type", "var":
            return true
        }
    case "sh":
        switch word {
        case "case", "cd", "do", "done", "echo", "elif", "else", "esac",
             "exit", "export", "fi", "for", "function", "if", "local",
             "return", "source", "then", "true", "false", "while":
            return true
        }
    case "json", "yaml":
        switch word {
        case "true", "false", "null", "yes", "no":
            return true
        }
    }
    return false
}
