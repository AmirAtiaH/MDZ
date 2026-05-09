package mdz_ffi

import "core:c"
import "core:mem"
import "core:strings"
import mdz "../mdz"

@(export)
mdz_compile :: proc(input: cstring, output: ^cstring, error_msg: ^cstring) -> c.int {
    result, err := mdz.compile(string(input))
    if err != nil {
        compile_err := err.(mdz.Compile_Error)
        error_msg^ = strings.clone_to_cstring(compile_err.message)
        return -1
    }
    output^ = strings.clone_to_cstring(result)
    delete(result)
    return 0
}

@(export)
mdz_compile_file :: proc(path: cstring, output: ^cstring, error_msg: ^cstring) -> c.int {
    result, err := mdz.compile_file(string(path))
    if err != nil {
        compile_err := err.(mdz.Compile_Error)
        error_msg^ = strings.clone_to_cstring(compile_err.message)
        return -1
    }
    output^ = strings.clone_to_cstring(result)
    delete(result)
    return 0
}

@(export)
mdz_free_string :: proc(s: cstring) {
    if s != nil {
        free(auto_cast s)
    }
}
