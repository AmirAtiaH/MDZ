#include <stdio.h>
#include <stdlib.h>
#include "mdz.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: mdz_c <file.mdx>\n");
        return 1;
    }

    char* output = NULL;
    char* error = NULL;

    int ret = mdz_compile_file(argv[1], &output, &error);
    if (ret != 0) {
        fprintf(stderr, "error: %s\n", error);
        mdz_free_string(error);
        return 1;
    }

    printf("%s", output);
    mdz_free_string(output);
    return 0;
}
