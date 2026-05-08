package main

import "core:fmt"
import "core:os"
import mdz "mdz"

main :: proc() {
    args := os.args

    if len(args) >= 2 && args[1] == "--bench" {
        run_benchmarks()
        return
    }

    if len(args) < 2 || args[1] == "-h" || args[1] == "--help" {
        fmt.eprintln("usage: mdz [options] <file.mdx>")
        fmt.eprintln()
        fmt.eprintln("Options:")
        fmt.eprintln("  -o <file>    Write output to file instead of stdout")
        fmt.eprintln("  --bench      Run benchmarks")
		fmt.eprintln("  -h, --help   Show this help")
        os.exit(1)
    }

    input_path := args[1]
    output_path: string

    if len(args) >= 4 && args[1] == "-o" {
        input_path = args[3]
        output_path = args[2]
    }

    result, err := mdz.compile_file(input_path)
    if err != nil {
        fmt.eprintf("error: %s\n", err.(mdz.Compile_Error).message)
        os.exit(1)
    }
    defer delete(result)

    if output_path != "" {
        write_err := os.write_entire_file(output_path, transmute([]byte)result)
        if write_err != nil {
            fmt.eprintf("error: failed to write '%s': %v\n", output_path, write_err)
            os.exit(1)
        }
    } else {
        fmt.print(result)
    }
}
