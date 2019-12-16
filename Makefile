REBAR=rebar3

.PHONY: all compile clean deps clean-deps distclean

all: compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean
	rm -rf ebin .eunit

deps:
	$(REBAR) get-deps

clean-deps:
	$(REBAR) delete-deps
	rm -rf deps/*

distclean: clean clean-deps
