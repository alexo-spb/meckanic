REBAR=./rebar3

.PHONY: all compile deps test clean

all: compile

compile:
	$(REBAR) compile

deps:
	$(REBAR) get-deps

test:
	$(REBAR) xref
	$(REBAR) eunit
	$(REBAR) dialyzer

clean:
	$(REBAR) clean
