CC = gcc
# NNG-only build. zeromq/nanomsg sources and libs are disabled.
# Fork layout: this Makefile lives in <bench>/bml/, the fork in <bench>/../nng
NNG_SRC = ../../nng
NNG_BUILD = ../../nng/build
CFLAGS = -Wall -Wextra -O3 -march=native -pthread -I$(NNG_SRC)/include -I$(NNG_SRC)
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

# Survey bridge toggle: true 1-to-N broadcast where every subscriber
# replies (needs NNG_SURVEY_QUORUM=sub-count at run time, see below).
# Survey build: `make SURVEY=1` (or `make survey`). Wins over RTT if both set.
ifeq ($(SURVEY),1)
CFLAGS += -DNNG_PUBSUB_SURVEY
endif

# Cumulative-ACK bridge toggle: sack/sackresp + RTT-lite, window of 8,
# one "C<next>[:mask]" per ~8 surveys instead of one ACK per survey.
# SACK build: `make SACK=1` (or `make sack`). Wins over both above.
ifeq ($(SACK),1)
CFLAGS += -DNNG_PUBSUB_SACK
endif

.PHONY: all clean reliable survey sack

all: $(EXEC)

reliable: CFLAGS += -DNNG_PUBSUB_RELIABLE
reliable: $(EXEC)

survey: CFLAGS += -DNNG_PUBSUB_SURVEY
survey: $(EXEC)

sack: CFLAGS += -DNNG_PUBSUB_SACK
sack: $(EXEC)

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
