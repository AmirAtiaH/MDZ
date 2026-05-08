fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    match target_os.as_str() {
        "windows" => {
            println!("cargo:rustc-link-lib=mdz");
            println!("cargo:rustc-link-search=..");
        }
        "linux" => {
            println!("cargo:rustc-link-lib=dylib=mdz");
            println!("cargo:rustc-link-search=..");
            println!("cargo:rustc-link-lib=dl");
        }
        "macos" => {
            println!("cargo:rustc-link-lib=dylib=mdz");
            println!("cargo:rustc-link-search=..");
        }
        other => panic!("unsupported target OS: {}", other),
    }
}
