.PHONY: build build-fast test clean ffi c-example rust-example bench bench-mdx

ODIN ?= odin
NODE ?= node

build:
	$(ODIN) build .

build-fast:
	$(ODIN) build . -o:speed -microarch:native -no-bounds-check -disable-assert -lto:thin

test:
	$(ODIN) test .

ffi:
	$(ODIN) build ffi -build:shared -o:speed -no-bounds-check -disable-assert

c-example: ffi
	cd c && $(MAKE)

rust-example: ffi
	cd rust && cargo build --example compile

bench:
	./mdz --bench

bench-mdx:
	$(NODE) benchmark/mdx_bench.mjs

clean:
	rm -f mdz mdz.exe mdz.dll libmdz.so libmdz.dylib *.obj *.lib *.pdb
	cd ffi && rm -f *.obj *.lib *.pdb 2>/dev/null || true
	cd c && $(MAKE) clean 2>/dev/null || true
	cd rust && cargo clean 2>/dev/null || true
