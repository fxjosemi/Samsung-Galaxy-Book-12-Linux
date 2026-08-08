CC ?= cc
CFLAGS ?= -O2 -pipe
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic -D_GNU_SOURCE
LDLIBS += -lm

BRIGHTNESS_SOURCES := ../../src/dpAux.c ../../src/brightness.c ../../src/tables.c

.PHONY: all clean

all: generate-fraction-index validate-fixed-point

generate-fraction-index: generate-fraction-index.c $(BRIGHTNESS_SOURCES)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LDLIBS)

validate-fixed-point: validate-fixed-point.c fraction-index.h $(BRIGHTNESS_SOURCES)
	$(CC) $(CFLAGS) -o $@ validate-fixed-point.c $(BRIGHTNESS_SOURCES) \
		$(LDFLAGS) $(LDLIBS)

clean:
	rm -f generate-fraction-index validate-fixed-point
