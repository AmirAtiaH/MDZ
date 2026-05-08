use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

extern "C" {
    fn mdz_compile(
        input: *const c_char,
        output: *mut *mut c_char,
        error_msg: *mut *mut c_char,
    ) -> i32;

    fn mdz_compile_file(
        path: *const c_char,
        output: *mut *mut c_char,
        error_msg: *mut *mut c_char,
    ) -> i32;

    fn mdz_free_string(s: *mut c_char);
}

pub fn compile(input: &str) -> Result<String, String> {
    let c_input = CString::new(input).map_err(|e| e.to_string())?;
    let mut output: *mut c_char = ptr::null_mut();
    let mut error_msg: *mut c_char = ptr::null_mut();

    let ret = unsafe { mdz_compile(c_input.as_ptr(), &mut output, &mut error_msg) };

    if ret != 0 {
        let err = if !error_msg.is_null() {
            unsafe { CStr::from_ptr(error_msg).to_string_lossy().to_string() }
        } else {
            "unknown error".to_string()
        };
        unsafe { mdz_free_string(error_msg) };
        return Err(err);
    }

    let result = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
    unsafe { mdz_free_string(output) };
    Ok(result)
}

pub fn compile_file(path: &str) -> Result<String, String> {
    let c_path = CString::new(path).map_err(|e| e.to_string())?;
    let mut output: *mut c_char = ptr::null_mut();
    let mut error_msg: *mut c_char = ptr::null_mut();

    let ret = unsafe { mdz_compile_file(c_path.as_ptr(), &mut output, &mut error_msg) };

    if ret != 0 {
        let err = if !error_msg.is_null() {
            unsafe { CStr::from_ptr(error_msg).to_string_lossy().to_string() }
        } else {
            "unknown error".to_string()
        };
        unsafe { mdz_free_string(error_msg) };
        return Err(err);
    }

    let result = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
    unsafe { mdz_free_string(output) };
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compile_heading() {
        let result = compile("# Hello").unwrap();
        assert!(result.contains("<h1>Hello</h1>"));
    }

    #[test]
    fn test_compile_bold() {
        let result = compile("**bold**").unwrap();
        assert!(result.contains("<strong>bold</strong>"));
    }

    #[test]
    fn test_compile_file() {
        let result = compile_file("../test.mdx").unwrap();
        assert!(result.contains("MDXContent"));
    }
}
