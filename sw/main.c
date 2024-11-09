#include <stdio.h>
#include "uci.h"

int main() {
    return uci_start(stdin, stdout) && 1;
}
