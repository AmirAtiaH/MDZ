package mdz

// BlockType classifies the kind of MDX block at the current scan position.
// No AST is built - we classify, process, and emit in one pass.
BlockType :: enum u8 {
    Unknown,
    Import,
    Export,
    JS_Module,   // const, let, var, function, class declarations
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
    Comment,
    DefList,
    BlankLine,
}

// NodeAction controls what the compile loop does with a classified block.
// This enables transformer-style processing without restructuring the loop.
NodeAction :: enum u8 {
    Keep,             // Process normally
    KeepSkipChildren, // Write the block but don't recurse
    Remove,           // Skip the block entirely
}

// TransformConfig vends per-block actions for the compile loop.
// A nil entry means Keep (default behavior).
// This is the "plugin system as optional external execution layer".
TransformConfig :: struct {
    heading:    proc(input: string, pos: int) -> NodeAction,
    paragraph:  proc(input: string, pos: int) -> NodeAction,
    fence:      proc(input: string, pos: int) -> NodeAction,
    blockquote: proc(input: string, pos: int) -> NodeAction,
    list:       proc(input: string, pos: int) -> NodeAction,
    table:      proc(input: string, pos: int) -> NodeAction,
    expression: proc(input: string, pos: int) -> NodeAction,
    jsx:        proc(input: string, pos: int) -> NodeAction,
    comment:    proc(input: string, pos: int) -> NodeAction,
    deflist:    proc(input: string, pos: int) -> NodeAction,
}

// Compile_Error reports a compilation problem with position info
Compile_Error :: struct {
    offset:  int,
    message: string,
}

Error :: Maybe(Compile_Error)
