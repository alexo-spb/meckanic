-module(mechanic_test).

-include_lib("eunit/include/eunit.hrl").

api_test_() ->
    [
        attach_fixture(),
        detach_fixture(),
        properties_fixture(),
        subscriptions_fixture()
    ].

attach_fixture() ->
    {
        foreach,
        fun() ->
            Handler = fun(_Pid, Mod, Fun, Arity, Args) ->
                meckanic:set_property(x, called, [Mod, Fun, Arity, Args]),
                meckanic:get_property(x, result)
            end,
            {ok, _Pid} = meckanic:start(x, Handler)
        end,
        fun(_) ->
            ok = meckanic:stop(x)
        end,
        [
            {
                "Attach and call module:function/0 with pass",
                fun() ->
                    meckanic:set_property(x, result, pass),
                    ok = meckanic:attach(x, module),
                    ?assertEqual(ok, module:function()),
                    Called = [module, function, 0, []],
                    ?assertEqual(Called, meckanic:get_property(x, called))
                end
            },
            {
                "Attach and call module:function/1 with pass",
                fun() ->
                    meckanic:set_property(x, result, pass),
                    ok = meckanic:attach(x, module),
                    ?assertEqual([a], module:function(a)),
                    Called = [module, function, 1, [a]],
                    ?assertEqual(Called, meckanic:get_property(x, called))
                end
            },
            {
                "Attach and call module:function/1 with return",
                fun() ->
                    meckanic:set_property(x, result, {return, [b]}),
                    ok = meckanic:attach(x, module),
                    ?assertEqual([b], module:function(a)),
                    Called = [module, function, 1, [a]],
                    ?assertEqual(Called, meckanic:get_property(x, called))
                end
            }
        ]
    }.

detach_fixture() ->
    {
        foreach,
        fun() ->
            Handler = fun(_Pid, _Mod, _Fun, _Arity, _Args) ->
                error(should_never_happen)
            end,
            {ok, _Pid} = meckanic:start(x, Handler),
            ok = meckanic:attach(x, module)
        end,
        fun(_) ->
            ok = meckanic:stop(x)
        end,
        [
            {
                "Detach and call module:function/1",
                fun() ->
                    ok = meckanic:detach(x, module),
                    ?assertEqual([a], module:function(a))
                end
            }
        ]
    }.

properties_fixture() ->
    {
        foreach,
        fun() ->
            Handler = fun(_Pid, _Mod, _Fun, _Arity, _Args) ->
                error(should_never_happen)
            end,
            {ok, _Pid} = meckanic:start(x, Handler)
        end,
        fun(_) ->
            ok = meckanic:stop(x)
        end,
        [
            {
                "Set property",
                fun() ->
                    ?assertEqual(undefined, meckanic:get_property(x, key)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 1)),
                    ?assertEqual(1, meckanic:get_property(x, key)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 2)),
                    ?assertEqual(2, meckanic:get_property(x, key))
                end
            },
            {
                "Unset property",
                fun() ->
                    ?assertEqual(ok, meckanic:set_property(x, key, 1)),
                    ?assertEqual(ok, meckanic:unset_property(x, key)),
                    ?assertEqual(undefined, meckanic:get_property(x, key))
                end
            }
        ]
    }.

subscriptions_fixture() ->
    {
        foreach,
        fun() ->
            Handler = fun(_Pid, _Mod, _Fun, _Arity, _Args) ->
                error(should_never_happen)
            end,
            {ok, _Pid} = meckanic:start(x, Handler)
        end,
        fun(_) ->
            ok = meckanic:stop(x)
        end,
        [
            {
                "Subscribe on property events",
                fun() ->
                    ?assertEqual(undefined, meckanic:subscribe_property(x, key)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 1)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 2)),
                    ?assertEqual(ok, meckanic:unset_property(x, key)),
                    ?assertEqual({ok, {set, 1}}, meckanic:wait_property(key, 0)),
                    ?assertEqual({ok, {set, 2}}, meckanic:wait_property(key, 0)),
                    ?assertEqual({ok, unset}, meckanic:wait_property(key, 0))
                end
            },
            {
                "Unsubscribe from property events",
                fun() ->
                    ?assertEqual(undefined, meckanic:subscribe_property(x, key)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 1)),
                    ?assertEqual(ok, meckanic:set_property(x, key, 2)),
                    ?assertEqual(ok, meckanic:unset_property(x, key)),
                    ?assertEqual(ok, meckanic:unsubscribe_property(x, key)),
                    ?assertEqual(timeout, meckanic:wait_property(key, 0)),
                    ?assertEqual(timeout, meckanic:wait_property(key, 0)),
                    ?assertEqual(timeout, meckanic:wait_property(key, 0))
                end
            }
        ]
    }.
