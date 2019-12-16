%%%============================================================================
%%% Copyright 2019 Aleksei Osin
%%%
%%%    Licensed under the Apache License, Version 2.0 (the "License");
%%%    you may not use this file except in compliance with the License.
%%%    You may obtain a copy of the License at
%%%
%%%        http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%    Unless required by applicable law or agreed to in writing, software
%%%    distributed under the License is distributed on an "AS IS" BASIS,
%%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KINA4,, either express or implied.
%%%    See the License for the specific language governing permissions and
%%%    limitations under the License.
%%%============================================================================

%%% @author Aleksei Osin
%%% @copyright 2019 Aleksei Osin
%%% @doc Mocking server

-module(meckanic).
-behaviour(gen_server).

%% API
-export([
    start/2,
    start/3,
    start_link/2,
    start_link/3,
    stop/1,
    attach/2,
    detach/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-type mocked_mod() :: atom().
-type mocked_fun() :: atom().
-type mocked_args() :: [term()].
-type result() :: passthrough | {return, term()} | {exception, throw | error | exit, term()}.
-type state() :: term().
-type handler() :: fun((pid(), mocked_mod(), mocked_fun(), mocked_args(), state()) -> {result(), state()}).

-record(state, {
    handler :: handler(),
    state :: term()
}).

%%==============================================================================
%% Exported functions
%%==============================================================================

start(Handler, State) ->
    gen_server:start(?MODULE, [Handler, State], []).

start(Name, Handler, State) ->
    gen_server:start({local, Name}, ?MODULE, [Handler, State], []).

start_link(Handler, State) ->
    gen_server:start_link(?MODULE, [Handler, State], []).

start_link(Name, Handler, State) ->
    gen_server:start_link({local, Name}, ?MODULE, [Handler, State], []).

stop(Name) ->
    gen_server:call(Name, stop).

attach(Name, Module) ->
    gen_server:call(Name, {attach, Module}).

detach(Name, Module) ->
    gen_server:call(Name, {detach, Module}).

init([Handler, State]) ->
    {ok, #state{handler = Handler, state = State}}.

handle_call({attach, Module}, _From, State) ->
    Reply = mock_module(Module),
    {reply, Reply, State};
handle_call({detach, Module}, _From, State) ->
    Reply = meck:unload(Module),
    {reply, Reply, State};
handle_call({handle_mocked_call, Pid, Module, Function, Args}, _From, State) ->
    #state{handler = Handler, state = State0} = State,
    {Reply, State1} = Handler(Pid, Module, Function, Args, State0),
    {reply, Reply, State#state{state = State1}};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {noreply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%==============================================================================
%% Local functions
%%==============================================================================

mock_module(Module) ->
    Exports = Module:module_info(exports),
    case meck:new(Module) of
        ok ->
            mock_exports(Module, Exports);
        {error, Reason} ->
            {error, Reason}
    end.

mock_exports(Module, [{Function, Arity} | Exports]) ->
    case mock_function(Module, Function, Arity) of
        ok ->
            mock_exports(Module, Exports);
        {error, Reason} ->
            {error, Reason}
    end;
mock_exports(_Module, []) ->
    ok.

mock_function(_Module, Function, _Arity)
  when Function == module_info ->
    ok;
mock_function(Module, Function, Arity)
  when Arity > 16 ->
    {error, {too_many_arguments, {Module, Function, Arity}}};
mock_function(Module, Function, Arity) ->
    meck:expect(Module, Function, make_mocking_fun(self(), Module, Function, Arity)).

make_mocking_fun(Pid, M, F, 0) ->
    fun() ->
        handle_mocked_call(Pid, M, F, [])
    end;
make_mocking_fun(Pid, M, F, 1) ->
    fun(A1) ->
        handle_mocked_call(Pid, M, F, [A1])
    end;
make_mocking_fun(Pid, M, F, 2) ->
    fun(A1, A2) ->
        handle_mocked_call(Pid, M, F, [A1, A2])
    end;
make_mocking_fun(Pid, M, F, 3) ->
    fun(A1, A2, A3) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3])
    end;
make_mocking_fun(Pid, M, F, 4) ->
    fun(A1, A2, A3, A4) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4])
    end;
make_mocking_fun(Pid, M, F, 5) ->
    fun(A1, A2, A3, A4, A5) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5])
    end;
make_mocking_fun(Pid, M, F, 6) ->
    fun(A1, A2, A3, A4, A5, A6) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6])
    end;
make_mocking_fun(Pid, M, F, 7) ->
    fun(A1, A2, A3, A4, A5, A6, A7) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7])
    end;
make_mocking_fun(Pid, M, F, 8) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8])
    end;
make_mocking_fun(Pid, M, F, 9) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9])
    end;
make_mocking_fun(Pid, M, F, 10) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10])
    end;
make_mocking_fun(Pid, M, F, 11) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11])
    end;
make_mocking_fun(Pid, M, F, 12) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12])
    end;
make_mocking_fun(Pid, M, F, 13) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13])
    end;
make_mocking_fun(Pid, M, F, 14) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14])
    end;
make_mocking_fun(Pid, M, F, 15) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15])
    end;
make_mocking_fun(Pid, M, F, 16) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16) ->
        handle_mocked_call(Pid, M, F, [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16])
    end.

handle_mocked_call(Pid, Mod, Fun, Args) ->
    case gen_server:call(Pid, {handle_mocked_call, self(), Mod, Fun, Args}) of
        {return, Result} ->
            Result;
        passthrough ->
            meck:passthrough(Args);
        {exception, Class, Reason} ->
            meck:exception(Class, Reason)
    end.
