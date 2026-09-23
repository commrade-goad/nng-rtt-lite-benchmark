CC = gcc
# NNG-only build. zeromq/nanomsg sources and libs are disabled.
# Fork layout: this Makefile lives in <bench>/bml/, the fork in <bench>/../nng
NNG_SRC = ../../nng
NNG_BUILD = ../../nng/build
CFLAGS = -Wall -Wextra -O2 -pthread -I$(NNG_SRC)/include -I$(NNG_SRC)
LDFLAGS = -L$(NNG_BUILD) -Wl,-rpath,$(abspath $(NNG_BUILD)) -lnng -pthread -lm
# NNG-only sources (ops_zeromq.c / ops_nanomsg.c intentionally excluded)
SRC = pub-sub.c utils.c ops_nng.c
OBJ = $(SRC:.c=.o)
EXEC = bml-pub-sub

# RTT-lite toggle: the fork's nng_wrapper.h only activates when
# NNG_PUBSUB_RELIABLE is defined. Default (plain `make`) = normal NNG.
# RTT-lite build: `make RTT=1` (or `make reliable`).
ifeq ($(RTT),1)
CFLAGS += -DNNG_PUBSUB_RELIABLE
endif

.PHONY: all clean reliable

all: $(EXEC)

reliable: CFLAGS += -DNNG_PUBSUB_RELIABLE
reliable: $(EXEC)

$(EXEC): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(EXEC)
	rm -rf ../logs logs
	rm -rf 127.0.0.1* benchmark* > /dev/null 2>&1

clean_results_data:
	rm -rf data

clean_all: clean clean_results_data

profiling: CFLAGS += -pg -ltcmalloc
profiling: $(EXEC)
