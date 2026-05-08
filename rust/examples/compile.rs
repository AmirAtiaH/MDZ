use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: mdz_rs <file.mdx>");
        std::process::exit(1);
    }

    match mdz_sys::compile_file(&args[1]) {
        Ok(output) => print!("{}", output),
        Err(e) => {
            eprintln!("error: {}", e);
            std::process::exit(1);
        }
    }
}
