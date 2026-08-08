/* SPDX-License-Identifier: GPL-2.0-only */
/* Compare the kernel-friendly fixed-point calibration with the reference. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../src/brightness.h"
#include "../../src/dpAux.h"
#include "../../src/tables.h"

typedef uint16_t u16;
#include "fraction-index.h"

#define SCALE 1000000000000LL
#define V72 (72LL * SCALE / 10)
#define V15 (15LL * SCALE / 10)

void __readBrightnessRegisters(aux_t aux, int output[10][3]);

static void fixed_channel_adjustment(int raw[10][3],
                                     unsigned char output[0x42][33])
{
    int64_t normalized[10][3] = {{0}};
    int64_t thresholds[0x100][3] = {{0}};

    for (int channel = 0; channel < 3; channel++)
        normalized[0][channel] = V72;

    for (int group = 9; group > 0; group--) {
        int shift = adjustmentFactor[group][0];
        int maximum = adjustmentFactor[group][1];

        for (int channel = 0; channel < 3; channel++) {
            int value = raw[group][channel] + shift;
            int64_t range = group == 9 ? V72 - V15 :
                            V72 - normalized[group + 1][channel];

            normalized[group][channel] =
                V72 - (int64_t)value * range / maximum;
        }
    }

    for (int group = 9; group > 0; group--) {
        int first = firstIdxPerGroup[group];
        int count = first - firstIdxPerGroup[group - 1];

        for (int channel = 0; channel < 3; channel++) {
            int64_t previous = group > 1 ?
                normalized[group - 1][channel] : V72;
            int64_t value = normalized[group][channel];

            for (int offset = 0; offset < count; offset++)
                thresholds[first - offset][channel] =
                    value + (int64_t)offset * (previous - value) / count;
        }
    }
    for (int channel = 0; channel < 3; channel++)
        thresholds[0][channel] = V72;

    for (int slot = 0; slot < 0x42; slot++) {
        int final[10][3] = {{0}};
        int pointer = 0;

        for (int group = 9; group > 0; group--) {
            int shift = adjustmentFactor[group][0];
            int maximum = adjustmentFactor[group][1];

            for (int channel = 0; channel < 3; channel++) {
                int64_t value = thresholds
                    [samsung_amoled_fraction_index[slot][group]][channel];
                int64_t range = V72 - V15;
                int result = (int)((int64_t)maximum * (V72 - value) /
                                   range) - shift;

                if (group != 9) {
                    int64_t next = thresholds
                        [samsung_amoled_fraction_index[slot][group + 1]]
                        [channel];

                    range = V72 - next;
                    result = (int)((int64_t)maximum * (V72 - value) /
                                   range) - shift;
                }

                result += brightnessShiftFactorPerChannelHighMode
                    [slot][group][channel];
                if (result < 0)
                    result = 0;
                if (result > 0xff && group != 9)
                    result = 0xff;
                final[group][channel] = result;
            }
        }
        for (int channel = 0; channel < 3; channel++)
            final[0][channel] = raw[0][channel];

        for (int channel = 0; channel < 3; channel++) {
            for (int group = 2; group < 10; group++)
                output[slot][pointer++] = final[group][channel];
            output[slot][pointer++] = final[1][channel];
            output[slot][pointer++] = (final[9][channel] / 2) & 0x80;
            output[slot][pointer++] = final[0][channel];
        }
    }
}

int main(int argc, char **argv)
{
    displayBrightness_t *reference;
    unsigned char fixed[0x42][33];
    int raw[10][3];
    aux_t aux;
    int differences = 0;
    int maximum_delta = 0;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s /dev/drm_dp_auxN\n", argv[0]);
        return 2;
    }
    aux = dpAuxOpen(argv[1]);
    if (aux < 0) {
        perror("open AUX");
        return 1;
    }
    if (accessParaAuxRegs(aux)) {
        fprintf(stderr, "Private panel registers are unavailable\n");
        return 1;
    }
    __readBrightnessRegisters(aux, raw);
    reference = initBrightness(aux, 1);
    if (!reference) {
        fprintf(stderr, "Reference calibration failed\n");
        return 1;
    }
    fixed_channel_adjustment(raw, fixed);

    for (int slot = 0; slot < 0x42; slot++) {
        for (int byte = 0; byte < 33; byte++) {
            unsigned int expected = reference->channelAdjustment[slot][byte];
            unsigned int actual = fixed[slot][byte];

            if (actual != expected) {
                int delta = abs((int)actual - (int)expected);

                if (differences < 20)
                    printf("slot %d byte %d: fixed=%u reference=%u\n",
                           slot, byte, actual, expected);
                if (delta > maximum_delta)
                    maximum_delta = delta;
                differences++;
            }
        }
    }
    printf("Compared %d bytes: %d rounding differences, maximum delta %d\n",
           0x42 * 33, differences, maximum_delta);
    free(reference);
    dpAuxClose(aux);
    return maximum_delta > 1;
}
