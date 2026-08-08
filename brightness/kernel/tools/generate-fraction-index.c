/* SPDX-License-Identifier: GPL-2.0-only */
/* Generate the panel-independent lookup used by the kernel implementation. */
#include <stdio.h>

void __computeFractionPerBrightnessGroup(int slot, int high_brightness_mode,
                                         double output[10]);
void __getIndexOfFractionPerBrightnessGroup(int slot,
                                            double fractions[10],
                                            int high_brightness_mode,
                                            int output[10]);

int main(void)
{
    int maximum = 0;

    puts("static const u16 samsung_amoled_fraction_index[0x42][10] = {");
    for (int slot = 0; slot < 0x42; slot++) {
        double fractions[10];
        int indexes[10];

        __computeFractionPerBrightnessGroup(slot, 1, fractions);
        __getIndexOfFractionPerBrightnessGroup(slot, fractions, 1, indexes);
        printf("\t{");
        for (int group = 0; group < 10; group++) {
            if (indexes[group] > maximum)
                maximum = indexes[group];
            printf("%s%u", group ? ", " : "", indexes[group]);
        }
        puts("},");
    }
    puts("};");
    fprintf(stderr, "maximum index: %d\n", maximum);
    return maximum > 255;
}
