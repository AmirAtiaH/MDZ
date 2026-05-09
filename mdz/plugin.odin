package mdz

PluginPhase :: enum u8 {
	BeforeBlock,
	AfterBlock,
}

PluginResult :: enum u8 {
	Keep,
	Remove,
	Handled,
}

Plugin :: struct {
	name:   string,
	phase:  PluginPhase,
	filter: []BlockType,
	hook:   proc(ctx: ^PluginContext) -> PluginResult,
}

PluginContext :: struct {
	input:      string,
	pos:        int,
	block_type: BlockType,
	output:     ^Writer,
	module:     ^Writer,
	written:    string,
}

PluginPipeline :: struct {
	plugins: [dynamic]Plugin,
}

plugin_init :: proc(pipeline: ^PluginPipeline) {
	pipeline.plugins = make([dynamic]Plugin)
}

plugin_destroy :: proc(pipeline: ^PluginPipeline) {
	delete(pipeline.plugins)
}

plugin_register :: proc(pipeline: ^PluginPipeline, p: Plugin) {
	append(&pipeline.plugins, p)
}

filter_matches :: proc(filter: []BlockType, bt: BlockType) -> bool {
	for f in filter {
		if f == bt { return true }
	}
	return false
}

run_before_plugins :: proc(pipeline: ^PluginPipeline, input: string, pos: ^int, w: ^Writer, mw: ^Writer, bt: BlockType) -> PluginResult {
	for p in pipeline.plugins {
		if p.phase != .BeforeBlock { continue }
		if len(p.filter) > 0 && !filter_matches(p.filter, bt) { continue }
		ctx := PluginContext{
			input      = input,
			pos        = pos^,
			block_type = bt,
			output     = w,
			module     = mw,
		}
		result := p.hook(&ctx)
		pos^ = ctx.pos
		if result != .Keep {
			return result
		}
	}
	return .Keep
}

run_after_plugins :: proc(pipeline: ^PluginPipeline, input: string, pos: int, w: ^Writer, mw: ^Writer, bt: BlockType, written: string) {
	for p in pipeline.plugins {
		if p.phase != .AfterBlock { continue }
		if len(p.filter) > 0 && !filter_matches(p.filter, bt) { continue }
		ctx := PluginContext{
			input      = input,
			pos        = pos,
			block_type = bt,
			output     = w,
			module     = mw,
			written    = written,
		}
		p.hook(&ctx)
	}
}
