.PHONY: all clean

ODIN_OUT := ..

ifeq ($(OS),Windows_NT)
  CC ?= cl
  TARGET := mdz_c.exe
  CFLAGS := /I.
  LDFLAGS := /link $(ODIN_OUT)/mdz.lib
  all:
	$(CC) example.c $(CFLAGS) $(LDFLAGS) /OUT:$(TARGET)
else
  UNAME := $(shell uname -s)
  ifeq ($(UNAME),Linux)
    CC ?= gcc
    TARGET := mdz_c
    LIBS := -ldl
  endif
  ifeq ($(UNAME),Darwin)
    CC ?= clang
    TARGET := mdz_c
    LIBS :=
  endif
  LDFLAGS := -L$(ODIN_OUT) -lmdz $(LIBS)
  all:
	$(CC) example.c -I. -o $(TARGET) $(LDFLAGS)
endif

clean:
	rm -f mdz_c mdz_c.exe *.o *.obj
