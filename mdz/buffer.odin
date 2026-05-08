package mdz

// Writer: growable output buffer with pre-allocation.
// Wraps [dynamic]byte directly.
Writer :: struct {
    buf: [dynamic]byte,
}

writer_init :: proc(w: ^Writer, input_len: int) {
    capacity := input_len + input_len / 4 + 512
    w.buf = make([dynamic]byte, 0, capacity)
}

writer_write :: proc(w: ^Writer, s: string) {
    append(&w.buf, ..transmute([]byte)s)
}

writer_write_byte :: proc(w: ^Writer, b: byte) {
    append(&w.buf, b)
}

writer_get :: proc(w: ^Writer) -> string {
    return string(w.buf[:])
}

writer_destroy :: proc(w: ^Writer) {
    delete(w.buf)
}
