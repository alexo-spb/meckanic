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
    start/1,
    start/2,
    start_link/1,
    start_link/2,
    stop/0, stop/1,
    attach/2,
    detach/2,
    detach_all/1,
    get_property/2,
    set_property/3,
    unset_property/2,
    subscribe_property/2,
    unsubscribe_property/2,
    wait_property/2
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

-type server_ref() :: atom() | pid().
-type mocked_module() :: atom().
-type mocked_function() :: atom().
-type args() :: [term()].

-type result() ::
    pass |
    {return, term()} |
    {exception, term()} |
    {exception, throw | error | exit, term()}.

-type handler() :: fun((pid(), mocked_module(), mocked_function(), arity(), args()) -> result()).

-type property_event() :: {set, term()} | unset.

-record(state, {
    handler :: handler(),
    properties = #{} :: map(),
    subscriptions = #{} :: map()
}).

-define(SERVER, ?MODULE).

%%==============================================================================
%% Exported functions
%%==============================================================================

-spec start(handler()) -> {ok, pid()} | {error, term()}.
start(Handler) ->
    start(?SERVER, Handler).

-spec start(atom(), handler()) -> {ok, pid()} | {error, term()}.
start(Name, Handler) ->
    gen_server:start({local, Name}, ?MODULE, Handler, []).

-spec start_link(handler()) -> {ok, pid()} | {error, term()}.
start_link(Handler) ->
    start_link(?SERVER, Handler).

-spec start_link(atom(), handler()) -> {ok, pid()} | {error, term()}.
start_link(Name, Handler) ->
    gen_server:start_link({local, Name}, ?MODULE, Handler, []).

-spec stop() -> ok.
stop() ->
    stop(?SERVER).

-spec stop(server_ref()) -> ok.
stop(ServerRef) ->
    gen_server:call(ServerRef, stop).

-spec attach(server_ref(), module()) -> ok | {error, term()}.
attach(ServerRef, Mod) ->
    gen_server:call(ServerRef, {attach, Mod}).

-spec detach(server_ref(), module()) -> ok.
detach(ServerRef, Mod) ->
    gen_server:call(ServerRef, {detach, Mod}).

-spec detach_all(server_ref()) -> [module()].
detach_all(ServerRef) ->
    gen_server:call(ServerRef, detach).

-spec get_property(server_ref(), term()) -> term().
get_property(ServerRef, Key) ->
    gen_server:call(ServerRef, {get_property, Key}).

-spec set_property(server_ref(), term(), term()) -> ok.
set_property(ServerRef, Key, Value) ->
    gen_server:call(ServerRef, {set_property, Key, Value}).

-spec unset_property(server_ref(), term()) -> ok.
unset_property(ServerRef, Key) ->
    gen_server:call(ServerRef, {unset_property, Key}).

-spec subscribe_property(server_ref(), term()) -> ok.
subscribe_property(ServerRef, Key) ->
    gen_server:call(ServerRef, {subscribe_property, self(), Key}).

-spec unsubscribe_property(server_ref(), term()) -> ok.
unsubscribe_property(ServerRef, Key) ->
    gen_server:call(ServerRef, {unsubscribe_property, self(), Key}),
    drain_messages(Key).

-spec wait_property(term(), pos_integer()) -> {ok, property_event()} | timeout().
wait_property(Key, Timeout) ->
    receive
        {meckanic, {property, Key}, Event} ->
            {ok, Event}
    after
        Timeout ->
            timeout
    end.

%% gen_server callback
init(Handler) ->
    process_flag(trap_exit, true),
    State = #state{handler = Handler},
    {ok, State}.

%% gen_server callback
handle_call({attach, Mod}, _From, State) ->
    Reply = handle_attach(Mod, State),
    {reply, Reply, State};
handle_call(detach, _From, State) ->
    Unloaded = meck:unload(),
    {reply, Unloaded, State};
handle_call({detach, Mod}, _From, State) ->
    meck:unload(Mod),
    {reply, ok, State};
handle_call({get_property, Key}, _From, State) ->
    Value = handle_get_property(Key, State),
    {reply, Value, State};
handle_call({set_property, Key, Value}, _From, State0) ->
    State1 = handle_set_property(Key, Value, State0),
    {reply, ok, State1};
handle_call({unset_property, Key}, _From, State0) ->
    State1 = handle_unset_property(Key, State0),
    {reply, ok, State1};
handle_call({subscribe_property, Pid, Key}, _From, State0) ->
    {Value, State1} = handle_subscribe_property(Pid, Key, State0),
    {reply, Value, State1};
handle_call({unsubscribe_property, Pid, Key}, _From, State0) ->
    State1 = handle_unsubscribe_property(Pid, Key, State0),
    {reply, ok, State1};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {noreply, State}.

%% gen_server callback
handle_cast(_Request, State) ->
    {noreply, State}.

%% gen_server callback
handle_info({'DOWN', _Ref, _Type, Pid, _Info}, State0) ->
    State1 = handle_subcriber_down(Pid, State0),
    {noreply, State1};
handle_info(_Info, State) ->
    {noreply, State}.

%% gen_server callback
terminate(_Reason, _State) ->
    meck:unload(),
    ok.

%% gen_server callback
code_change(_OldVsn, Handler, _Extra) ->
    {ok, Handler}.

%%==============================================================================
%% Local functions
%%==============================================================================

handle_attach(Mod, State) ->
    #state{handler = Handler} = State,
    Exports = Mod:module_info(exports),
    meck:new(Mod),
    mock_exports(Handler, Mod, Exports).

mock_exports(Handler, Mod, [{Fun, Arity} | Exports]) ->
    case mock_function(Handler, Mod, Fun, Arity) of
        ok ->
            mock_exports(Handler, Mod, Exports);
        {error, Reason} ->
            {error, Reason}
    end;
mock_exports(_Handler, _Mod, []) ->
    ok.

mock_function(_Handler, _Mod, Fun, _Arity)
  when Fun == behaviour_info;
       Fun == module_info ->
    ok;
mock_function(_Handler, Mod, Fun, Arity)
  when Arity > 16 ->
    {error, {too_big_arity, {Mod, Fun, Arity}}};
mock_function(Handler, Mod, Fun, Arity) ->
    meck:expect(Mod, Fun, make_mocking_fun(Handler, Mod, Fun, Arity)).

make_mocking_fun(Handler, Mod, Fun, 0 = Arity) ->
    fun() ->
        handle_mocked_call(Handler, Mod, Fun, Arity, [])
    end;
make_mocking_fun(Handler, Mod, Fun, 1 = Arity) ->
    fun(A1) ->
        Args = [A1],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 2 = Arity) ->
    fun(A1, A2) ->
        Args = [A1, A2],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 3 = Arity) ->
    fun(A1, A2, A3) ->
        Args = [A1, A2, A3],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 4 = Arity) ->
    fun(A1, A2, A3, A4) ->
        Args = [A1, A2, A3, A4],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 5 = Arity) ->
    fun(A1, A2, A3, A4, A5) ->
        Args = [A1, A2, A3, A4, A5],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 6 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6) ->
        Args = [A1, A2, A3, A4, A5, A6],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 7 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7) ->
        Args = [A1, A2, A3, A4, A5, A6, A7],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 8 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 9 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 10 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 11 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 12 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 13 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 14 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 15 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end;
make_mocking_fun(Handler, Mod, Fun, 16 = Arity) ->
    fun(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16) ->
        Args = [A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16],
        handle_mocked_call(Handler, Mod, Fun, Arity, Args)
    end.

handle_mocked_call(Handler, Mod, Fun, Arity, Args) ->
    case Handler(self(), Mod, Fun, Arity, Args) of
        pass ->
            meck:passthrough(Args);
        {return, Result} ->
            Result;
        {exception, Class, Reason} ->
            meck:exception(Class, Reason)
    end.

handle_get_property(Key, State) ->
    #state{properties = Properties} = State,
    maps:get(Key, Properties, undefined).

handle_set_property(Key, Value, State) ->
    #state{properties = Properties0} = State,
    case maps:find(Key, Properties0) of
        {ok, Value} ->
            State;
        _ ->
            Properties1 = maps:put(Key, Value, Properties0),
            #state{subscriptions = Subscriptions} = State,
            case maps:find({key, Key}, Subscriptions) of
                {ok, Pids} ->
                    [notify_property_set(Pid, Key, Value) || Pid <- Pids];
                error ->
                    ok
            end,
            State#state{properties = Properties1}
    end.

notify_property_set(Pid, Key, Value) ->
    Message = {meckanic, {property, Key}, {set, Value}},
    erlang:send(Pid, Message).

handle_unset_property(Key, State) ->
    #state{properties = Properties0} = State,
    case maps:is_key(Key, Properties0) of
        true ->
            Properties1 = maps:remove(Key, Properties0),
            #state{subscriptions = Subscriptions} = State,
            case maps:find({key, Key}, Subscriptions) of
                {ok, Pids} ->
                    [notify_property_unset(Pid, Key) || Pid <- Pids];
                error ->
                    ok
            end,
            State#state{properties = Properties1};
        false ->
            State
    end.

notify_property_unset(Pid, Key) ->
    Message = {meckanic, {property, Key}, unset},
    erlang:send(Pid, Message).

handle_subscribe_property(Pid, Key, State) ->
    #state{properties = Properties, subscriptions = Subscriptions0} = State,
    Value = maps:get(Key, Properties, undefined),
    Subscriptions1 = add_subscription(Pid, Key, Subscriptions0),
    {Value, State#state{subscriptions = Subscriptions1}}.

add_subscription(Pid, Key, Subscribtions0) ->
    Subscriptions1 = case maps:find(Pid, Subscribtions0) of
        {ok, {Ref, Keys0}} ->
            Keys1 = ordsets:add_element(Key, Keys0),
            maps:put(Pid, {Ref, Keys1}, Subscribtions0);
        error ->
            Ref = erlang:monitor(process, Pid),
            maps:put(Pid, {Ref, [Key]}, Subscribtions0)
    end,
    Pids0 = maps:get({key, Key}, Subscriptions1, []),
    Pids1 = ordsets:add_element(Pid, Pids0),
    maps:put({key, Key}, Pids1, Subscriptions1).

handle_unsubscribe_property(Pid, Key, State) ->
    #state{subscriptions = Subscriptions0} = State,
    Subscriptions1 = del_subscription(Pid, Key, Subscriptions0),
    State#state{subscriptions = Subscriptions1}.

del_subscription(Pid, Key, Subscriptions0) ->
    Subscriptions1 = case maps:find(Pid, Subscriptions0) of
        {ok, {Ref, [Key]}} ->
            erlang:demonitor(Ref),
            maps:remove(Pid, Subscriptions0);
        {ok, {Ref, Keys0}} ->
            Keys1 = ordsets:del_element(Key, Keys0),
            maps:put(Pid, {Ref, Keys1}, Subscriptions0);
        error ->
            Subscriptions0
    end,
    case maps:find({key, Key}, Subscriptions1) of
        {ok, [Pid]} ->
            maps:remove({key, Key}, Subscriptions1);
        {ok, Pids0} ->
            Pids1 = ordsets:del_element(Pid, Pids0),
            maps:put({key, Key}, Pids1, Subscriptions1);
        error ->
            Subscriptions1
    end.

handle_subcriber_down(Pid, State) ->
    #state{subscriptions = Subscriptions0} = State,
    Subscriptions1 = del_subscriptions(Pid, Subscriptions0),
    State#state{subscriptions = Subscriptions1}.

del_subscriptions(Pid, Subscriptions0) ->
    case maps:find(Pid, Subscriptions0) of
        {ok, {_Ref, Keys}} ->
            Subscriptions1 = maps:remove(Pid, Subscriptions0),
            Fun = fun(Key, Subscriptions) ->
                case maps:find({key, Key}, Subscriptions) of
                    {ok, [Pid]} ->
                        maps:remove({key, Key}, Subscriptions);
                    {ok, Pids0} ->
                        Pids1 = ordsets:del_element(Pid, Pids0),
                        maps:put({key, Key}, Pids1, Subscriptions);
                    error ->
                        Subscriptions
                end
            end,
            lists:foldl(Fun, Subscriptions1, Keys);
        error ->
            Subscriptions0
    end.

drain_messages(Key) ->
    receive
        {meckanic, {property, Key}, _} ->
            drain_messages(Key)
    after
        0 ->
            ok
    end.
