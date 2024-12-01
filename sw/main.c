#include <stdio.h>
#include <errno.h>
#include <string.h>
#include "uci.h"

int main(int argc, char** argv) {
    FILE* input = stdin;
    FILE* output = stdout;

    if (argc > 1) {
        input = fopen(argv[1], "r");
        if (!input) {
            fprintf(stderr, "failed to open input %s: %s\n", argv[1], strerror(errno));
            return 1;
        }
    }

    if (argc > 2) {
        output = fopen(argv[1], "w");
        if (!output) {
            fprintf(stderr, "failed to open output %s: %s\n", argv[1], strerror(errno));
            return 1;
        }
    }

    int status = uci_start(input, output);

    fclose(input);
    fclose(output);

    return status && 1;
}
