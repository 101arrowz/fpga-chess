#include <stdio.h>
#include "uci.h"

int main(int argc, char** argv) {
    FILE* input = stdin;
    FILE* output = stdout;

    if (argc > 1) input = fopen(argv[1], "r");
    if (argc > 2) output = fopen(argv[2], "a+");

    int status = uci_start(input, output);

    fclose(input);
    fclose(output);

    return status && 1;
}
