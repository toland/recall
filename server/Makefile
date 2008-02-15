.SUFFIXES: .erl .beam

.erl.beam:
	erlc -W $<

MODS = recall recall_cmds recall_utils json

compile: ${MODS:%=%.beam}

clean:
	rm -f *.beam erl_crash.dump
