#include <stdio.h>
#include "uci.h"

int main(int argc, char** argv) {
    FILE* input = stdin;
    FILE* output = stdout;

    if (argc > 1) input = fopen(argv[1], "r");
    if (argc > 2) output = fopen(argv[2], "a+");

    return uci_start(input, output) && 1;
}
