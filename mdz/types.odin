package mdz

// BlockType classifies the kind of MDX block at the current scan position.
// No AST is built - we classify, process, and emit in one pass.
BlockType :: enum u8 {
    Unknown,
    Import,
    Export,
    JSX_Element,
    JS_Expression,
    Frontmatter,
    Fence,
    Heading,
    Paragraph,
    Blockquote,
    List,
    ListItem,
    Table,
    ThematicBreak,
    BlankLine,
}

// Compile_Error reports a compilation problem with position info
Compile_Error :: struct {
    offset:  int,
    message: string,
}

Error :: Maybe(Compile_Error)
